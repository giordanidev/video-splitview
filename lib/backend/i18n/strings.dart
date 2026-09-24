/// i18n simples e reativo: catálogo de strings por idioma + enum de idioma.
///
/// Usado via `ref.watch(stringsProvider)`; trocar a definição `language` faz o
/// app inteiro atualizar de imediato.
library;

import 'package:flutter/widgets.dart';

import '../models/models.dart';

enum AppLanguage {
  ptBr('pt-BR', 'Português', '🇧🇷'),
  enUs('en-US', 'English', '🇺🇸'),
  esEs('es-ES', 'Español', '🇪🇸');

  const AppLanguage(this.code, this.label, this.flag);

  final String code;
  final String label;
  final String flag;

  Locale get locale => switch (this) {
        AppLanguage.ptBr => const Locale('pt', 'BR'),
        AppLanguage.enUs => const Locale('en', 'US'),
        AppLanguage.esEs => const Locale('es', 'ES'),
      };

  String get id => code;

  /// Idioma a partir do código guardado. Desconhecido → en-US.
  static AppLanguage fromId(Object? value) => switch (value) {
        'pt-BR' || 'ptBr' || 'pt' => AppLanguage.ptBr,
        'es-ES' || 'esEs' || 'es' => AppLanguage.esEs,
        'en-US' || 'enUs' || 'en' => AppLanguage.enUs,
        _ => AppLanguage.enUs,
      };

  /// Detecta o idioma do sistema (lista de locales do Flutter).
  /// Sem correspondência → [AppLanguage.enUs].
  static AppLanguage fromSystem() {
    try {
      final locales = WidgetsBinding.instance.platformDispatcher.locales;
      for (final locale in locales) {
        switch (locale.languageCode.toLowerCase()) {
          case 'pt':
            return AppLanguage.ptBr;
          case 'es':
            return AppLanguage.esEs;
          case 'en':
            return AppLanguage.enUs;
        }
      }
    } catch (_) {}
    return AppLanguage.enUs;
  }
}

class Strings {
  const Strings({
    required this.language,
    required this.noVideo,
    required this.open,
    required this.change,
    required this.remove,
    required this.removeVideo,
    required this.muteSide,
    required this.unmuteSide,
    required this.brandName,
    required this.slogan,
    required this.dropTitle,
    required this.dropHint,
    required this.repeat,
    required this.pause,
    required this.play,
    required this.stop,
    required this.unmute,
    required this.mute,
    required this.splitWipe,
    required this.splitColumns,
    required this.toggleOrientation,
    required this.sectionViews,
    required this.viewCountTooltip,
    required this.videoCount1,
    required this.videoCount2,
    required this.videoCount3,
    required this.videoCount4,
    required this.layoutColumns3,
    required this.layoutRows3,
    required this.layoutTopPair,
    required this.layoutBottomPair,
    required this.layoutLeftSingle,
    required this.layoutLeftPair,
    required this.layoutColumns4,
    required this.layoutRows4,
    required this.layoutGrid2x2,
    required this.layoutTopTriple,
    required this.layoutBottomTriple,
    required this.layoutLeftTriple,
    required this.layoutRightTriple,
    required this.blink,
    required this.fullscreen,
    required this.copyImage,
    required this.saveImage,
    required this.settings,
    required this.copiedImage,
    required this.copyImageFailed,
    required this.savedImage,
    required this.saveImageFailed,
    required this.dualAudio,
    required this.blinkTitle,
    required this.letterPosition,
    required this.posTop,
    required this.posCenter,
    required this.posBottom,
    required this.posLeft,
    required this.posRight,
    required this.posCorner,
    required this.close,
    required this.sectionView,
    required this.wipe,
    required this.wipeHint,
    required this.columns,
    required this.columnsHint,
    required this.rotateFrames,
    required this.rotateVideo,
    required this.rotateVideos,
    required this.sectionOrientation,
    required this.vertical,
    required this.verticalHint,
    required this.horizontal,
    required this.horizontalHint,
    required this.blinkToggle,
    required this.blinkInterval,
    required this.holdSpeed,
    required this.sectionPerf,
    required this.scaler,
    required this.scalerBilinear,
    required this.scalerBicubic,
    required this.scalerLanczos,
    required this.videoSync,
    required this.syncAudio,
    required this.syncResample,
    required this.syncDesync,
    required this.hwdec,
    required this.hwdecOff,
    required this.hwdecCompat,
    required this.hwdecDirect,
    required this.framedrop,
    required this.interpolation,
    required this.playbackRate,
    required this.sectionPlayback,
    required this.frameStepCount,
    required this.stepFrames1,
    required this.stepFrames2,
    required this.stepFrames5,
    required this.driftMeter,
    required this.bufferProfile,
    required this.bufferSmall,
    required this.bufferNormal,
    required this.bufferLarge,
    required this.bufferIndicator,
    required this.sectionHud,
    required this.hudPosition,
    required this.hudVerticalLabel,
    required this.hudHorizontalLabel,
    required this.hudPosTop,
    required this.hudPosBottom,
    required this.hudPosCenter,
    required this.hudPosCornerTop,
    required this.hudPosCornerBottom,
    required this.syncing,
    required this.fpsAlways,
    required this.statsOverlay,
    required this.audioOn,
    required this.audioNo,
    required this.mutedLabel,
    required this.rememberWindowState,
    required this.sectionWindow,
    required this.settingsNote,
    required this.languageLabel,
    required this.assistTitle,
    required this.assistFallback,
    required this.assistNote,
    required this.verifyEngine,
    required this.verifying,
    required this.copyDiagnostic,
    required this.chooseAnother,
    required this.engineLabel,
    required this.engineOk,
    required this.engineProblem,
    required this.engineBundled,
    required this.runtimeAlert,
    required this.frame,
    required this.dialogTitle,
    required this.filterVideo,
    required this.filterAll,
    required this.sideA,
    required this.sideB,
    required this.sideC,
    required this.sideD,
    required this.diagTitle,
    required this.diagDate,
    required this.diagSide,
    required this.diagFile,
    required this.diagPath,
    required this.diagCode,
    required this.diagEngineMessage,
    required this.diagEngineFound,
    required this.diagEngineBundled,
    required this.diagEnginePath,
    required this.diagEngineVersion,
    required this.diagEngineState,
    required this.diagUnknown,
    required this.diagNotAvailable,
    required this.diagYes,
    required this.diagNo,
    required this.diagOk,
    required this.diagUnavailable,
    required this.sectionUpdates,
    required this.updateCurrent,
    required this.updateCheckNow,
    required this.updateChecking,
    required this.updateUpToDate,
    required this.updateAvailable,
    required this.updateFailed,
    required this.updateDownload,
    required this.updateOpenReleases,
    required this.updateInstall,
    required this.updateDownloading,
    required this.updateInstalling,
    required this.updateInstallFailed,
  });

