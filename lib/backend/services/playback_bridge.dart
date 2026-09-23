/// Ponte de reprodução: dona dos dois lados libmpv e da lógica de sincronização.
///
/// O vídeo é composto na mesma cena Flutter (widgets `Video`): wipe/colunas/blink
/// são só widgets, sem camadas nativas.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;

import '../models/models.dart';
import '../state/settings.dart';
import 'mpv_side.dart';

class RuntimeState {
  const RuntimeState({this.ready = false, this.error});

  final bool ready;
  final String? error;

  RuntimeState copyWith({bool? ready, Object? error = _sentinel}) => RuntimeState(
        ready: ready ?? this.ready,
        error: error == _sentinel ? this.error : error as String?,
      );
}

const Object _sentinel = Object();

const List<Side> _sides = [Side.a, Side.b, Side.c, Side.d];

class PlaybackBridge extends ChangeNotifier {
  PlaybackBridge();

  final Map<Side, MpvSide> _players = {};
  final Map<Side, PlayerState> _state = {
    for (final side in _sides) side: const PlayerState(),
  };
  final Map<Side, StreamSubscription<dynamic>> _subs = {};

  /// Número de vídeos ativos na view (1..4) — espelha `AppSettings.viewCount`.
  int _viewCount = 2;

  RuntimeState runtime = const RuntimeState();

  /// Lado(s) onde mostrar o toast de "silenciado por outro áudio".
  Set<Side> dualAudioToastSides = <Side>{};

  /// HUD de frame (aparece ao passar 1 frame com as setas e só desaparece
  /// quando o play volta a arrancar).
  bool frameHudVisible = false;

  /// Lado(s) ainda à espera de o seek/decode assentar (mostra o spinner).
  final Set<Side> _syncingSides = <Side>{};

  bool isSideSyncing(Side side) => _syncingSides.contains(side);

  void _clearSyncing() {
    if (_syncingSides.isEmpty) return;
    _syncingSides.clear();
    notifyListeners();
  }

  /// Segundos de buffer já em cache por lado (-1 = sem dado).
  final Map<Side, double> _bufferSeconds = {
    for (final side in _sides) side: -1,
  };

  /// Bytes em memória no demuxer cache por lado (`null` = sem dado).
  final Map<Side, int?> _bufferBytes = {for (final side in _sides) side: null};
  Timer? _bufferTimer;

  double bufferSeconds(Side side) => _bufferSeconds[side] ?? -1;

  /// Tamanho do buffer em memória (bytes); `null` enquanto desconhecido.
  int? bufferBytes(Side side) => _bufferBytes[side];

  /// Resolução (`3840x2160`) e codec (`h264`) por lado, lidos com retry
  /// após o load (estatísticas por vídeo); `null` enquanto desconhecido.
  final Map<Side, String?> _videoSize = {for (final side in _sides) side: null};
  final Map<Side, String?> _videoCodec = {for (final side in _sides) side: null};
  final Map<Side, String?> _audioCodec = {for (final side in _sides) side: null};
  final Map<Side, String?> _displaySize = {for (final side in _sides) side: null};
  final Map<Side, int?> _fileSize = {for (final side in _sides) side: null};
  final Map<Side, int?> _droppedFrames = {for (final side in _sides) side: null};

  String? videoSize(Side side) => _videoSize[side];
  String? videoCodec(Side side) => _videoCodec[side];
  String? audioCodec(Side side) => _audioCodec[side];
  String? displaySize(Side side) => _displaySize[side];
  int? fileSize(Side side) => _fileSize[side];
  int? droppedFrames(Side side) => _droppedFrames[side];

  /// Velocidade efetiva de um lado (inclui a correção de drift).
  double rateOf(Side side) => _rate[side] ?? 1.0;

  /// Desvio atual entre os lados, em milissegundos (líder − pior seguidor).
  double get driftMs {
    final loaded = loadedSides();
    if (loaded.length < 2) return 0;
    final master = _masterSide();
    final masterProj = _projected(master);
    var worst = 0.0;
    for (final side in loaded) {
      if (side == master) continue;
      final drift = (masterProj - _projected(side)) * 1000.0;
      if (drift.abs() > worst.abs()) worst = drift;
    }
    return worst;
  }

  /// Número do frame mostrado. Durante o frame-step usa o cursor exato
  /// (`_stepTime`) em vez do `time-pos` reportado, que salta para o frame
  /// mais próximo de cada vídeo. O seguidor usa `floor` (+ epsilon): o seu
  /// número só avança quando o tempo cruza a fronteira do *próprio* frame.
  int frameNumber(Side side) {
    final fps = fpsOf(side);
    final time = _stepTime ?? _state[side]!.position;
    final value = ((time + 0.0001) * fps).floor();
    return value < 0 ? 0 : value;
  }

  /// FPS do conteúdo por lado (pode ainda estar a ser detetado).
  double fpsOf(Side side) => _fps[side] ?? 30;

  void _showFrameHud() {
    frameHudVisible = true;
  }

  void _hideFrameHud() {
    if (!frameHudVisible) return;
    frameHudVisible = false;
    notifyListeners();
  }

  /// Notificado quando um ficheiro falha a abrir (abre o modal de assistência).
  void Function(Side side, String? path, String message)? onLoadError;

  bool _initialized = false;
  bool _scrubbing = false;
  bool _holdActive = false;

  /// Hold em modo jog (reprodução contínua à rate das setas).
  /// Enquanto activo, o drift sync corre sobre `_jogRate` em vez de bloquear.
  bool _jogActive = false;
  double _jogRate = 1.0;

  /// +1 = frente, −1 = trás (`play-direction` do mpv).
  int _jogDirection = 1;

  /// Invalida um `startJog` em voo quando o utilizador solta a seta.
  int _jogEpoch = 0;

  Timer? _dualAudioTimer;

  /// Lado dono do áudio (primeiro com áudio detectado; os outros ficam
  /// mutados na transição, sem re-muter desmutes manuais).
  Side? _audioOwner;

  /// Mute explícito do utilizador por lado. `true`/`false` = preferência
  /// guardada; ausente = sem preferência (deixa a política decidir).
  final Map<Side, bool> _sideMute = <Side, bool>{};

  /// Mute global (mestre). Precedência do estado efetivo: mute explícito do
  /// lado > mute global > unmute explícito do lado > política (dono do áudio).
  bool _globalMuted = false;

  /// Volume global aplicado a todos os lados.
  double _globalVolume = 100;

  /// FPS do conteúdo por lado (líder do frame-step).
  final Map<Side, double> _fps = {for (final side in _sides) side: 30};

  /// Rotação do vídeo no próprio eixo (0/90/180/270) por lado — property
  /// mpv `video-rotate`.
  final Map<Side, int> _videoRotation = {for (final side in _sides) side: 0};

  /// Instante em que a posição de cada lado foi conhecida (microssegundos).
  final Map<Side, int> _stampMicros = {for (final side in _sides) side: 0};

  /// Cursor exato do frame-step: garante que cada passo avança exatamente
  /// `1/fps` do lado com maior FPS, sem depender do `time-pos` quantizado que
  /// o mpv reporta (que salta para o frame mais próximo).
  double? _stepTime;

  /// Folga da correção de drift (além de um frame do lado mais lento). Abaixo
  /// disto o desvio é só a quantização natural dos frames, não desincronia.
  static const double _driftSlack = 0.005;

