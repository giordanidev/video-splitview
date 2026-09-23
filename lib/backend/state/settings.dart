/// Definições persistentes + store (JSON portátil) + providers Riverpod.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/strings.dart';
import '../models/models.dart';
import 'portable_store.dart';

/// Limites da janela guardados em `settings.json` → `window`.
class SavedWindowBounds {
  const SavedWindowBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}

/// Intervalo de alternância do modo Blink (ms).
const int blinkMinMs = 100;
const int blinkMaxMs = 1000;
const int blinkDefaultMs = 1000;

/// Ritmo base de repetição do frame-step ao segurar as setas (ms).
const int _frameBaseMs = 33;
const int _minPercent = 10;
const int _maxPercent = 100;

int clampPercent(num value) {
  if (!value.isFinite) return 50;
  return value.round().clamp(_minPercent, _maxPercent);
}

int clampBlink(num value) {
  if (!value.isFinite) return blinkDefaultMs;
  return value.round().clamp(blinkMinMs, blinkMaxMs);
}

/// Intervalo entre frame-steps ao segurar a seta, derivado da velocidade.
int holdIntervalMs(AppSettings settings) {
  final percent = clampPercent(settings.holdSpeedPercent);
  return (() {
    final value = ((_frameBaseMs * 100) / percent).round();
    return value < 16 ? 16 : value;
  })();
}

/// Limites da velocidade de reprodução.
const double playbackRateMin = 0.25;
const double playbackRateMax = 2.0;

double clampPlaybackRate(num value) {
  if (!value.isFinite) return 1.0;
  return value.clamp(playbackRateMin, playbackRateMax).toDouble();
}

/// Tamanhos de passo válidos para as setas (frames por toque).
const List<int> frameStepChoices = [1, 2, 5];

int clampFrameStep(num value) {
  final rounded = value.isFinite ? value.round() : 1;
  return frameStepChoices.contains(rounded) ? rounded : 1;
}

/// Estado de definições, imutável.
class AppSettings {
  const AppSettings({
    this.holdSpeedPercent = 50,
    this.splitMode = SplitMode.wipe,
    this.blinkEnabled = false,
    this.viewCount = 2,
    this.layout = SplitLayout.sideBySide,
    this.viewRotation = 0,
    this.frameOrder = const [],
    this.blinkIntervalMs = blinkDefaultMs,
    this.blinkLetterPosition = BlinkLetterPosition.center,
    this.scaler = Scaler.bicubic,
    this.framedrop = false,
    this.interpolation = false,
    this.videoSync = VideoSyncMode.audio,
    this.hardwareDecode = HardwareDecode.compat,
    this.language = AppLanguage.enUs,
    this.playbackRate = 1.0,
    this.frameStepCount = 1,
    this.bufferProfile = BufferProfile.normal,
    this.bufferIndicator = false,
    this.driftMeter = true,
    this.hudVertical = HudVPos.corner,
    this.hudHorizontal = HudHPos.corner,
    this.fpsAlways = false,
    this.statsOverlay = true,
    this.rememberWindowState = true,
  });

  final int holdSpeedPercent;
  final SplitMode splitMode;
  final bool blinkEnabled;

  /// Número de vídeos visíveis na view (1..4).
  final int viewCount;

  /// Layout de divisão da view (válido para `viewCount` — ver `SplitLayout`).
  final SplitLayout layout;

  /// Rotação dos vídeos entre os quadros (0..n-1; não normalizada aqui).
  final int viewRotation;

  /// Ordem base dos vídeos nos quadros (ids dos lados, por slot). Vazia =
  /// identidade (A,B,C,D). A rotação aplica-se por cima desta ordem.
  final List<String> frameOrder;

  final int blinkIntervalMs;
  final BlinkLetterPosition blinkLetterPosition;
  final Scaler scaler;
  final bool framedrop;
  final bool interpolation;
  final VideoSyncMode videoSync;
  final HardwareDecode hardwareDecode;
  final AppLanguage language;
  final double playbackRate;
  final int frameStepCount;
  final BufferProfile bufferProfile;
  final bool bufferIndicator;
  final bool driftMeter;

  /// Eixo vertical da posição das informações sobrepostas (por célula).
  final HudVPos hudVertical;

  /// Eixo horizontal da posição das informações sobrepostas (por célula).
  final HudHPos hudHorizontal;

  /// Mostra o HUD de FPS sempre (não só após as setas).
  final bool fpsAlways;

  /// Estatísticas completas por vídeo (substituem FPS/buffer no view).
  final bool statsOverlay;

  /// Lembrar posição e tamanho da janela entre sessões.
  final bool rememberWindowState;

  /// Número de vídeos ativo, sempre dentro de 1..4.
  int get effectiveViewCount => clampViewCount(viewCount);