  final AppLanguage language;

  final String noVideo;
  final String open;
  final String change;
  final String remove;
  final String removeVideo;
  final String muteSide;
  final String unmuteSide;
  final String brandName;
  final String slogan;
  final String dropTitle;
  final String dropHint;
  final String repeat;
  final String pause;
  final String play;
  final String stop;
  final String unmute;
  final String mute;
  final String splitWipe;
  final String splitColumns;
  final String toggleOrientation;
  final String sectionViews;
  final String viewCountTooltip;
  final String videoCount1;
  final String videoCount2;
  final String videoCount3;
  final String videoCount4;
  final String layoutColumns3;
  final String layoutRows3;
  final String layoutTopPair;
  final String layoutBottomPair;
  final String layoutLeftSingle;
  final String layoutLeftPair;
  final String layoutColumns4;
  final String layoutRows4;
  final String layoutGrid2x2;
  final String layoutTopTriple;
  final String layoutBottomTriple;
  final String layoutLeftTriple;
  final String layoutRightTriple;
  final String blink;
  final String fullscreen;
  final String copyImage;
  final String saveImage;
  final String settings;
  final String copiedImage;
  final String copyImageFailed;
  final String savedImage;
  final String saveImageFailed;
  final String dualAudio;
  final String blinkTitle;
  final String letterPosition;
  final String posTop;
  final String posCenter;
  final String posBottom;
  final String posLeft;
  final String posRight;
  final String posCorner;
  final String close;
  final String sectionView;
  final String wipe;
  final String wipeHint;
  final String columns;
  final String columnsHint;

  /// Roda os vídeos entre os quadros do layout atual (muda a posição).
  final String rotateFrames;

  /// Gira o vídeo no próprio eixo (0/90/180/270º) — um lado de cada vez.
  final String rotateVideo;

  /// Gira todos os vídeos no próprio eixo ao mesmo tempo.
  final String rotateVideos;
  final String sectionOrientation;
  final String vertical;
  final String verticalHint;
  final String horizontal;
  final String horizontalHint;
  final String blinkToggle;
  final String blinkInterval;
  final String holdSpeed;
  final String sectionPerf;
  final String scaler;
  final String scalerBilinear;
  final String scalerBicubic;
  final String scalerLanczos;
  final String videoSync;
  final String syncAudio;
  final String syncResample;
  final String syncDesync;
  final String hwdec;
  final String hwdecOff;
  final String hwdecCompat;
  final String hwdecDirect;
  final String framedrop;
  final String interpolation;
  final String playbackRate;
  final String sectionPlayback;
  final String frameStepCount;
  final String stepFrames1;
  final String stepFrames2;
  final String stepFrames5;
  final String driftMeter;
  final String bufferProfile;
  final String bufferSmall;
  final String bufferNormal;
  final String bufferLarge;
  final String bufferIndicator;
  final String sectionHud;
  final String hudPosition;