  /// Controlador proporcional de sincronização. O mpv corrige o pitch
  /// (`audio-pitch-correction`), por isso mexer na velocidade não altera o tom
  /// — é a forma suave de re-sincronizar, sem pausar nem fazer seek.
  static const double _driftGain = 0.8;
  static const double _driftMaxRateDelta = 0.12;
  static const int _driftTickMs = 100;

  /// Prontidão após um seek: verificação de posição a cada 5 ms, com folga
  /// mínima para o `vo` apresentar o frame antes de arrancar.
  static const Duration _readyPoll = Duration(milliseconds: 5);
  static const Duration _readySettle = Duration(milliseconds: 24);
  static const Duration _readyTimeout = Duration(seconds: 4);

  /// Velocidade atualmente aplicada a cada lado.
  final Map<Side, double> _rate = {for (final side in _sides) side: 1.0};

  /// Base da velocidade de reprodução escolhida pelo utilizador (o drift
  /// aplica o delta por cima desta base, nunca sobre 1.0 fixo).
  double _userRate = 1.0;

  /// Frames avançados por toque/iteração das setas (definição do utilizador).
  int _frameStepCount = 1;

  Timer? _driftTimer;

  bool get initialized => _initialized;

  MpvSide sideOf(Side side) => _players[side]!;
  PlayerState stateOf(Side side) => _state[side]!;

  /// Lados visíveis na view atual (1º..Nº de `Side.values`).
  List<Side> activeSides() => Side.forViewCount(_viewCount);

  /// Número de vídeos ativo na view (1..4).
  int get viewCount => clampViewCount(_viewCount);

  /// Lados visíveis e com vídeo carregado (são estes que participam na
  /// reprodução/sincronia — vídeos carregados mas ocultos ficam em pausa).
  List<Side> loadedSides() => activeSides()
      .where((side) => _state[side]!.loaded)
      .toList(growable: false);

  bool isPlaying() => loadedSides().any((side) => !_state[side]!.paused);

  bool isEnded() {
    final loaded = loadedSides();
    if (loaded.isEmpty) return false;
    if (loaded.any((side) => _state[side]!.ended)) return true;
    final reference = _state[authority()]!;
    return reference.loaded &&
        reference.duration > 0 &&
        reference.paused &&
        reference.position >= reference.duration - 0.05;
  }

  Side authority() {
    final loaded = loadedSides();
    if (loaded.isEmpty) return Side.a;
    for (final side in loaded) {
      if (!_state[side]!.paused) return side;
    }
    return loaded.first;
  }

  double _projected(Side side) {
    final state = _state[side]!;
    if (state.paused) return state.position;
    final stamp = _stampMicros[side]!;
    if (stamp == 0) return state.position;
    final elapsed =
        (DateTime.now().microsecondsSinceEpoch - stamp) / 1000000.0;
    final signed = _jogActive && _jogDirection < 0 ? -elapsed : elapsed;
    return state.position + signed.clamp(-1.0, 1.0);
  }

  /// Duração de um frame do lado (segundos).
  double _framePeriod(Side side) {
    final fps = _fps[side] ?? 30;
    return fps > 0.1 ? 1.0 / fps : 1 / 30.0;
  }

  /// Mestre do relógio: o lado com mais FPS (granularidade mais fina = melhor
  /// referência). Empate → primeiro lado ativo carregado.
  Side _masterSide() {
    final loaded = loadedSides();
    if (loaded.isEmpty) return Side.a;
    var best = loaded.first;
    var bestFps = _fps[best] ?? 30;
    for (final side in loaded.skip(1)) {
      final fps = _fps[side] ?? 30;
      if (fps > bestFps + 0.001) {
        best = side;
        bestFps = fps;
      }
    }
    return best;
  }

  /// Um desvio só conta como desincronia quando passa de um frame inteiro do
  /// lado mais lento: abaixo disso é a quantização natural dos frames.
  double get _driftTolerance {
    final loaded = loadedSides();
    var maxPeriod = 0.0;
    for (final side in loaded.isEmpty ? _sides : loaded) {
      final period = _framePeriod(side);
      if (period > maxPeriod) maxPeriod = period;
    }
    return maxPeriod + _driftSlack;
  }

  // --- Regras de sincronia -------------------------------------------------

  /// FPS iguais (≈0,5%) => os dois vídeos partilham a grelha de frames e podem
  /// ficar presos ao **mesmo número de frame**. FPS diferentes => não há grelha
  /// comum, alinha-se só no tempo (uma única verificação de posição).
  bool get _frameLocked {
    final loaded = loadedSides();
    if (loaded.length < 2) return false;
    final reference = _fps[loaded.first] ?? 30;
    if (reference <= 0.1) return false;
    for (final side in loaded.skip(1)) {
      final fps = _fps[side] ?? 30;
      if (fps <= 0.1) return false;
      final slower = fps < reference ? fps : reference;
      if ((fps - reference).abs() / slower >= 0.005) return false;
    }
    return true;
  }

  /// Encaixa `time` na grelha de frames (só quando os FPS são iguais). Com FPS
  /// diferentes devolve o próprio instante: não há grelha partilhada onde
  /// encaixar sem empurrar um dos lados para outro frame.
  double _alignToFrameGrid(double time) {
    final target = time < 0 ? 0.0 : time;
    if (!_frameLocked) return target;
    final fps = _fps[_masterSide()] ?? 30;
    if (fps <= 0.1) return target;
    return (target * fps).round() / fps;
  }

  /// `true` quando o lado terminou o seek e já tem o frame alvo pronto a
  /// mostrar: sem `seeking`, sem `paused-for-cache` e com o `time-pos` na
  /// posição pedida. Confirmar o `time-pos` evita aceitar uma leitura anterior
  /// ao próprio seek, porque a flag `seeking` pode chegar atrasada.
  Future<bool> _sideReady(Side side, double target, double tolerance) async {
    final native = _players[side]?.native;
    if (native == null) return true;
    try {
      if ((await native.getProperty('seeking')).trim() == 'yes') return false;
      if ((await native.getProperty('paused-for-cache')).trim() == 'yes') {
        return false;
      }
      final raw = (await native.getProperty('time-pos')).trim();
      final position = double.tryParse(raw);
      if (position == null) return false;
      return (position - target).abs() <= tolerance;
    } catch (_) {
      return true;
    }
  }

  /// Espera até os dois lados estarem parados no **mesmo instante** com o frame
  /// pronto a apresentar. Marca os lados ainda não prontos como "a sincronizar"
  /// (spinner no player) e limpa o estado ao sair. Vale para FPS iguais e
  /// diferentes: o encaixe na grelha (quando aplicável) já foi feito antes,
  /// no `_alignToFrameGrid`.
  Future<void> _waitUntilBothReady(List<Side> loaded, double target) async {
    final tolerance = _driftTolerance;
    final deadline = DateTime.now().add(_readyTimeout);
    try {
      while (DateTime.now().isBefore(deadline)) {
        final ready =
            await Future.wait(loaded.map((side) => _sideReady(side, target, tolerance)));
        var changed = false;
        for (var i = 0; i < loaded.length; i++) {
          if (ready[i]) {
            changed = _syncingSides.remove(loaded[i]) || changed;
          } else {
            changed = _syncingSides.add(loaded[i]) || changed;
          }
        }
        if (ready.every((value) => value)) {
          // Folga mínima para o `vo` apresentar o frame antes do `play`.
          await Future<void>.delayed(_readySettle);
          return;
        }
        if (changed) notifyListeners();
        await Future<void>.delayed(_readyPoll);
      }
    } finally {
      _clearSyncing();
    }
  }