  /// Layout efetivo: válido para o número de vídeos ativo (com fallback para
  /// o predefinido quando a combinação guardada não existe).
  SplitLayout get effectiveLayout {
    final count = effectiveViewCount;
    if (count <= 1) return SplitLayout.sideBySide;
    return layout.supportsViewCount(count) ? layout : SplitLayout.defaultFor(count);
  }

  /// Rotação efetiva (0..n-1) para o número de vídeos ativo.
  int get effectiveRotation {
    final n = effectiveViewCount;
    if (n <= 1) return 0;
    final r = viewRotation % n;
    return r < 0 ? r + n : r;
  }

  /// Lado que mostra em cada slot (0..n-1), já com a rotação aplicada por
  /// cima da ordem base. É esta ordem que resolve as células/capturas.
  List<Side> get effectiveFrameOrder {
    final active = Side.forViewCount(effectiveViewCount);
    final base = fitFrameOrder(
        [for (final id in frameOrder) Side.fromId(id)], active);
    final count = active.length;
    if (count <= 1) return base;
    final rot = effectiveRotation;
    return [for (var i = 0; i < count; i++) base[(i + rot) % count]];
  }

  /// Modo efetivo enviado à apresentação (Blink tem prioridade; o Wipe existe
  /// para 2+ vídeos — com 1 vídeo a view é sempre a área toda).
  ViewMode get effectiveViewMode {
    if (blinkEnabled) return ViewMode.blink;
    if (effectiveViewCount >= 2 && splitMode == SplitMode.wipe) {
      return ViewMode.wipe;
    }
    return ViewMode.columns;
  }

  /// Nova definição ao mudar o número de vídeos (ajusta o layout se preciso e
  /// repõe a rotação e a ordem dos quadros, que são relativas ao conjunto).
  AppSettings withViewCount(int value) {
    final count = clampViewCount(value);
    final nextLayout = layout.supportsViewCount(count)
        ? layout
        : SplitLayout.defaultFor(count);
    return copyWith(
      viewCount: count,
      layout: nextLayout,
      viewRotation: 0,
      frameOrder: const [],
    );
  }

  /// Avança a rotação em +1. Legado de persistência — a UI usa
  /// `PlaybackBridge.rotateVideoPositions()` (troca o conteúdo nos players,
  /// quadros fixos). Mantido para roundtrip de settings antigos.
  AppSettings withRotatedFrames() =>
      copyWith(viewRotation: viewRotation + 1);

  /// Troca dois lados na ordem base. Legado — a UI usa
  /// `PlaybackBridge.swapVideos()` para trocar só o conteúdo em reprodução.
  AppSettings withSwappedFrames(Side a, Side b) {
    final active = Side.forViewCount(effectiveViewCount);
    if (a == b || !active.contains(a) || !active.contains(b)) return this;
    final base =
        fitFrameOrder([for (final id in frameOrder) Side.fromId(id)], active);
    final ia = base.indexOf(a);
    final ib = base.indexOf(b);
    if (ia < 0 || ib < 0) return this;
    final swapped = [...base];
    swapped[ia] = b;
    swapped[ib] = a;
    return copyWith(frameOrder: [for (final side in swapped) side.id]);
  }

  /// Nova definição ao escolher um layout (ignora layouts de outro contador).
  AppSettings withLayout(SplitLayout value) {
    final count = effectiveViewCount;
    final next = value.supportsViewCount(count)
        ? value
        : SplitLayout.defaultFor(count);
    return copyWith(layout: next);
  }

  AppSettings copyWith({
    int? holdSpeedPercent,
    SplitMode? splitMode,
    bool? blinkEnabled,
    int? viewCount,
    SplitLayout? layout,
    int? viewRotation,
    List<String>? frameOrder,
    int? blinkIntervalMs,
    BlinkLetterPosition? blinkLetterPosition,
    Scaler? scaler,
    bool? framedrop,
    bool? interpolation,
    VideoSyncMode? videoSync,
    HardwareDecode? hardwareDecode,
    AppLanguage? language,
    double? playbackRate,
    int? frameStepCount,
    BufferProfile? bufferProfile,
    bool? bufferIndicator,
    bool? driftMeter,
    HudVPos? hudVertical,
    HudHPos? hudHorizontal,
    bool? fpsAlways,
    bool? statsOverlay,
    bool? rememberWindowState,
  }) {
    return AppSettings(
      holdSpeedPercent: holdSpeedPercent ?? this.holdSpeedPercent,
      splitMode: splitMode ?? this.splitMode,
      blinkEnabled: blinkEnabled ?? this.blinkEnabled,
      viewCount: clampViewCount((viewCount ?? this.viewCount)),
      layout: layout ?? this.layout,
      viewRotation: viewRotation ?? this.viewRotation,
      frameOrder: frameOrder ?? this.frameOrder,
      blinkIntervalMs: blinkIntervalMs ?? this.blinkIntervalMs,
      blinkLetterPosition: blinkLetterPosition ?? this.blinkLetterPosition,
      scaler: scaler ?? this.scaler,
      framedrop: framedrop ?? this.framedrop,
      interpolation: interpolation ?? this.interpolation,
      videoSync: videoSync ?? this.videoSync,
      hardwareDecode: hardwareDecode ?? this.hardwareDecode,
      language: language ?? this.language,
      playbackRate: playbackRate ?? this.playbackRate,
      frameStepCount: frameStepCount ?? this.frameStepCount,
      bufferProfile: bufferProfile ?? this.bufferProfile,
      bufferIndicator: bufferIndicator ?? this.bufferIndicator,
      driftMeter: driftMeter ?? this.driftMeter,
      hudVertical: hudVertical ?? this.hudVertical,
      hudHorizontal: hudHorizontal ?? this.hudHorizontal,
      fpsAlways: fpsAlways ?? this.fpsAlways,
      statsOverlay: statsOverlay ?? this.statsOverlay,
      rememberWindowState: rememberWindowState ?? this.rememberWindowState,
    );
  }