  /// Rótulos dos dois eixos da posição das informações.
  final String hudVerticalLabel;
  final String hudHorizontalLabel;
  final String hudPosTop;
  final String hudPosBottom;
  final String hudPosCenter;
  final String hudPosCornerTop;
  final String hudPosCornerBottom;
  final String syncing;
  final String fpsAlways;
  final String statsOverlay;
  final String audioOn;
  final String audioNo;
  final String mutedLabel;
  final String rememberWindowState;
  final String sectionWindow;
  final String settingsNote;
  final String languageLabel;
  final String assistTitle;
  final String assistFallback;
  final String assistNote;
  final String verifyEngine;
  final String verifying;
  final String copyDiagnostic;
  final String chooseAnother;
  final String engineLabel;
  final String engineOk;
  final String engineProblem;
  final String engineBundled;
  final String runtimeAlert;
  final String frame;
  final String dialogTitle;
  final String filterVideo;
  final String filterAll;
  final String sideA;
  final String sideB;
  final String sideC;
  final String sideD;
  final String diagTitle;
  final String diagDate;
  final String diagSide;
  final String diagFile;
  final String diagPath;
  final String diagCode;
  final String diagEngineMessage;
  final String diagEngineFound;
  final String diagEngineBundled;
  final String diagEnginePath;
  final String diagEngineVersion;
  final String diagEngineState;
  final String diagUnknown;
  final String diagNotAvailable;
  final String diagYes;
  final String diagNo;
  final String diagOk;
  final String diagUnavailable;

  /// Secção de atualizações das definições.
  final String sectionUpdates;
  final String updateCurrent;
  final String updateCheckNow;
  final String updateChecking;
  final String updateUpToDate;
  final String updateAvailable;
  final String updateFailed;
  final String updateDownload;
  final String updateOpenReleases;
  final String updateInstall;
  final String updateDownloading;
  final String updateInstalling;
  final String updateInstallFailed;

  static Strings forLanguage(AppLanguage language) => switch (language) {
        AppLanguage.ptBr => ptBr,
        AppLanguage.enUs => enUs,
        AppLanguage.esEs => esEs,
      };