  // --- Ciclo de vida -------------------------------------------------------

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      for (final side in _sides) {
        final mpv = MpvSide(side);
        await mpv.init();
        _players[side] = mpv;
        _wire(side, mpv);
      }
      runtime = runtime.copyWith(ready: true, error: null);
      _driftTimer = Timer.periodic(
          const Duration(milliseconds: _driftTickMs), (_) => _syncDrift());
      _bufferTimer =
          Timer.periodic(const Duration(milliseconds: 500), (_) => _pollBuffers());
    } catch (error) {
      runtime = runtime.copyWith(ready: false, error: error.toString());
    }
    notifyListeners();
  }

  void _wire(Side side, MpvSide mpv) {
    final stream = mpv.player.stream;
    _subs[side] = stream.position.listen((value) {
      final seconds = value.inMilliseconds / 1000.0;
      _setState(side, (s) => s.copyWith(position: seconds), stamp: true);
    });
    // O resto dos streams são guardados noutras subscrições.
    stream.duration.listen((value) {
      _setState(side, (s) => s.copyWith(duration: value.inMilliseconds / 1000.0));
    });
    stream.playing.listen((playing) {
      _setState(side, (s) => s.copyWith(paused: !playing, ended: playing ? false : s.ended));
    });
    stream.completed.listen((completed) {
      if (completed) {
        final duration = _state[side]!.duration;
        _setState(side, (s) => s.copyWith(paused: true, ended: true, position: duration));
      }
    });
    stream.volume.listen((volume) {
      _setState(side, (s) => s.copyWith(volume: volume));
    });
    stream.error.listen((message) {
      if (message.trim().isEmpty) return;
      _setState(side, (s) => s.copyWith(error: message));
    });
    stream.track.listen((track) {
      final hasAudio = track.audio.id.isNotEmpty;
      _setState(side, (s) => s.copyWith(hasAudio: hasAudio));
      _applyAudioPolicy();
    });
  }

  void _setState(Side side, PlayerState Function(PlayerState) transform,
      {bool stamp = false}) {
    if (stamp) {
      _stampMicros[side] = DateTime.now().microsecondsSinceEpoch;
    }
    _state[side] = transform(_state[side]!);
    notifyListeners();
  }

  // --- Carregamento --------------------------------------------------------

  Future<void> loadFile(Side side, String path) async {
    final mpv = _players[side];
    if (mpv == null) return;
    _stepTime = null;
    _fps[side] = 30;
    _bufferSeconds[side] = -1;
    _bufferBytes[side] = null;
    _videoSize[side] = null;
    _videoCodec[side] = null;
    _audioCodec[side] = null;
    _displaySize[side] = null;
    _fileSize[side] = null;
    _droppedFrames[side] = null;
    _syncingSides.remove(side);
    // Ficheiro novo: a preferência de mudo do lado anterior não se aplica —
    // a política (dono do áudio) decide de raiz e muta o novo lado quando
    // outro vídeo já é dono.
    _sideMute.remove(side);
    _state[side] = PlayerState(
      loaded: false,
      path: path,
      name: _fileName(path),
      position: 0,
      paused: true,
      volume: _state[side]!.volume,
    );
    _stampMicros[side] = DateTime.now().microsecondsSinceEpoch;
    notifyListeners();

    try {
      await mpv.player.open(Media(path), play: false);
      _state[side] = _state[side]!.copyWith(loaded: true, error: null, ended: false);
      // O `track` (hasAudio) pode ter disparado ainda com `loaded: false`
      // (fora do loadedSides da política) — reaplica agora para garantir que
      // o novo lado fica mudo quando outro já tem áudio.
      _applyAudioPolicy();
      notifyListeners();
      // O `container-fps` só fica disponível depois de o ficheiro estar
      // identificado — dispara a leitura com retry em background, sem bloquear
      // o carregamento (esta era a causa de os dois lados ficarem em 30 FPS).
      unawaited(_readFps(side));
      unawaited(_readVideoInfo(side));
      unawaited(_applyVideoRotation(side));
      await _alignAfterLoad(side);
    } catch (error) {
      _state[side] = _state[side]!.copyWith(loaded: false, error: error.toString());
      notifyListeners();
      onLoadError?.call(side, path, error.toString());
    }
  }

  Future<void> unloadSide(Side side) async {
    final mpv = _players[side];
    if (mpv == null) return;
    _stepTime = null;
    _fps[side] = 30;
    _bufferSeconds[side] = -1;
    _bufferBytes[side] = null;
    _videoSize[side] = null;
    _videoCodec[side] = null;
    _audioCodec[side] = null;
    _displaySize[side] = null;
    _fileSize[side] = null;
    _droppedFrames[side] = null;
    _syncingSides.remove(side);
    try {
      await mpv.player.stop();
    } catch (_) {}
    _state[side] = PlayerState(volume: _state[side]!.volume);
    if (_audioOwner == side) _audioOwner = null;
    _sideMute.remove(side);
    _stampMicros[side] = DateTime.now().microsecondsSinceEpoch;
    notifyListeners();
    _applyAudioPolicy();
  }

  /// Lê o FPS do lado, com retry: tenta `container-fps` e `estimated-vf-fps`
  /// até 3 s (50 ms entre tentativas), parando se o ficheiro mudar. Notifica
  /// quando o valor é obtido (o líder do frame-step e o HUD dependem dele).
  Future<void> _readFps(Side side) async {
    final native = _players[side]?.native;
    if (native == null) return;
    final watchedPath = _state[side]!.path;
    for (var attempt = 0; attempt < 60; attempt++) {
      final state = _state[side]!;
      if (!state.loaded || state.path != watchedPath) return;
      for (final property in const ['container-fps', 'estimated-vf-fps']) {
        try {
          final raw = await native.getProperty(property);
          final value = double.tryParse(raw.trim());
          if (value != null && value.isFinite && value > 0.1) {
            if ((_fps[side]! - value).abs() > 0.01) {
              _fps[side] = value;
              notifyListeners();
            } else {
              _fps[side] = value;
            }
            return;
          }
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// Lê resolução/codec/display/tamanho do lado, com retry (só disponíveis
  /// depois de o ficheiro estar identificado). Notifica quando chegam — as
  /// estatísticas completas por vídeo dependem delas.
  Future<void> _readVideoInfo(Side side) async {
    final native = _players[side]?.native;
    if (native == null) return;
    final watchedPath = _state[side]!.path;
    String? firstWord(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final word = trimmed.split(RegExp(r'\s+')).first;
      const bogus = {'property', 'unavailable', 'error', 'unknown', 'no'};
      return bogus.contains(word.toLowerCase()) ? null : word;
    }

    for (var attempt = 0; attempt < 60; attempt++) {
      final state = _state[side]!;
      if (!state.loaded || state.path != watchedPath) return;
      try {
        final w = int.tryParse((await native.getProperty('video-params/w')).trim());
        final h = int.tryParse((await native.getProperty('video-params/h')).trim());
        final size = (w != null && h != null && w > 0 && h > 0) ? '${w}x$h' : null;
        // Resolução de exibição (após aspect/rotação). `dwidth`/`dheight` são
        // os aliases OSD; em fallback lê `video-params/dw`/`dh`. Só fica
        // disponível um pouco depois da resolução nativa.
        var dw = int.tryParse((await native.getProperty('dwidth')).trim());
        var dh = int.tryParse((await native.getProperty('dheight')).trim());
        if (dw == null || dh == null) {
          dw ??= int.tryParse((await native.getProperty('video-params/dw')).trim());
          dh ??= int.tryParse((await native.getProperty('video-params/dh')).trim());
        }
        final display =
            (dw != null && dh != null && dw > 0 && dh > 0) ? '${dw}x$dh' : null;
        String? videoCodec;
        String? audioCodec;
        if (size != null) {
          videoCodec = firstWord(await native.getProperty('video-codec'));
          audioCodec = firstWord(await native.getProperty('audio-codec'));
        }
        final fileSize = int.tryParse((await native.getProperty('file-size')).trim());
        final drops =
            int.tryParse((await native.getProperty('frame-drop-count')).trim());

        if (size != null) _videoSize[side] = size;
        if (display != null) _displaySize[side] = display;
        if (videoCodec != null) _videoCodec[side] = videoCodec;
        if (audioCodec != null) _audioCodec[side] = audioCodec;
        if (fileSize != null && fileSize > 0) _fileSize[side] = fileSize;
        if (drops != null && drops >= 0) _droppedFrames[side] = drops;
        // Só termina quando a resolução nativa **e** a de exibição estão
        // conhecidas (a de exibição chega mais tarde); após ~1,5 s aceita o
        // que existir para não atrasar as estatísticas.
        if (size != null && display != null) {
          notifyListeners();
          return;
        }
        if (size != null && attempt >= 30) {
          notifyListeners();
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _alignAfterLoad(Side side) async {
    Side? reference;
    for (final other in _sides) {
      if (other != side && _state[other]!.loaded) {
        reference = other;
        break;
      }
    }
    if (reference == null) return;

    final time = _state[reference]!.position;
    if (time > 0) {
      _state[side] = _state[side]!.copyWith(position: time);
      await _seek(side, time, exact: true);
    }
    if (_state[reference]!.duration > 0 && _state[side]!.duration <= 0) {
      _state[side] = _state[side]!.copyWith(duration: _state[reference]!.duration);
    }
    if (!_state[reference]!.paused) {
      _state[side] = _state[side]!.copyWith(paused: false);
      await _players[side]!.player.play();
    } else {
      _state[side] = _state[side]!.copyWith(paused: true);
    }
    notifyListeners();
  }

  // --- Transporte ----------------------------------------------------------

  Future<void> playPause() async {
    final loaded = loadedSides();
    if (loaded.isEmpty) return;

    if (_jogActive) {
      _holdActive = false;
      await _stopJog();
      return;
    }

    if (isPlaying()) {
      _stepTime = null;
      for (final side in loaded) {
        await _players[side]!.player.pause();
        _state[side] = _state[side]!.copyWith(paused: true);
      }
      notifyListeners();
      return;
    }

    final double time;
    if (isEnded()) {
      time = 0;
    } else {
      time = _projected(authority());
    }
    _stepTime = null;
    for (final side in loaded) {
      _state[side] = _state[side]!.copyWith(position: time, paused: false, ended: false);
      _stampMicros[side] = DateTime.now().microsecondsSinceEpoch;
    }
    await _startTogether(loaded, time);
    // O play foi ativado: o HUD de frame/FFPS some (só volta com as setas).
    _hideFrameHud();
    notifyListeners();
  }

  /// Arranca os lados em conjunto: alinha no mesmo instante (encaixado na
  /// grelha de frames quando os FPS são iguais), espera que os dois tenham o
  /// frame alvo pronto e só então manda tocar — assim nenhum lado "sai na
  /// frente". O ajuste fino fica a cargo do `_syncDrift`.
  Future<void> _startTogether(List<Side> loaded, double time) async {
    for (final side in loaded) {
      _rate[side] = _userRate;
    }
    await Future.wait(
        loaded.map((side) => _players[side]!.player.setRate(_userRate)));
    var target = _alignToFrameGrid(time);
    final duration = _state[authority()]!.duration;
    if (duration > 0 && target > duration - 0.001) target = duration - 0.001;
    await _seekBoth(target, exact: true);
    // Espera que os dois descodifiquem o frame alvo antes de arrancar.
    await _waitUntilBothReady(loaded, target);
    // Dispara os dois `play()` seguidos, sem `await` entre eles.
    final starts = <Future<void>>[];
    for (final side in loaded) {
      starts.add(_players[side]!.player.play());
    }
    await Future.wait(starts);
    final now = DateTime.now().microsecondsSinceEpoch;
    for (final side in loaded) {
      _stampMicros[side] = now;
      _state[side] = _state[side]!.copyWith(position: target);
    }
  }

  /// Pausa os dois lados (usado no início do scrub).
  Future<void> pauseAll() async {
    final loaded = loadedSides();
    if (loaded.isEmpty) return;
    if (_jogActive) {
      _holdActive = false;
      await _stopJog();
      return;
    }
    await Future.wait(loaded.map((side) => _players[side]!.player.pause()));
    _resetRates();
    for (final side in loaded) {
      _state[side] = _state[side]!.copyWith(paused: true);
    }
    notifyListeners();
  }

  Future<void> stop() async {
    final loaded = loadedSides();
    if (loaded.isEmpty) return;
    _stepTime = null;
    // Não chamar `player.stop()`: isso descarrega a media e impede o play
    // seguinte. Faz só pausa + seek ao início, mantendo o ficheiro carregado.
    for (final side in loaded) {
      _state[side] = _state[side]!.copyWith(position: 0, paused: true, ended: false);
      _stampMicros[side] = DateTime.now().microsecondsSinceEpoch;
    }
    await _seekBoth(0, exact: true);
    await Future.wait(loaded.map((side) => _players[side]!.player.pause()));
    _resetRates();
    for (final side in loaded) {
      _state[side] = _state[side]!.copyWith(paused: true);
    }
    notifyListeners();
  }

  /// Procura um instante nos dois lados e **re-alinha** exatamente.
  ///
  /// Se estava a tocar, pausa os dois, faz o seek exato e volta a arrancar os
  /// dois em paralelo — é isto que evita o desfasamento ao clicar na barra ou
  /// ao saltar com Shift/Ctrl. Se estava em pausa, permanece em pausa.
  Future<void> seek(double time, {bool exact = false}) async {
    final loaded = loadedSides();
    if (loaded.isEmpty) return;
    final wasPlaying = isPlaying();
    final target = time < 0 ? 0.0 : time;
    _stepTime = null;
    for (final side in loaded) {
      _state[side] = _state[side]!.copyWith(position: target, ended: false);
      _stampMicros[side] = DateTime.now().microsecondsSinceEpoch;
    }
    if (wasPlaying) {
      await Future.wait(loaded.map((side) => _players[side]!.player.pause()));
      await _startTogether(loaded, target);
      // O play foi ativado: o HUD de frame/FPS some.
      _hideFrameHud();
    } else {
      await _seekBoth(target, exact: true);
      // Espera os frames assentarem (spinner por lado durante o seek em pausa).
      await _waitUntilBothReady(loaded, target);
    }
    for (final side in loaded) {
      _state[side] = _state[side]!.copyWith(paused: !wasPlaying);
      _stampMicros[side] = DateTime.now().microsecondsSinceEpoch;
    }
    notifyListeners();
  }

  Future<void> _seekBoth(double time, {required bool exact}) async {
    await Future.wait(loadedSides().map((side) => _seek(side, time, exact: exact)));
  }

  Future<void> _seek(Side side, double time, {required bool exact}) async {
    final player = _players[side]!.player;
    final clamped = time < 0 ? 0.0 : time;
    try {
      if (exact) {
        final native = _players[side]!.native;
        if (native != null) {
          await native.command(['seek', clamped.toStringAsFixed(4), 'absolute+exact']);
          return;
        }
      }
      await player.seek(Duration(milliseconds: (clamped * 1000).round()));
    } catch (_) {}
  }

  /// Alinha os dois lados no mesmo instante e mantém pausa.
  Future<void> resyncBoth({double? time}) async {
    final loaded = loadedSides();
    if (loaded.isEmpty) return;
    final target = _alignToFrameGrid(
        (time ?? _projected(authority())).clamp(0.0, double.infinity));
    _stepTime = null;
    for (final side in loaded) {
      _state[side] = _state[side]!.copyWith(position: target, ended: false);
      _stampMicros[side] = DateTime.now().microsecondsSinceEpoch;
    }
    await _seekBoth(target, exact: true);
    await _waitUntilBothReady(loaded, target);
    for (final side in loaded) {
      await _players[side]!.player.pause();
      _state[side] = _state[side]!.copyWith(paused: true);
    }
    notifyListeners();
  }

  void setScrubbing(bool active) => _scrubbing = active;
  void setHoldActive(bool active) => _holdActive = active;

  bool get jogActive => _jogActive;

  /// Arranca o jog para a **frente**: os lados tocam à rate que equivale a
  /// `frameStepCount` frames do líder por cada `holdIntervalMs`.
  ///
  /// Retrocesso contínuo via `play-direction=backward` não é fiável neste
  /// libmpv (acaba a reproduzir para a frente) — o hold para trás usa
  /// `frameStep` exact no UI.
  ///
  /// Chamar só depois do delay do hold; o toque inicial continua a ser um
  /// `frameStep` exact. Ao soltar a seta, [endHold] pausa e re-alinha.
  Future<void> startJog({
    required int direction,
    required int holdIntervalMs,
  }) async {
    if (direction < 0) return;
    if (_jogActive || !_holdActive) return;
    final epoch = _jogEpoch;
    const dir = 1;
    // Espera o frame-step inicial assentar (evita play a meio do seek).
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (_stepInFlight && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (!_holdActive || epoch != _jogEpoch) return;
    }
    if (!_holdActive || _jogActive || epoch != _jogEpoch) return;

    final loaded = loadedSides();
    if (loaded.isEmpty) return;

    final intervalMs = holdIntervalMs < 16 ? 16 : holdIntervalMs;
    final unit = _framePeriod(_masterSide()) * _frameStepCount;
    final rate = (unit / (intervalMs / 1000.0)).clamp(0.05, 4.0);

    _jogActive = true;
    _jogRate = rate;
    _jogDirection = dir;
    _stepTime = null;
    _showFrameHud();

    await _setPlayDirection(loaded, 'forward');
    for (final side in loaded) {
      _rate[side] = rate;
    }
    await Future.wait(
        loaded.map((side) => _players[side]!.player.setRate(rate)));
    if (!_holdActive || epoch != _jogEpoch) {
      await _abortJogStart(loaded);
      return;
    }

    final starts = <Future<void>>[];
    for (final side in loaded) {
      starts.add(_players[side]!.player.play());
    }
    await Future.wait(starts);
    if (!_holdActive || epoch != _jogEpoch) {
      await _abortJogStart(loaded);
      return;
    }

    final now = DateTime.now().microsecondsSinceEpoch;
    for (final side in loaded) {
      _stampMicros[side] = now;
      _state[side] = _state[side]!.copyWith(paused: false, ended: false);
    }
    notifyListeners();
  }

  Future<void> _setPlayDirection(List<Side> loaded, String direction) async {
    await Future.wait(loaded.map((side) async {
      final native = _players[side]?.native;
      if (native == null) return;
      try {
        await native.setProperty('play-direction', direction);
      } catch (_) {}
    }));
  }

  /// Termina o hold: se estava em jog, pausa e faz um único resync exact.
  Future<void> endHold() async {
    _holdActive = false;
    _jogEpoch++;
    if (_jogActive) {
      await _stopJog();
    }
  }

  /// Cancela um jog que ainda estava a arrancar (seta solta a meio).
  Future<void> _abortJogStart(List<Side> loaded) async {
    // [endHold]/[_stopJog] já tomou conta.
    if (!_jogActive) return;
    _jogActive = false;
    _jogDirection = 1;
    await Future.wait(loaded.map((side) => _players[side]!.player.pause()));
    await _setPlayDirection(loaded, 'forward');
    _resetRates();
    for (final side in loaded) {
      _state[side] = _state[side]!.copyWith(paused: true);
    }
    notifyListeners();
  }

  Future<void> _stopJog() async {
    if (!_jogActive && !isPlaying()) {
      _jogActive = false;
      _jogDirection = 1;
      _resetRates();
      return;
    }
    _jogActive = false;
    final loaded = loadedSides();
    if (loaded.isEmpty) {
      _jogDirection = 1;
      _resetRates();
      return;
    }

    await Future.wait(loaded.map((side) => _players[side]!.player.pause()));
    await _setPlayDirection(loaded, 'forward');
    _jogDirection = 1;
    _resetRates();

    final target = _alignToFrameGrid(
        _projected(authority()).clamp(0.0, double.infinity));
    _stepTime = target;
    for (final side in loaded) {
      _state[side] =
          _state[side]!.copyWith(position: target, paused: true, ended: false);
      _stampMicros[side] = DateTime.now().microsecondsSinceEpoch;
    }
    await _seekBoth(target, exact: true);
    await _waitUntilBothReady(loaded, target);
    for (final side in loaded) {
      _state[side] = _state[side]!.copyWith(paused: true);
    }
    _showFrameHud();
    notifyListeners();
  }

  /// Avança/recua **exatamente `frameStepCount` frames** do lado com maior FPS
  /// e alinha o outro no mesmo instante. Não usa o `frame-step` do mpv (cujo
  /// `time-pos` pode chegar atrasado e repetir o mesmo frame): mantém um cursor
  /// exato (`_stepTime`) e soma `count/fps` do líder a cada passo, o que é
  /// determinístico.
  ///
  /// O lado com menos FPS pode repetir o mesmo frame em passos consecutivos —
  /// isso é o esperado, porque o que manda é o tempo do vídeo.
  Future<void> frameStep(int direction) async {
    final loaded = loadedSides();
    if (loaded.isEmpty) return;
    if (_jogActive) return;
    // Serialize os passos: com a espera de sincronização, um passo pode demorar
    // mais que o intervalo do hold — o tick seguinte é então descartado em vez
    // de sobrepor seeks concorrentes.
    if (_stepInFlight) return;
    _stepInFlight = true;
    try {
      await _frameStepLocked(direction, loaded);
    } finally {
      _stepInFlight = false;
    }
  }

  bool _stepInFlight = false;

  Future<void> _frameStepLocked(int direction, List<Side> loaded) async {
    if (isPlaying()) {
      for (final side in loaded) {
        await _players[side]!.player.pause();
        _state[side] = _state[side]!.copyWith(paused: true);
      }
    }

    final leader = _masterSide();
    final unit = _framePeriod(leader) * _frameStepCount;
    final duration = _state[authority()]!.duration;

    var target = (_stepTime ?? _state[leader]!.position) +
        unit * (direction < 0 ? -1 : 1);
    if (target < 0) target = 0;
    if (duration > 0 && target > duration - 0.001) target = duration - 0.001;
    _stepTime = target;

    for (final side in loaded) {
      _state[side] = _state[side]!.copyWith(position: target, ended: false);
      _stampMicros[side] = DateTime.now().microsecondsSinceEpoch;
    }
    await _seekBoth(target, exact: true);
    await Future.wait(loaded.map((side) => _players[side]!.player.pause()));
    // Espera o frame alvo assentar nos dois lados (spinner durante o seek).
    await _waitUntilBothReady(loaded, target);
    for (final side in loaded) {
      _state[side] = _state[side]!.copyWith(paused: true);
    }
    _showFrameHud();
    notifyListeners();
  }

  /// Salta `seconds` (positivo = frente) a partir da posição atual.
  ///
  /// **Não** altera o estado de reprodução: se estava a tocar continua a tocar,
  /// se estava em pausa continua em pausa (não inicia play).
  Future<void> nudgeBy(double seconds) async {
    final loaded = loadedSides();
    if (loaded.isEmpty) return;
    final target = (_projected(authority()) + seconds).clamp(0.0, double.infinity);
    await seek(target, exact: true);
  }

  // --- Áudio ---------------------------------------------------------------

  /// Volume global (não altera o mute de cada lado).
  Future<void> setVolume(double volume) async {
    _globalVolume = volume.clamp(0.0, 100.0);
    for (final side in loadedSides()) {
      _state[side] = _state[side]!.copyWith(volume: _globalVolume);
      await _players[side]!.player.setVolume(_globalVolume);
    }
    notifyListeners();
  }

  /// Volume global atual (0..100).
  double get globalVolume => _globalVolume;

  /// Mute global atual.
  bool get globalMuted => _globalMuted;

  Future<void> _setMuteProperty(Side side, bool muted) async {
    final native = _players[side]?.native;
    if (native != null) {
      try {
        await native.setProperty('mute', muted ? 'yes' : 'no');
      } catch (_) {}
    }
  }

  /// Mute global: muda a preferência global e re-aplica o estado efetivo a
  /// todos os lados (o mute explícito de um lado sobrevive ao unmute global).
  Future<void> setMuted(bool muted) async {
    _globalMuted = muted;
    _applyAudioPolicy();
  }

  /// Mute/unmute explícito de um lado. Vence a política; perde para o mute
  /// global quando este está ativo (precedência do estado efetivo).
  Future<void> setMutedSide(Side side, bool muted) async {
    final state = _state[side]!;
    if (!state.loaded) return;
    _sideMute[side] = muted;
    final target = _effectiveMuted(side);
    if (state.muted != target) {
      await _muteSideDirect(side, target);
    } else {
      notifyListeners();
    }
  }

  Future<void> toggleMuteSide(Side side) async {
    final state = _state[side]!;
    if (!state.loaded) return;
    await setMutedSide(side, !state.muted);
  }

  Future<void> toggleMute() async {
    if (loadedSides().isEmpty) return;
    await setMuted(!_globalMuted);
  }

  /// Estado efetivo de mute de um lado. Precedência: mute explícito do lado >
  /// mute global > unmute explícito do lado > política (dono do áudio).
  bool _effectiveMuted(Side side) {
    if (_sideMute[side] == true) return true;
    if (_globalMuted) return true;
    if (_sideMute[side] == false) return false;
    final owner = _audioOwner;
    if (owner == null || side == owner) return false;
    // Política: os restantes lados com áudio ficam mutados.
    return _state[side]!.hasAudio;
  }

  /// Política de áudio: um único dono (o primeiro lado com áudio). Recalcula
  /// sempre (sem early-return): a mudança de `hasAudio` sem mudança de dono
  /// também tem de re-aplicar o estado. Desmutes manuais nunca são revertidos
  /// — são resolvidos pela precedência em `_effectiveMuted`.
  void _applyAudioPolicy() {
    final withAudio = loadedSides()
        .where((side) => _state[side]!.hasAudio)
        .toList(growable: false);
    if (withAudio.isEmpty) {
      _audioOwner = null;
    } else {
      var owner = _audioOwner;
      if (owner == null || !withAudio.contains(owner)) {
        owner = withAudio.first;
      }
      _audioOwner = owner;
    }

    var mutedAny = false;
    final mutedByPolicy = <Side>[];
    var applied = false;
    for (final side in loadedSides()) {
      final target = _effectiveMuted(side);
      if (_state[side]!.muted == target) continue;
      applied = true;
      // Só conta como "dual-audio" o que a política (não os comandos do
      // utilizador) acabou de mutar, com 2+ lados com áudio.
      if (target &&
          _sideMute[side] == null &&
          !_globalMuted &&
          withAudio.length >= 2) {
        mutedAny = true;
        mutedByPolicy.add(side);
      }
      unawaited(_muteSideDirect(side, target));
    }
    if (!applied) return;
    if (mutedAny) _showDualAudioToast(mutedByPolicy);
  }

  Future<void> _muteSideDirect(Side side, bool muted) async {
    final state = _state[side];
    if (state == null || !state.loaded) return;
    _state[side] = state.copyWith(muted: muted);
    await _setMuteProperty(side, muted);
    notifyListeners();
  }

  void _showDualAudioToast(Iterable<Side> sides) {
    dualAudioToastSides = sides.toSet();
    notifyListeners();
    _dualAudioTimer?.cancel();
    _dualAudioTimer = Timer(const Duration(seconds: 3), () {
      if (dualAudioToastSides.isEmpty) return;
      dualAudioToastSides = <Side>{};
      notifyListeners();
    });
  }

  // --- Opções de vídeo -----------------------------------------------------

  /// Rotação atual do vídeo no próprio eixo (graus: 0/90/180/270).
  int videoRotation(Side side) => _videoRotation[side] ?? 0;

  /// Troca só o conteúdo em reprodução entre dois quadros. Orientação e mute
  /// seguem o vídeo (botões do quadro destino); a letra/geometria ficam.
  Future<void> swapVideos(Side a, Side b) async {
    if (a == b) return;
    final active = Side.forViewCount(_viewCount);
    if (!active.contains(a) || !active.contains(b)) return;
    _swapSideContent(a, b);
    await _rebindFrameOutput(a);
    await _rebindFrameOutput(b);
    _applyAudioPolicy();
    notifyListeners();
  }

  /// Avança cada vídeo para o quadro seguinte (A←B←C←D←A). Quadros fixos;
  /// só o conteúdo em reprodução muda — o mesmo modelo do drag & drop.
  Future<void> rotateVideoPositions() async {
    final sides = Side.forViewCount(_viewCount);
    if (sides.length < 2) return;
    // sides[0] recebe o que estava em sides[1], …, sides[n-1] recebe sides[0].
    for (var i = 0; i < sides.length - 1; i++) {
      _swapSideContent(sides[i], sides[i + 1]);
    }
    for (final side in sides) {
      await _rebindFrameOutput(side);
    }
    _applyAudioPolicy();
    notifyListeners();
  }

  /// Reaplica volume do quadro e mute do conteúdo ao player que agora lá está.
  Future<void> _rebindFrameOutput(Side side) async {
    final state = _state[side];
    final player = _players[side]?.player;
    if (state == null || player == null) return;
    try {
      await player.setVolume(state.volume);
    } catch (_) {}
    await _setMuteProperty(side, state.muted);
  }

  /// Troca o estado de reprodução entre dois lados. Orientação e mute seguem
  /// o vídeo (e os botões do quadro destino); volume do painel fica no quadro.
  void _swapSideContent(Side a, Side b) {
    void swapMap<T>(Map<Side, T> map) {
      final tmp = map[a] as T;
      map[a] = map[b] as T;
      map[b] = tmp;
    }

    final volA = _state[a]!.volume;
    final volB = _state[b]!.volume;
    final sideMuteA = _sideMute[a];
    final sideMuteB = _sideMute[b];
    final hadMuteA = _sideMute.containsKey(a);
    final hadMuteB = _sideMute.containsKey(b);

    swapMap(_players);
    swapMap(_state);
    swapMap(_fps);
    swapMap(_bufferSeconds);
    swapMap(_bufferBytes);
    swapMap(_videoSize);
    swapMap(_videoCodec);
    swapMap(_audioCodec);
    swapMap(_displaySize);
    swapMap(_fileSize);
    swapMap(_droppedFrames);
    swapMap(_videoRotation);
    swapMap(_rate);
    swapMap(_stampMicros);

    // Preferência explícita de mute segue o vídeo (botões acompanham).
    if (hadMuteB) {
      _sideMute[a] = sideMuteB!;
    } else {
      _sideMute.remove(a);
    }
    if (hadMuteA) {
      _sideMute[b] = sideMuteA!;
    } else {
      _sideMute.remove(b);
    }

    // Volume do painel permanece no quadro.
    _state[a] = _state[a]!.copyWith(volume: volA);
    _state[b] = _state[b]!.copyWith(volume: volB);

    final syncA = _syncingSides.contains(a);
    final syncB = _syncingSides.contains(b);
    if (syncA != syncB) {
      if (syncA) {
        _syncingSides.remove(a);
        _syncingSides.add(b);
      } else {
        _syncingSides.remove(b);
        _syncingSides.add(a);
      }
    }

    // Dono do áudio segue o conteúdo (se o dono era A e A↔B, passa a B).
    if (_audioOwner == a) {
      _audioOwner = b;
    } else if (_audioOwner == b) {
      _audioOwner = a;
    }
  }

  /// Gira o vídeo do lado +90º no próprio eixo (sentido dos relógios).
  Future<void> rotateVideo(Side side) async {
    if (!_state[side]!.loaded) return;
    _videoRotation[side] = (videoRotation(side) + 90) % 360;
    await _applyVideoRotation(side);
  }

  /// Gira todos os vídeos carregados +90º no próprio eixo.
  Future<void> rotateAllVideos() async {
    for (final side in loadedSides()) {
      _videoRotation[side] = (videoRotation(side) + 90) % 360;
      await _applyVideoRotation(side);
    }
  }

  Future<void> _applyVideoRotation(Side side) async {
    final native = _players[side]?.native;
    if (native == null) return;
    try {
      await native.setProperty('video-rotate', '${videoRotation(side)}');
    } catch (_) {}
    notifyListeners();
  }

  /// Aplica as opções do mpv e mantém o número de vídeos da view em
  /// sincronia (pausa lados ocultos e re-alinha os visíveis).
  Future<void> applyVideoOptions(AppSettings settings) async {
    final count = clampViewCount(settings.viewCount);
    if (count != _viewCount) {
      _viewCount = count;
      unawaited(_onViewCountChanged());
    }

    final hwdec = switch (settings.hardwareDecode) {
      HardwareDecode.off => 'no',
      // Windows/media_kit: `direct` (zero-copy) não é suportado; usa copy-back.
      HardwareDecode.compat || HardwareDecode.direct => 'auto-copy',
    };
    final options = <String, String>{
      'scale': settings.scaler.name,
      'framedrop': settings.framedrop ? 'vo' : 'no',
      'interpolation': settings.interpolation ? 'yes' : 'no',
      'video-sync': settings.videoSync.mpvValue,
      'hwdec': hwdec,
      'demuxer-max-bytes': settings.bufferProfile.mpvMaxBytes,
    };
    for (final side in _sides) {
      final native = _players[side]?.native;
      if (native == null) continue;
      for (final entry in options.entries) {
        try {
          await native.setProperty(entry.key, entry.value);
        } catch (_) {}
      }
    }

    _frameStepCount = clampFrameStep(settings.frameStepCount);

    final rate = clampPlaybackRate(settings.playbackRate);
    if ((rate - _userRate).abs() > 0.0005) {
      _userRate = rate;
      for (final side in _sides) {
        _rate[side] = rate;
        final player = _players[side]?.player;
        if (player != null && _state[side]!.loaded) {
          unawaited(player.setRate(rate));
        }
      }
    } else {
      _userRate = rate;
    }
  }

  /// Ao mudar o número de vídeos: põe em pausa os lados que saíram da view e
  /// re-alinha os que entraram (mantendo o estado de reprodução).
  Future<void> _onViewCountChanged() async {
    final active = activeSides();
    for (final side in _sides) {
      if (_state[side]!.loaded && !active.contains(side)) {
        await _players[side]?.player.pause();
        _state[side] = _state[side]!.copyWith(paused: true);
      }
    }
    final activeLoaded = active
        .where((side) => _state[side]!.loaded)
        .toList(growable: false);
    if (activeLoaded.length >= 2 && !_scrubbing) {
      // `seek` preserva o estado (tocar continua a tocar) e re-alinha todos
      // os lados ativos no mesmo instante.
      await seek(_projected(authority()), exact: true);
    }
    notifyListeners();
  }

  // --- Buffer --------------------------------------------------------------

  /// Poll do `demuxer-cache-duration`, bytes em cache e `frame-drop-count`
  /// por lado (500 ms) — alimenta o indicador de buffer e as estatísticas.
  /// Notifica só quando os valores mudam.
  void _pollBuffers() {
    for (final side in _sides) {
      unawaited(_pollBufferFor(side));
    }
  }

  Future<void> _pollBufferFor(Side side) async {
    final state = _state[side]!;
    final native = _players[side]?.native;
    if (!state.loaded || native == null) {
      var cleared = false;
      if (_bufferSeconds[side] != -1) {
        _bufferSeconds[side] = -1;
        cleared = true;
      }
      if (_bufferBytes[side] != null) {
        _bufferBytes[side] = null;
        cleared = true;
      }
      if (cleared) notifyListeners();
      return;
    }
    try {
      final raw = await native.getProperty('demuxer-cache-duration');
      final value = double.tryParse(raw.trim());
      final next = (value != null && value.isFinite && value >= 0) ? value : -1.0;
      final prev = _bufferSeconds[side]!;
      var changed = false;
      if (prev.toStringAsFixed(1) != next.toStringAsFixed(1)) {
        _bufferSeconds[side] = next;
        changed = true;
      }

      // Bytes à frente no demuxer (`fw-bytes`). Sem estimativa por bitrate
      // (inflava acima do tamanho do ficheiro). Se a property falhar, usa
      // proporção ficheiro×duração, sempre limitada a `file-size`.
      final nextBytes = await _readCacheBytes(native, side, next);
      if (_bufferBytes[side] != nextBytes) {
        _bufferBytes[side] = nextBytes;
        changed = true;
      }

      final drops =
          int.tryParse((await native.getProperty('frame-drop-count')).trim());
      if (drops != null && drops >= 0 && _droppedFrames[side] != drops) {
        _droppedFrames[side] = drops;
        changed = true;
      }
      if (changed) notifyListeners();
    } catch (_) {}
  }

  /// Bytes de buffer em memória para estatísticas (`null` se indisponível).
  ///
  /// Usa `fw-bytes` (pacotes à frente da posição actual). `total-bytes` é
  /// evitado: inclui gamas seekable e overhead e pode ultrapassar o tamanho
  /// do ficheiro. Em fallback, estima `fileSize × buffer/duration`, sempre
  /// limitado ao tamanho do ficheiro.
  Future<int?> _readCacheBytes(
    NativePlayer native,
    Side side,
    double bufferSeconds,
  ) async {
    int? raw = _parseByteCount(
      await native.getProperty('demuxer-cache-state/fw-bytes'),
    );

    if (raw == null) {
      try {
        final blob = (await native.getProperty('demuxer-cache-state')).trim();
        if (blob.isNotEmpty) {
          final match = RegExp(
            r'fw-bytes\s*[:=]\s*"?(\d+)"?',
            caseSensitive: false,
          ).firstMatch(blob);
          if (match != null) {
            raw = int.tryParse(match.group(1)!);
          }
        }
      } catch (_) {}
    }

    if (raw == null && bufferSeconds >= 0) {
      raw = _estimateCacheBytesFromFile(side, bufferSeconds);
    }

    return _clampCacheBytesToFile(side, raw);
  }

  /// Proporção do ficheiro correspondente aos segundos em cache (≤ file size).
  int? _estimateCacheBytesFromFile(Side side, double bufferSeconds) {
    final fileSize = _fileSize[side];
    final duration = _state[side]!.duration;
    if (fileSize == null || fileSize <= 0 || duration <= 0) return null;
    final cappedSeconds = bufferSeconds > duration ? duration : bufferSeconds;
    if (cappedSeconds < 0) return null;
    return (fileSize / duration * cappedSeconds).round().clamp(0, fileSize);
  }

  /// Garante que o valor mostrado nunca excede o tamanho do ficheiro em disco
  /// (comparável com a linha de estatísticas que já mostra esse tamanho).
  int? _clampCacheBytesToFile(Side side, int? bytes) {
    if (bytes == null || bytes < 0) return null;
    final fileSize = _fileSize[side];
    if (fileSize != null && fileSize > 0 && bytes > fileSize) return fileSize;
    return bytes;
  }

  int? _parseByteCount(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final asInt = int.tryParse(trimmed);
    if (asInt != null && asInt >= 0) return asInt;
    final asDouble = double.tryParse(trimmed);
    if (asDouble != null && asDouble.isFinite && asDouble >= 0) {
      return asDouble.round();
    }
    return null;
  }

  // --- Drift ---------------------------------------------------------------

  /// Aplica a velocidade a um lado (só se mudou).
  void _applyRate(Side side, double rate) {
    if ((_rate[side]! - rate).abs() < 0.0005) return;
    _rate[side] = rate;
    final player = _players[side]?.player;
    if (player != null) unawaited(player.setRate(rate));
  }

  void _resetRates() {
    for (final side in _sides) {
      _applyRate(side, _userRate);
    }
  }

  void _syncDrift() {
    if (_scrubbing) return;
    // Hold em passos (sem jog): não mexer na rate. Jog activo: drift sobre
    // `_jogRate` (com sinal invertido se for para trás).
    if (_holdActive && !_jogActive) return;
    final loaded = loadedSides();
    final baseRate = _jogActive ? _jogRate : _userRate;
    if (loaded.length < 2) {
      if (_jogActive) {
        for (final side in loaded) {
          _applyRate(side, baseRate);
        }
      } else {
        _resetRates();
      }
      return;
    }
    if (loaded.any((side) => _state[side]!.paused)) {
      if (!_jogActive) _resetRates();
      return;
    }
    if (loaded.any((side) => _state[side]!.duration <= 0)) return;

    final master = _masterSide();
    final masterProj = _projected(master);
    final tolerance = _driftTolerance;
    // Em reverse, progresso = tempo a descer: inverte o sinal do drift.
    final dirSign = _jogActive && _jogDirection < 0 ? -1.0 : 1.0;
    for (final side in loaded) {
      if (side == master) {
        _applyRate(master, baseRate);
        continue;
      }
      final drift = (masterProj - _projected(side)) * dirSign;
      final excess = drift.abs() - tolerance;
      if (excess <= 0) {
        _applyRate(side, baseRate);
        continue;
      }
      // Ajuste proporcional: quanto maior o desvio, mais rápido o lado
      // atrasado (ou mais lento o adiantado) até voltar a alinhar. O delta
      // incide sobre a velocidade base (utilizador ou jog).
      final delta = (excess * _driftGain).clamp(0.0, _driftMaxRateDelta);
      final adjusted =
          (drift > 0 ? baseRate + delta : baseRate - delta).clamp(0.05, 4.0);
      _applyRate(side, adjusted);
    }
  }

  // --- Motor ---------------------------------------------------------------

  Future<EngineInfo> engineInfo() async {
    final native = _players[Side.a]?.native;
    if (native == null) {
      return const EngineInfo(
        found: false,
        ok: false,
        bundled: false,
        message: 'O motor ainda não está inicializado.',
      );
    }
    try {
      final version = (await native.getProperty('mpv-version')).trim();
      return EngineInfo(
        found: true,
        ok: version.isNotEmpty,
        bundled: true,
        path: null,
        version: version.isEmpty ? null : version,
        message: version.isEmpty
            ? 'libmpv respondeu sem versão.'
            : 'libmpv empacotado (media_kit) a responder.',
      );
    } catch (error) {
      return EngineInfo(
        found: false,
        ok: false,
        bundled: true,
        message: 'Falha ao consultar o libmpv: $error',
      );
    }
  }

  static String _fileName(String path) {
    final parts = path.split(RegExp(r'[\\/]'));
    return parts.isNotEmpty && parts.last.isNotEmpty ? parts.last : path;
  }

  @override
  void dispose() {
    _driftTimer?.cancel();
    _bufferTimer?.cancel();
    _dualAudioTimer?.cancel();
    for (final sub in _subs.values) {
      sub.cancel();
    }
    for (final mpv in _players.values) {
      unawaited(mpv.dispose());
    }
    super.dispose();
  }
}