  Map<String, Object?> toMap() => {
        'holdSpeedPercent': holdSpeedPercent,
        'splitMode': splitMode.name,
        'blinkEnabled': blinkEnabled,
        'viewCount': effectiveViewCount,
        'layout': effectiveLayout.name,
        'viewRotation': viewRotation,
        'frameOrder': frameOrder,
        'blinkIntervalMs': blinkIntervalMs,
        'blinkLetterPosition': blinkLetterPosition.name,
        'scaler': scaler.name,
        'framedrop': framedrop,
        'interpolation': interpolation,
        'videoSync': videoSync.name,
        'hardwareDecode': hardwareDecode.name,
        'language': language.id,
        'playbackRate': playbackRate,
        'frameStepCount': frameStepCount,
        'bufferProfile': bufferProfile.name,
        'bufferIndicator': bufferIndicator,
        'driftMeter': driftMeter,
        'hudVertical': hudVertical.name,
        'hudHorizontal': hudHorizontal.name,
        'fpsAlways': fpsAlways,
        'statsOverlay': statsOverlay,
        'rememberWindowState': rememberWindowState,
      };

  factory AppSettings.fromMap(Map<String, Object?> map) {
    // Migração de chaves antigas (ex.: `viewMode`).
    final legacySplit = map['splitMode'] ?? map['viewMode'];
    var splitMode = SplitMode.fromId(legacySplit);
    var blinkEnabled = map['blinkEnabled'] == true;
    if (map['splitMode'] == null && map['viewMode'] == 'blink') {
      blinkEnabled = true;
      splitMode = SplitMode.wipe;
    }
    return AppSettings(
      holdSpeedPercent: clampPercent((map['holdSpeedPercent'] as num?) ?? 50),
      splitMode: splitMode,
      blinkEnabled: blinkEnabled,
      viewCount: clampViewCount((map['viewCount'] as num?) ?? 2),
      // Migração: chaves antigas `orientation` (vertical/horizontal) → layout.
      layout: SplitLayout.fromId(map['layout'] ?? map['orientation']),
      viewRotation: (map['viewRotation'] as num?)?.round() ?? 0,
      frameOrder: [
        for (final id in (map['frameOrder'] as List?) ?? const [])
          if (id is String) id,
      ],
      blinkIntervalMs: clampBlink((map['blinkIntervalMs'] as num?) ?? blinkDefaultMs),
      blinkLetterPosition: BlinkLetterPosition.fromId(map['blinkLetterPosition']),
      scaler: Scaler.fromId(map['scaler']),
      framedrop: map['framedrop'] == true,
      interpolation: map['interpolation'] == true,
      videoSync: VideoSyncMode.fromId(map['videoSync']),
      hardwareDecode: HardwareDecode.fromId(map['hardwareDecode'], legacy: map['hwdec']),
      language: map['language'] != null
          ? AppLanguage.fromId(map['language'])
          : AppLanguage.fromSystem(),
      playbackRate: clampPlaybackRate((map['playbackRate'] as num?) ?? 1.0),
      frameStepCount: clampFrameStep((map['frameStepCount'] as num?) ?? 1),
      bufferProfile: BufferProfile.fromId(map['bufferProfile']),
      bufferIndicator: map['bufferIndicator'] as bool? ?? false,
      driftMeter: map['driftMeter'] as bool? ?? true,
      hudVertical: HudVPos.fromId(
          map['hudVertical'] ?? _legacyHudV(map['hudPosition'])),
      hudHorizontal: HudHPos.fromId(
          map['hudHorizontal'] ?? _legacyHudH(map['hudPosition'])),
      fpsAlways: map['fpsAlways'] as bool? ?? false,
      statsOverlay: map['statsOverlay'] as bool? ?? true,
      rememberWindowState: map['rememberWindowState'] as bool? ?? true,
    );
  }
}