  static const Strings ptBr = Strings(
    language: AppLanguage.ptBr,
    noVideo: 'Sem vídeo',
    open: 'Abrir',
    change: 'Alterar',
    remove: 'Remover',
    removeVideo: 'Remover vídeo',
    muteSide: 'Silenciar vídeo',
    unmuteSide: 'Ativar som do vídeo',
    brandName: 'Video Splitview',
    slogan: 'Lado a lado, frame a frame.',
    dropTitle: 'Arraste ou clique aqui para selecionar um vídeo',
    dropHint: 'MP4 · WebM · MKV · MOV · AVI · M2TS',
    repeat: 'Repetir (Espaço)',
    pause: 'Pausar (Espaço)',
    play: 'Reproduzir (Espaço)',
    stop: 'Parar',
    unmute: 'Ativar som (M)',
    mute: 'Silenciar (M)',
    splitWipe: 'Wipe',
    splitColumns: 'Colunas',
    toggleOrientation: 'Escolher layout da divisão',
    sectionViews: 'Vídeos visíveis',
    viewCountTooltip: 'Número de vídeos na view',
    videoCount1: '1 vídeo',
    videoCount2: '2 vídeos',
    videoCount3: '3 vídeos',
    videoCount4: '4 vídeos',
    layoutColumns3: '3 colunas',
    layoutRows3: '3 linhas',
    layoutTopPair: 'Dois em cima, um em baixo',
    layoutBottomPair: 'Um em cima, dois em baixo',
    layoutLeftSingle: 'Um à esquerda, dois à direita',
    layoutLeftPair: 'Dois à esquerda, um à direita',
    layoutColumns4: '4 colunas',
    layoutRows4: '4 linhas',
    layoutGrid2x2: 'Grelha 2×2',
    layoutTopTriple: 'Três em cima, um em baixo',
    layoutBottomTriple: 'Um em cima, três em baixo',
    layoutLeftTriple: 'Um à esquerda, três à direita',
    layoutRightTriple: 'Três à esquerda, um à direita',
    blink: 'Blink (alterna A↔B)',
    fullscreen: 'Tela cheia (F)',
    copyImage: 'Copiar imagem da comparação',
    saveImage: 'Salvar comparação (PNG)',
    settings: 'Definições',
    copiedImage: 'Imagem copiada para a área de transferência.',
    copyImageFailed: 'Não foi possível copiar a imagem.',
    savedImage: 'Comparação salva (PNG).',
    saveImageFailed: 'Não foi possível salvar a comparação.',
    dualAudio: 'Outro vídeo tem áudio — este foi silenciado',
    blinkTitle: 'Blink',
    letterPosition: 'Posição das letras',
    posTop: 'Topo',
    posCenter: 'Meio',
    posBottom: 'Base',
    posLeft: 'Esquerda',
    posRight: 'Direita',
    posCorner: 'Canto',
    close: 'Fechar',
    sectionView: 'Visualização (sem Blink)',
    wipe: 'Wipe',
    wipeHint: 'N vídeos sobrepostos, a divisória revela',
    columns: 'Colunas',
    columnsHint: 'Cada vídeo na sua célula do layout',
    rotateFrames: 'Rotacionar posição dos vídeos',
    rotateVideo: 'Girar vídeo',
    rotateVideos: 'Girar vídeos',
    sectionOrientation: 'Layout da divisão',
    vertical: 'Vertical',
    verticalHint: 'Lado a lado',
    horizontal: 'Horizontal',
    horizontalHint: 'Cima / baixo',
    blinkToggle: 'Blink (alterna A↔B, ignora o split)',
    blinkInterval: 'Intervalo do Blink',
    holdSpeed: 'Velocidade ao segurar as setas',
    sectionPerf: 'Desempenho / qualidade',
    scaler: 'Escala de vídeo',
    scalerBilinear: 'Bilinear (mais leve)',
    scalerBicubic: 'Bicubic (equilibrado)',
    scalerLanczos: 'Lanczos (melhor)',
    videoSync: 'Sincronização de vídeo',
    syncAudio: 'Audio (padrão)',
    syncResample: 'Display resample (suave)',
    syncDesync: 'Desync (menos GPU)',
    hwdec: 'Descodificação por hardware',
    hwdecOff: 'Desligada (software)',
    hwdecCompat: 'Compatível (auto-copy)',
    hwdecDirect: 'Direta (auto-copy no Windows)',
    framedrop: 'Largar frames atrasados (framedrop)',
    interpolation: 'Interpolação de movimento',
    playbackRate: 'Velocidade de reprodução',
    sectionPlayback: 'Reprodução',
    frameStepCount: 'Passo das setas (quadros)',
    stepFrames1: '1 quadro',
    stepFrames2: '2 quadros',
    stepFrames5: '5 quadros',
    driftMeter: 'Medidor de dessincronia (Δ A↔B)',
    bufferProfile: 'Perfil de buffer',
    bufferSmall: 'Pequeno (64 MB)',
    bufferNormal: 'Normal (150 MB)',
    bufferLarge: 'Grande (512 MB)',
    bufferIndicator: 'Informação de buffer por vídeo',
    sectionHud: 'Informações sobrepostas',
    hudPosition: 'Posição das informações',
    hudVerticalLabel: 'Posição vertical',
    hudHorizontalLabel: 'Posição horizontal',
    hudPosTop: 'Topo',
    hudPosBottom: 'Baixo',
    hudPosCenter: 'Centro',
    hudPosCornerTop: 'Canto superior',
    hudPosCornerBottom: 'Canto inferior',
    syncing: 'Sincronizando...',
    fpsAlways: 'Mostrar FPS',
    statsOverlay: 'Estatísticas completas por vídeo',
    audioOn: 'com áudio',
    audioNo: 'sem áudio',
    mutedLabel: 'silenciado',
    rememberWindowState: 'Lembrar tamanho e posição do aplicativo',
    sectionWindow: 'Janela',
    settingsNote:
        'Setas: passo de quadro configurável (1/2/5) · Shift+setas: 1 s · Ctrl+setas: 5 s. No Windows o media_kit usa descodificação copy-back (sem zero-copy).',
    languageLabel: 'Idioma',
    assistTitle: 'Não foi possível reproduzir este vídeo',
    assistFallback: 'O motor de vídeo não conseguiu abrir este ficheiro.',
    assistNote:
        'Este app usa o motor libmpv (via media_kit). Instalar codecs avulsos no Windows normalmente não faz este leitor funcionar — a DLL do libmpv traz os codecs.',
    verifyEngine: 'Verificar motor',
    verifying: 'A verificar…',
    copyDiagnostic: 'Copiar diagnóstico',
    chooseAnother: 'Escolher outro ficheiro',
    engineLabel: 'Motor de vídeo',
    engineOk: 'OK',
    engineProblem: 'com problema',
    engineBundled: 'empacotado',
    runtimeAlert: 'libmpv indisponível',
    frame: 'Quadro',
    dialogTitle: 'Selecionar vídeo(s)',
    filterVideo: 'Vídeo',
    filterAll: 'Todos os ficheiros',
    sideA: 'A (esquerda)',
    sideB: 'B (direita)',
    sideC: 'C',
    sideD: 'D',
    diagTitle: 'Video Splitview — diagnóstico de reprodução',
    diagDate: 'Data',
    diagSide: 'Lado',
    diagFile: 'Ficheiro',
    diagPath: 'Caminho',
    diagCode: 'Código',
    diagEngineMessage: 'Mensagem do motor',
    diagEngineFound: 'Motor libmpv encontrado',
    diagEngineBundled: 'Motor empacotado',
    diagEnginePath: 'Caminho do motor',
    diagEngineVersion: 'Versão do motor',
    diagEngineState: 'Estado do motor',
    diagUnknown: '(desconhecido)',
    diagNotAvailable: '(n/d)',
    diagYes: 'sim',
    diagNo: 'não',
    diagOk: 'OK',
    diagUnavailable: 'indisponível',
    sectionUpdates: 'Atualizações',
    updateCurrent: 'Versão atual',
    updateCheckNow: 'Verificar',
    updateChecking: 'A verificar…',
    updateUpToDate: 'Está na versão mais recente.',
    updateAvailable: 'Nova versão disponível',
    updateFailed: 'Não foi possível verificar atualizações.',
    updateDownload: 'Baixar atualização',
    updateOpenReleases: 'Abrir releases',
    updateInstall: 'Atualizar',
    updateDownloading: 'A transferir…',
    updateInstalling: 'A instalar…',
    updateInstallFailed: 'Não foi possível atualizar.',
  );

  static const Strings enUs = Strings(
    language: AppLanguage.enUs,
    noVideo: 'No video',
    open: 'Open',
    change: 'Change',
    remove: 'Remove',
    removeVideo: 'Remove video',
    muteSide: 'Mute video',
    unmuteSide: 'Unmute video',
    brandName: 'Video Splitview',
    slogan: 'Side by side, frame by frame.',
    dropTitle: 'Drag or click here to select a video',
    dropHint: 'MP4 · WebM · MKV · MOV · AVI · M2TS',
    repeat: 'Replay (Space)',
    pause: 'Pause (Space)',
    play: 'Play (Space)',
    stop: 'Stop',
    unmute: 'Unmute (M)',
    mute: 'Mute (M)',
    splitWipe: 'Wipe',
    splitColumns: 'Columns',
    toggleOrientation: 'Choose split layout',
    sectionViews: 'Visible videos',
    viewCountTooltip: 'Number of videos in view',
    videoCount1: '1 video',
    videoCount2: '2 videos',
    videoCount3: '3 videos',
    videoCount4: '4 videos',
    layoutColumns3: '3 columns',
    layoutRows3: '3 rows',
    layoutTopPair: 'Two on top, one below',
    layoutBottomPair: 'One on top, two below',
    layoutLeftSingle: 'One left, two right',
    layoutLeftPair: 'Two left, one right',
    layoutColumns4: '4 columns',
    layoutRows4: '4 rows',
    layoutGrid2x2: '2×2 grid',
    layoutTopTriple: 'Three on top, one below',
    layoutBottomTriple: 'One on top, three below',
    layoutLeftTriple: 'One left, three right',
    layoutRightTriple: 'Three left, one right',
    blink: 'Blink (toggles A↔B)',
    fullscreen: 'Fullscreen (F)',
    copyImage: 'Copy comparison image',
    saveImage: 'Save comparison (PNG)',
    settings: 'Settings',
    copiedImage: 'Image copied to clipboard.',
    copyImageFailed: 'Could not copy the image.',
    savedImage: 'Comparison saved (PNG).',
    saveImageFailed: 'Could not save the comparison.',
    dualAudio: 'Another video has audio — this one was muted',
    blinkTitle: 'Blink',
    letterPosition: 'Letter position',
    posTop: 'Top',
    posCenter: 'Middle',
    posBottom: 'Bottom',
    posLeft: 'Left',
    posRight: 'Right',
    posCorner: 'Corner',
    close: 'Close',
    sectionView: 'View (without Blink)',
    wipe: 'Wipe',
    wipeHint: 'Videos overlaid, dividers reveal',
    columns: 'Columns',
    columnsHint: 'Each video in its layout cell',
    rotateFrames: 'Rotate video positions',
    rotateVideo: 'Rotate video',
    rotateVideos: 'Rotate videos',
    sectionOrientation: 'Split layout',
    vertical: 'Vertical',
    verticalHint: 'Side by side',
    horizontal: 'Horizontal',
    horizontalHint: 'Top / bottom',
    blinkToggle: 'Blink (toggles A↔B, ignores the split)',
    blinkInterval: 'Blink interval',
    holdSpeed: 'Speed while holding the arrow keys',
    sectionPerf: 'Performance / quality',
    scaler: 'Video scaling',
    scalerBilinear: 'Bilinear (lightest)',
    scalerBicubic: 'Bicubic (balanced)',
    scalerLanczos: 'Lanczos (best)',
    videoSync: 'Video sync',
    syncAudio: 'Audio (default)',
    syncResample: 'Display resample (smooth)',
    syncDesync: 'Desync (less GPU)',
    hwdec: 'Hardware decoding',
    hwdecOff: 'Off (software)',
    hwdecCompat: 'Compatible (auto-copy)',
    hwdecDirect: 'Direct (auto-copy on Windows)',
    framedrop: 'Drop late frames (framedrop)',
    interpolation: 'Motion interpolation',
    playbackRate: 'Playback speed',
    sectionPlayback: 'Playback',
    frameStepCount: 'Arrow step size (frames)',
    stepFrames1: '1 frame',
    stepFrames2: '2 frames',
    stepFrames5: '5 frames',
    driftMeter: 'Drift meter (Δ A↔B)',
    bufferProfile: 'Buffer profile',
    bufferSmall: 'Small (64 MB)',
    bufferNormal: 'Normal (150 MB)',
    bufferLarge: 'Large (512 MB)',
    bufferIndicator: 'Per-video buffer info',
    sectionHud: 'On-video overlays',
    hudPosition: 'Overlay position',
    hudVerticalLabel: 'Vertical position',
    hudHorizontalLabel: 'Horizontal position',
    hudPosTop: 'Top',
    hudPosBottom: 'Bottom',
    hudPosCenter: 'Center',
    hudPosCornerTop: 'Top corner',
    hudPosCornerBottom: 'Bottom corner',
    syncing: 'Syncing...',
    fpsAlways: 'Show FPS',
    statsOverlay: 'Full per-video statistics',
    audioOn: 'with audio',
    audioNo: 'no audio',
    mutedLabel: 'muted',
    rememberWindowState: 'Remember app size and position',
    sectionWindow: 'Window',
    settingsNote:
        'Arrows: configurable frame step (1/2/5) · Shift+arrows: 1 s · Ctrl+arrows: 5 s. On Windows media_kit uses copy-back decoding (no zero-copy).',
    languageLabel: 'Language',
    assistTitle: 'Could not play this video',
    assistFallback: 'The video engine could not open this file.',
    assistNote:
        'This app uses the libmpv engine (via media_kit). Installing codecs on Windows usually does not make this player work — the libmpv DLL ships the codecs.',
    verifyEngine: 'Check engine',
    verifying: 'Checking…',
    copyDiagnostic: 'Copy diagnostic',
    chooseAnother: 'Choose another file',
    engineLabel: 'Video engine',
    engineOk: 'OK',
    engineProblem: 'has an issue',
    engineBundled: 'bundled',
    runtimeAlert: 'libmpv unavailable',
    frame: 'Frame',
    dialogTitle: 'Select video(s)',
    filterVideo: 'Video',
    filterAll: 'All files',
    sideA: 'A (left)',
    sideB: 'B (right)',
    sideC: 'C',
    sideD: 'D',
    diagTitle: 'Video Splitview — playback diagnostic',
    diagDate: 'Date',
    diagSide: 'Side',
    diagFile: 'File',
    diagPath: 'Path',
    diagCode: 'Code',
    diagEngineMessage: 'Engine message',
    diagEngineFound: 'libmpv engine found',
    diagEngineBundled: 'Engine bundled',
    diagEnginePath: 'Engine path',
    diagEngineVersion: 'Engine version',
    diagEngineState: 'Engine state',
    diagUnknown: '(unknown)',
    diagNotAvailable: '(n/a)',
    diagYes: 'yes',
    diagNo: 'no',
    diagOk: 'OK',
    diagUnavailable: 'unavailable',
    sectionUpdates: 'Updates',
    updateCurrent: 'Current version',
    updateCheckNow: 'Check',
    updateChecking: 'Checking…',
    updateUpToDate: 'You are on the latest version.',
    updateAvailable: 'A new version is available',
    updateFailed: 'Could not check for updates.',
    updateDownload: 'Download update',
    updateOpenReleases: 'Open releases',
    updateInstall: 'Update',
    updateDownloading: 'Downloading…',
    updateInstalling: 'Installing…',
    updateInstallFailed: 'Could not update.',
  );