/// Migração do antigo `hudPosition` (5 opções) para o eixo vertical.
String? _legacyHudV(Object? value) => switch (value) {
      'bottom' || 'bottomCorner' => 'bottom',
      'center' => 'center',
      'topCorner' => 'top',
      'top' => 'top',
      _ => null,
    };

/// Migração do antigo `hudPosition` para o eixo horizontal.
String? _legacyHudH(Object? value) => switch (value) {
      'topCorner' || 'bottomCorner' => 'corner',
      'center' => 'center',
      _ => 'center',
    };

/// Persistência das definições (JSON junto ao executável).
///
/// O mesmo `settings.json` guarda também os bounds da janela na chave
/// `window` — um único ficheiro de config.
class SettingsStore {
  SettingsStore(this._file);

  final File _file;

  static const String _windowKey = 'window';
  static const double _minWidth = 960;
  static const double _minHeight = 600;

  /// Ficheiro por omissão: `<pasta-do-exe>/settings.json`.
  /// Migra `window.json` legado para a chave `window` neste ficheiro.
  factory SettingsStore.portable() {
    final store = SettingsStore(portableFile('settings.json'));
    store._migrateLegacyWindowFile();
    return store;
  }

  void _migrateLegacyWindowFile() {
    final legacy = portableFile('window.json');
    if (!legacy.existsSync()) return;
    try {
      if (loadWindowBounds() == null) {
        final window = readJsonMap(legacy);
        if (window != null) {
          final existing = readJsonMap(_file);
          final map = existing != null
              ? Map<String, Object?>.from(existing)
              : Map<String, Object?>.from(
                  AppSettings(language: AppLanguage.fromSystem()).toMap());
          map[_windowKey] = window;
          _file.writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(map),
            flush: true,
          );
        }
      }
      legacy.deleteSync();
    } catch (_) {}
  }

  AppSettings load() {
    final map = readJsonMap(_file);
    if (map == null) {
      return AppSettings(language: AppLanguage.fromSystem());
    }
    try {
      return AppSettings.fromMap(map);
    } catch (_) {
      // Corrompido: volta aos defaults (idioma do sistema).
    }
    return AppSettings(language: AppLanguage.fromSystem());
  }

  Future<void> save(AppSettings settings) async {
    final existing = readJsonMap(_file);
    final map = Map<String, Object?>.from(settings.toMap());
    final window = existing?[_windowKey];
    if (window != null) map[_windowKey] = window;
    await writeJsonMap(_file, map);
  }

  /// Bounds da janela guardados em `settings.json` → `window`.
  SavedWindowBounds? loadWindowBounds() {
    try {
      final decoded = readJsonMap(_file);
      final window = decoded?[_windowKey];
      if (window is! Map) return null;
      final rect = Rect.fromLTWH(
        ((window['x'] as num?) ?? 0).toDouble(),
        ((window['y'] as num?) ?? 0).toDouble(),
        ((window['width'] as num?) ?? 0).toDouble(),
        ((window['height'] as num?) ?? 0).toDouble(),
      );
      if (!_plausibleWindow(rect)) return null;
      return SavedWindowBounds(
        x: rect.left,
        y: rect.top,
        width: rect.width < _minWidth ? _minWidth : rect.width,
        height: rect.height < _minHeight ? _minHeight : rect.height,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveWindowBounds({
    required double x,
    required double y,
    required double width,
    required double height,
  }) async {
    final existing = readJsonMap(_file);
    final map = existing != null
        ? Map<String, Object?>.from(existing)
        : Map<String, Object?>.from(
            AppSettings(language: AppLanguage.fromSystem()).toMap());
    map[_windowKey] = {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    };
    await writeJsonMap(_file, map);
  }

  static bool _plausibleWindow(Rect bounds) =>
      bounds.width.isFinite &&
      bounds.height.isFinite &&
      bounds.width >= 400 &&
      bounds.height >= 300 &&
      bounds.width <= 32768 &&
      bounds.height <= 32768 &&
      bounds.left.abs() <= 16384 &&
      bounds.top.abs() <= 16384;
}

/// Provider do store — substituído em `main.dart` com a instância real.
final settingsStoreProvider = Provider<SettingsStore>((ref) {
  throw UnimplementedError('settingsStoreProvider deve ser substituído em main()');
});

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsStoreProvider).load();

  void update(AppSettings next) {
    state = next;
    ref.read(settingsStoreProvider).save(next);
  }

  void mutate(AppSettings Function(AppSettings current) transform) {
    update(transform(state));
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