  static const Strings esEs = Strings(
    language: AppLanguage.esEs,
    noVideo: 'Sin vídeo',
    open: 'Abrir',
    change: 'Cambiar',
    remove: 'Quitar',
    removeVideo: 'Quitar vídeo',
    muteSide: 'Silenciar vídeo',
    unmuteSide: 'Activar sonido del vídeo',
    brandName: 'Video Splitview',
    slogan: 'Lado a lado, fotograma a fotograma.',
    dropTitle: 'Arrastra o haz clic aquí para seleccionar un vídeo',
    dropHint: 'MP4 · WebM · MKV · MOV · AVI · M2TS',
    repeat: 'Repetir (Espacio)',
    pause: 'Pausar (Espacio)',
    play: 'Reproducir (Espacio)',
    stop: 'Parar',
    unmute: 'Activar sonido (M)',
    mute: 'Silenciar (M)',
    splitWipe: 'Wipe',
    splitColumns: 'Columnas',
    toggleOrientation: 'Elegir diseño de la división',
    sectionViews: 'Vídeos visibles',
    viewCountTooltip: 'Número de vídeos en la vista',
    videoCount1: '1 vídeo',
    videoCount2: '2 vídeos',
    videoCount3: '3 vídeos',
    videoCount4: '4 vídeos',
    layoutColumns3: '3 columnas',
    layoutRows3: '3 filas',
    layoutTopPair: 'Dos arriba, uno abajo',
    layoutBottomPair: 'Uno arriba, dos abajo',
    layoutLeftSingle: 'Uno a la izquierda, dos a la derecha',
    layoutLeftPair: 'Dos a la izquierda, uno a la derecha',
    layoutColumns4: '4 columnas',
    layoutRows4: '4 filas',
    layoutGrid2x2: 'Cuadrícula 2×2',
    layoutTopTriple: 'Tres arriba, uno abajo',
    layoutBottomTriple: 'Uno arriba, tres abajo',
    layoutLeftTriple: 'Uno a la izquierda, tres a la derecha',
    layoutRightTriple: 'Tres a la izquierda, uno a la derecha',
    blink: 'Blink (alterna A↔B)',
    fullscreen: 'Pantalla completa (F)',
    copyImage: 'Copiar imagen de la comparación',
    saveImage: 'Guardar comparación (PNG)',
    settings: 'Ajustes',
    copiedImage: 'Imagen copiada al portapapeles.',
    copyImageFailed: 'No se pudo copiar la imagen.',
    savedImage: 'Comparación guardada (PNG).',
    saveImageFailed: 'No se pudo guardar la comparación.',
    dualAudio: 'Otro vídeo tiene audio — este fue silenciado',
    blinkTitle: 'Blink',
    letterPosition: 'Posición de las letras',
    posTop: 'Arriba',
    posCenter: 'Centro',
    posBottom: 'Abajo',
    posLeft: 'Izquierda',
    posRight: 'Derecha',
    posCorner: 'Esquina',
    close: 'Cerrar',
    sectionView: 'Visualización (sin Blink)',
    wipe: 'Wipe',
    wipeHint: 'Vídeos superpuestos, los divisores revelan',
    columns: 'Columnas',
    columnsHint: 'Cada vídeo en su celda del diseño',
    rotateFrames: 'Rotar posiciones de los vídeos',
    rotateVideo: 'Girar vídeo',
    rotateVideos: 'Girar vídeos',
    sectionOrientation: 'Diseño de la división',
    vertical: 'Vertical',
    verticalHint: 'Lado a lado',
    horizontal: 'Horizontal',
    horizontalHint: 'Arriba / abajo',
    blinkToggle: 'Blink (alterna A↔B, ignora el split)',
    blinkInterval: 'Intervalo del Blink',
    holdSpeed: 'Velocidad al mantener las flechas',
    sectionPerf: 'Rendimiento / calidad',
    scaler: 'Escalado de vídeo',
    scalerBilinear: 'Bilinear (más ligero)',
    scalerBicubic: 'Bicubic (equilibrado)',
    scalerLanczos: 'Lanczos (mejor)',
    videoSync: 'Sincronización de vídeo',
    syncAudio: 'Audio (predeterminado)',
    syncResample: 'Display resample (suave)',
    syncDesync: 'Desync (menos GPU)',
    hwdec: 'Decodificación por hardware',
    hwdecOff: 'Desactivada (software)',
    hwdecCompat: 'Compatible (auto-copy)',
    hwdecDirect: 'Directa (auto-copy en Windows)',
    framedrop: 'Descartar fotogramas tardíos (framedrop)',
    interpolation: 'Interpolación de movimiento',
    playbackRate: 'Velocidad de reproducción',
    sectionPlayback: 'Reproducción',
    frameStepCount: 'Paso de las flechas (fotogramas)',
    stepFrames1: '1 fotograma',
    stepFrames2: '2 fotogramas',
    stepFrames5: '5 fotogramas',
    driftMeter: 'Medidor de desincronización (Δ A↔B)',
    bufferProfile: 'Perfil de búfer',
    bufferSmall: 'Pequeño (64 MB)',
    bufferNormal: 'Normal (150 MB)',
    bufferLarge: 'Grande (512 MB)',
    bufferIndicator: 'Información de búfer por vídeo',
    sectionHud: 'Información superpuesta',
    hudPosition: 'Posición de la información',
    hudVerticalLabel: 'Posición vertical',
    hudHorizontalLabel: 'Posición horizontal',
    hudPosTop: 'Superior',
    hudPosBottom: 'Inferior',
    hudPosCenter: 'Centro',
    hudPosCornerTop: 'Esquina superior',
    hudPosCornerBottom: 'Esquina inferior',
    syncing: 'Sincronizando...',
    fpsAlways: 'Mostrar FPS',
    statsOverlay: 'Estadísticas completas por vídeo',
    audioOn: 'con audio',
    audioNo: 'sin audio',
    mutedLabel: 'silenciado',
    rememberWindowState: 'Recordar tamaño y posición de la aplicación',
    sectionWindow: 'Ventana',
    settingsNote:
        'Flechas: paso de fotograma configurable (1/2/5) · Shift+flechas: 1 s · Ctrl+flechas: 5 s. En Windows media_kit usa decodificación copy-back (sin zero-copy).',
    languageLabel: 'Idioma',
    assistTitle: 'No se pudo reproducir este vídeo',
    assistFallback: 'El motor de vídeo no pudo abrir este archivo.',
    assistNote:
        'Esta app usa el motor libmpv (vía media_kit). Instalar códecs en Windows normalmente no hace que este reproductor funcione — el DLL de libmpv incluye los códecs.',
    verifyEngine: 'Comprobar motor',
    verifying: 'Comprobando…',
    copyDiagnostic: 'Copiar diagnóstico',
    chooseAnother: 'Elegir otro archivo',
    engineLabel: 'Motor de vídeo',
    engineOk: 'OK',
    engineProblem: 'con problema',
    engineBundled: 'incluido',
    runtimeAlert: 'libmpv no disponible',
    frame: 'Fotograma',
    dialogTitle: 'Seleccionar vídeo(s)',
    filterVideo: 'Vídeo',
    filterAll: 'Todos los archivos',
    sideA: 'A (izquierda)',
    sideB: 'B (derecha)',
    sideC: 'C',
    sideD: 'D',
    diagTitle: 'Video Splitview — diagnóstico de reproducción',
    diagDate: 'Fecha',
    diagSide: 'Lado',
    diagFile: 'Archivo',
    diagPath: 'Ruta',
    diagCode: 'Código',
    diagEngineMessage: 'Mensaje del motor',
    diagEngineFound: 'Motor libmpv encontrado',
    diagEngineBundled: 'Motor incluido',
    diagEnginePath: 'Ruta del motor',
    diagEngineVersion: 'Versión del motor',
    diagEngineState: 'Estado del motor',
    diagUnknown: '(desconocido)',
    diagNotAvailable: '(n/d)',
    diagYes: 'sí',
    diagNo: 'no',
    diagOk: 'OK',
    diagUnavailable: 'no disponible',
    sectionUpdates: 'Actualizaciones',
    updateCurrent: 'Versión actual',
    updateCheckNow: 'Buscar',
    updateChecking: 'Comprobando…',
    updateUpToDate: 'Estás en la versión más reciente.',
    updateAvailable: 'Nueva versión disponible',
    updateFailed: 'No se pudieron buscar actualizaciones.',
    updateDownload: 'Descargar actualización',
    updateOpenReleases: 'Abrir releases',
    updateInstall: 'Actualizar',
    updateDownloading: 'Descargando…',
    updateInstalling: 'Instalando…',
    updateInstallFailed: 'No se pudo actualizar.',
  );
}

/// Nome apresentável de um layout de divisão no idioma ativo.
String layoutName(SplitLayout layout, Strings s) => switch (layout) {
      SplitLayout.sideBySide => s.verticalHint,
      SplitLayout.stacked => s.horizontalHint,
      SplitLayout.columns3 => s.layoutColumns3,
      SplitLayout.rows3 => s.layoutRows3,
      SplitLayout.topPairBottomSingle => s.layoutTopPair,
      SplitLayout.topSingleBottomPair => s.layoutBottomPair,
      SplitLayout.singleLeftPairRight => s.layoutLeftSingle,
      SplitLayout.pairLeftSingleRight => s.layoutLeftPair,
      SplitLayout.columns4 => s.layoutColumns4,
      SplitLayout.rows4 => s.layoutRows4,
      SplitLayout.grid2x2 => s.layoutGrid2x2,
      SplitLayout.topTripleBottomSingle => s.layoutTopTriple,
      SplitLayout.topSingleBottomTriple => s.layoutBottomTriple,
      SplitLayout.singleLeftTripleRight => s.layoutLeftTriple,
      SplitLayout.tripleLeftSingleRight => s.layoutRightTriple,
    };

/// Rótulo completo de um lado (A..D) no idioma ativo.
String sideLabelOf(Side side, Strings s) => switch (side) {
      Side.a => s.sideA,
      Side.b => s.sideB,
      Side.c => s.sideC,
      Side.d => s.sideD,
    };

/// Rótulo curto do número de vídeos (`1 vídeo`, `2 vídeos`, ...).
String viewCountLabel(int count, Strings s) => switch (clampViewCount(count)) {
      1 => s.videoCount1,
      3 => s.videoCount3,
      4 => s.videoCount4,
      _ => s.videoCount2,
    };
