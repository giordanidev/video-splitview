/// Palco de comparação: 1-4 vídeos, layouts de divisão, wipe/colunas/blink,
/// splitters e drag&drop.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../backend/i18n/strings.dart';
import '../../backend/models/models.dart';
import '../../backend/services/playback_bridge.dart';
import '../../backend/state/providers.dart';
import '../../backend/state/settings.dart';
import '../theme/theme.dart';
import 'common.dart';
import 'top_bar.dart';

class Stage extends ConsumerStatefulWidget {
  const Stage({super.key});

  @override
  ConsumerState<Stage> createState() => _StageState();
}

class _StageState extends ConsumerState<Stage> {
  /// Margem dos overlays em relação à borda do view.
  static const double _hudMargin = 12;

  /// Altura de referência das pills para alinhar o centro.
  static const double _hudHeight = 26;

  /// Altura estimada do bloco de estatísticas completas.
  static const double _statsHeight = 145;

  /// Dimensões fixas da pill de dessincronia (reserva de espaço nas pontas).
  static const double _driftWidth = 96;
  static const double _driftHeight = 34;

  /// Espaço entre a pill de drift e os grupos A/B (ou 10 sem drift).
  static const double _pillGap = 8;

  /// Largura máxima estimada dos grupos de overlay (para colisões do drift).
  static const double _groupMaxWidth = 240;

  /// Fronteiras de coluna (interiores, %) — `cols-1` valores por layout.
  List<double> _colSplits = [50];

  /// Fronteiras de linha (interiores, %) — `rows-1` valores por layout.
  List<double> _rowSplits = [50];

  bool _armed = false;
  bool _dragging = false;
  int _blinkIndex = 0;
  List<Side> _blinkSides = const <Side>[];
  Timer? _blinkTimer;
  int _lastInterval = -1;
  bool _lastBlinkEnabled = false;
  Side? _highlight;
  SplitLayout? _lastSplitLayout;

  /// Células mais recentes para os callbacks do `DropTarget`. Guardadas em
  /// campo de instância (em vez da variável local do build) para que
  /// callbacks capturados na primeira build continuem a apontar para a célula
  /// certa depois de os quadros serem trocados.
  Map<Side, CellRect> _dropCells = const <Side, CellRect>{};

  @override
  void dispose() {
    _closeFrameMenu();
    _blinkTimer?.cancel();
    super.dispose();
  }

  void _restartBlink(int intervalMs, bool enabled) {
    _lastInterval = intervalMs;
    _lastBlinkEnabled = enabled;
    _blinkTimer?.cancel();
    _blinkIndex = 0;
    if (!enabled) return;
    _blinkTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (!mounted) return;
      setState(() {
        final count = _blinkSides.length;
        if (count > 0) _blinkIndex = (_blinkIndex + 1) % count;
      });
    });
  }

  /// Mantém os arrays de splits com a dimensão certa do layout atual.
  void _syncSplitLengths(SplitLayout layout) {
    if (_lastSplitLayout == layout) return;
    final spec = layoutSpec(layout);
    _lastSplitLayout = layout;
    _colSplits = defaultColSplits(spec.cols);
    _rowSplits = defaultRowSplits(spec.rows);
  }

  /// Atualiza a fronteira interior `boundary` (1-based) do eixo indicado.
  void _setBoundary({
    required int boundary,
    required bool horizontal,
    required double percent,
    required Size size,
  }) {
    final list = horizontal ? _rowSplits : _colSplits;
    final idx = boundary - 1;
    if (idx < 0 || idx >= list.length) return;
    final total = horizontal ? size.height : size.width;
    if (total <= 0) return;
    final min = idx == 0
        ? splitMinCellPercent
        : list[idx - 1] + splitMinCellPercent;
    final max = idx == list.length - 1
        ? 100 - splitMinCellPercent
        : list[idx + 1] - splitMinCellPercent;
    final clamped = percent.clamp(min, max).toDouble();
    setState(() => list[idx] = clamped);
  }

  void _updateSplitFromLocal(
      Offset local, Size size, bool horizontal, {int boundary = 1}) {
    final pct = horizontal
        ? (size.height <= 0 ? 50.0 : local.dy / size.height * 100)
        : (size.width <= 0 ? 50.0 : local.dx / size.width * 100);
    _setBoundary(
      boundary: boundary,
      horizontal: horizontal,
      percent: pct,
      size: size,
    );
  }

  /// Repõe uma fronteira (ou o eixo todo em double-tap) no valor igual.
  void _center({bool? horizontal, SplitLayout? layout}) {
    setState(() {
      final effective = layout ?? _lastSplitLayout ?? SplitLayout.sideBySide;
      final spec = layoutSpec(effective);
      if (horizontal == null || !horizontal) {
        _colSplits = defaultColSplits(spec.cols);
      }
      if (horizontal == null || horizontal) {
        _rowSplits = defaultRowSplits(spec.rows);
      }
      _armed = false;
      _dragging = false;
    });
  }

  /// Lado cuja célula contém o ponto (fallback: célula mais próxima).
  Side _sideAtPoint(Offset local, Map<Side, CellRect> cells) {
    CellRect? fallback;
    var fallbackSide = cells.keys.first;
    var fallbackDistance = double.infinity;
    for (final entry in cells.entries) {
      final cell = entry.value;
      if (cell.contains(local.dx, local.dy)) return entry.key;
      final dx = local.dx - cell.centerX;
      final dy = local.dy - cell.centerY;
      final distance = dx * dx + dy * dy;
      if (distance < fallbackDistance) {
        fallbackDistance = distance;
        fallback = cell;
        fallbackSide = entry.key;
      }
    }
    return fallback == null ? fallbackSide : fallbackSide;
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(playbackBridgeProvider);
    final settings = ref.watch(settingsProvider);
    final strings = ref.watch(stringsProvider);
    final viewCount = settings.effectiveViewCount;
    final layout = settings.effectiveLayout;
    final horizontal = layout == SplitLayout.stacked;
    final twoVideo = viewCount == 2;
    _syncSplitLengths(layout);

    if (settings.blinkEnabled != _lastBlinkEnabled ||
        settings.blinkIntervalMs != _lastInterval) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _restartBlink(settings.blinkIntervalMs, settings.blinkEnabled);
        }
      });
    }

    return Padding(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return ListenableBuilder(
            listenable: bridge,
            builder: (context, _) {
              final active = Side.forViewCount(viewCount);
              final loadedActive = active
                  .where((side) => bridge.stateOf(side).loaded)
                  .toList(growable: false);
              final comparing = loadedActive.isNotEmpty;
              final cells = resolveLayoutCells(
                viewCount: viewCount,
                layout: layout,
                width: size.width,
                height: size.height,
                colSplits: _colSplits,
                rowSplits: _rowSplits,
              );
              _dropCells = cells;

              _blinkSides = loadedActive;
              if (_blinkIndex >= _blinkSides.length) _blinkIndex = 0;
              final blinkOn =
                  settings.blinkEnabled && loadedActive.length >= 2;
              final visibleSide = _blinkSides.isEmpty
                  ? null
                  : _blinkSides[_blinkIndex % _blinkSides.length];
              final wipeOn = !blinkOn &&
                  viewCount >= 2 &&
                  loadedActive.length >= 2 &&
                  settings.splitMode == SplitMode.wipe;

              // O corpo do palco (gestos + vídeos) fica por baixo; o alvo de
              // ficheiros é um painel transparente sempre no topo (ver o
              // `DropTarget` no Stack interno), para o drop do SO nunca ser
              // "tapado" pelo vídeo.
              return MouseRegion(
                  cursor: twoVideo && comparing
                      ? SystemMouseCursors.click
                      : MouseCursor.defer,
                  onHover: (event) {
                    if (twoVideo && comparing && (_armed || _dragging)) {
                      _updateSplitFromLocal(
                          event.localPosition, size, horizontal);
                    }
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: twoVideo && comparing
                        ? () => setState(() => _armed = !_armed)
                        : null,
                    onDoubleTap:
                        twoVideo && comparing ? _center : null,
                    child: ClipRect(
                      child: Container(
                        color: AppColors.bg,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: _buildContent(
                                bridge: bridge,
                                settings: settings,
                                cells: cells,
                                active: active,
                                blinkOn: blinkOn,
                                wipeOn: wipeOn,
                                visibleSide: visibleSide,
                                viewCount: viewCount,
                              ),
                            ),
                            // Divisórias arrastáveis: UX arm/hover em 2 vídeos;
                            // segmentos com boundary em 3/4; nenhuma em 1.
                            if (!blinkOn && twoVideo)
                              _buildDivider(horizontal, size, enabled: comparing),
                            if (!blinkOn && viewCount >= 3)
                              ..._buildDraggableDividers(cells, size,
                                  enabled: comparing),
                            if (comparing && !blinkOn)
                              ..._buildOverlays(
                                bridge,
                                settings,
                                strings,
                                size,
                                horizontal,
                                cells,
                                active,
                                wipeOn: wipeOn,
                              ),
                            if (comparing && !blinkOn)
                              ..._buildSyncSpinners(
                                bridge,
                                strings,
                                cells,
                                active,
                              ),
                            if (comparing && !blinkOn && viewCount >= 2)
                              ..._buildDragHandles(bridge, size, cells, active),
                            // Toast de áudio dual: centro da célula do vídeo
                            // que a política acabou de silenciar.
                            ..._buildDualAudioToasts(
                                bridge, strings, cells, active),
                            if (blinkOn && visibleSide != null)
                              _buildBlinkLetter(
                                  bridge,
                                  visibleSide,
                                  settings.blinkLetterPosition,
                                  viewCount,
                                  cells),
                            // Painel transparente sempre no topo: dá ao
                            // `DropTarget` um RenderBox do tamanho do palco
                            // (o plugin usa bounds, não hit-test do Flutter).
                            // `IgnorePointer` deixa passar gestos/alças/divisórias.
                            // `localPosition` já vem nas coords do palco (= células).
                            Positioned.fill(
                              child: IgnorePointer(
                                child: DropTarget(
                                  onDragEntered: (detail) {
                                    setState(() => _highlight = _sideAtPoint(
                                        detail.localPosition, _dropCells));
                                  },
                                  onDragExited: (_) =>
                                      setState(() => _highlight = null),
                                  onDragUpdated: (detail) {
                                    setState(() => _highlight = _sideAtPoint(
                                        detail.localPosition, _dropCells));
                                  },
                                  onDragDone: (detail) {
                                    final side = _sideAtPoint(
                                        detail.localPosition, _dropCells);
                                    final paths =
                                        detail.files.map((f) => f.path).toList();
                                    setState(() => _highlight = null);
                                    assignPaths(ref, bridge, side, paths);
                                  },
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
            },
          );
        },
      ),
    );
  }

  Widget _buildContent({
    required PlaybackBridge bridge,
    required AppSettings settings,
    required Map<Side, CellRect> cells,
    required List<Side> active,
    required bool blinkOn,
    required bool wipeOn,
    required Side? visibleSide,
    required int viewCount,
  }) {
    if (blinkOn && visibleSide != null) {
      return SizedBox.expand(child: _video(bridge, visibleSide));
    }
    if (wipeOn) {
      // Vídeos pintados a ecrã cheio (clipados à célula) NÃO podem ser o
      // `DragTarget`: `ClipRect` só corta a pintura, o hit-test ficava no
      // palco inteiro e o último lado da stack ganhava sempre. Separar:
      // (1) pintura IgnorePointer; (2) alvos de troca só na área da célula.
      return Stack(
        children: [
          for (final side in active)
            if (cells[side] case final cell?)
              if (bridge.stateOf(side).loaded)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRect(
                      clipper: _CellClipper(cell: cell),
                      child: _video(bridge, side),
                    ),
                  ),
                ),
          for (final side in active)
            if (cells[side] case final cell?)
              Positioned(
                left: cell.left,
                top: cell.top,
                width: cell.width,
                height: cell.height,
                child: bridge.stateOf(side).loaded
                    ? _frameMenu(
                        bridge,
                        side,
                        _swapTarget(
                          side,
                          const SizedBox.expand(),
                          staticBorder: true,
                          dropOver: _highlight == side,
                        ),
                      )
                    : _swapTarget(
                        side,
                        _dropPane(bridge, side),
                        dropOver: _highlight == side,
                      ),
              ),
          for (final side in active)
            if (cells[side] case final cell?)
              Positioned(
                left: cell.left + 8,
                top: cell.top + 8,
                child: IgnorePointer(child: _cornerLabel(side.label)),
              ),
        ],
      );
    }
    return _buildGrid(
      bridge: bridge,
      cells: cells,
      active: active,
    );
  }

  /// Grelha de células: vídeo onde há ficheiro, drop pane onde não há.
  /// Sempre com a badge da letra no canto superior esquerdo de cada célula.
  Widget _buildGrid({
    required PlaybackBridge bridge,
    required Map<Side, CellRect> cells,
    required List<Side> active,
  }) {
    return Stack(
      children: [
        for (final side in active)
          if (cells[side] case final cell?)
            Positioned(
              left: cell.left,
              top: cell.top,
              width: cell.width,
              height: cell.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _cellContent(bridge, side),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: IgnorePointer(child: _cornerLabel(side.label)),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Widget _cellContent(PlaybackBridge bridge, Side side) {
    final loaded = bridge.stateOf(side).loaded;
    if (!loaded) {
      return _swapTarget(side, _dropPane(bridge, side),
          dropOver: _highlight == side);
    }
    return _frameMenu(
      bridge,
      side,
      _swapTarget(side, _video(bridge, side),
          staticBorder: true, dropOver: _highlight == side),
    );
  }

  /// Overlay do menu de contexto do quadro (substitui `showMenu` para
  /// permitir reabrir noutro quadro com um único clique direito).
  OverlayEntry? _frameMenuEntry;

  /// Menu de contexto (botão direito) num quadro com vídeo: mesmas ações
  /// do header — Alterar, Remover, Girar, Silenciar.
  Widget _frameMenu(PlaybackBridge bridge, Side side, Widget child) {
    return Builder(
      builder: (context) {
        return MouseRegion(
          cursor: SystemMouseCursors.contextMenu,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if (event.buttons != kSecondaryMouseButton) return;
              final strings = ref.read(stringsProvider);
              _openFrameMenu(
                context,
                event.position,
                bridge,
                side,
                strings,
              );
            },
            child: child,
          ),
        );
      },
    );
  }

  void _closeFrameMenu() {
    _frameMenuEntry?.remove();
    _frameMenuEntry = null;
  }

  void _openFrameMenu(
    BuildContext context,
    Offset globalPosition,
    PlaybackBridge bridge,
    Side side,
    Strings strings,
  ) {
    final state = bridge.stateOf(side);
    if (!state.loaded) return;
    // Fecha o menu atual (se houver) e abre o novo no mesmo gesto —
    // sem precisar de dois cliques.
    _closeFrameMenu();

    final muted = state.muted || state.volume <= 0;
    final fileName = state.name?.trim();
    final title = (fileName == null || fileName.isEmpty)
        ? side.label
        : '${side.label} · $fileName';
    final overlay = Overlay.of(context);
    final media = MediaQuery.sizeOf(context);
    const menuWidth = 240.0;
    const estimatedHeight = 220.0;
    final left = globalPosition.dx
        .clamp(8.0, math.max(8.0, media.width - menuWidth - 8))
        .toDouble();
    final top = globalPosition.dy
        .clamp(8.0, math.max(8.0, media.height - estimatedHeight - 8))
        .toDouble();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _FrameContextMenuOverlay(
        left: left,
        top: top,
        title: title,
        changeLabel: strings.change,
        removeLabel: strings.removeVideo,
        rotateLabel: strings.rotateVideo,
        muteLabel: muted ? strings.unmuteSide : strings.muteSide,
        muteIcon: muted ? Icons.volume_up : Icons.volume_off,
        onDismiss: () {
          // Só fecha se ainda for este entry — evita que o dismiss do menu
          // anterior (mesmo pointer down) derrube o menu acabado de abrir.
          if (identical(_frameMenuEntry, entry)) _closeFrameMenu();
        },
        onSelect: (action) async {
          if (identical(_frameMenuEntry, entry)) _closeFrameMenu();
          switch (action) {
            case 'change':
              await pickFor(ref, bridge, side, strings);
            case 'remove':
              await bridge.unloadSide(side);
            case 'rotate':
              await bridge.rotateVideo(side);
            case 'mute':
              await bridge.toggleMuteSide(side);
          }
        },
      ),
    );
    _frameMenuEntry = entry;
    overlay.insert(entry);
  }

  /// Célula como alvo de troca: largar a alça de outro vídeo aqui troca as
  /// posições dos dois vídeos (realçada enquanto se arrasta por cima).
  ///
  /// - `staticBorder`: mostra sempre a borda do card de vídeo; os drop panes
  ///   já têm a sua própria borda e só ganham o realce.
  /// - `dropOver`: realce da célula enquanto se arrasta um ficheiro por cima
  ///   (`_highlight`), para o hover do file-drop acompanhar a célula certa.
  Widget _swapTarget(
    Side side,
    Widget child, {
    bool staticBorder = false,
    bool dropOver = false,
  }) {
    return DragTarget<Side>(
      onWillAcceptWithDetails: (details) => details.data != side,
      onAcceptWithDetails: (details) {
        unawaited(ref.read(playbackBridgeProvider).swapVideos(details.data, side));
      },
      builder: (context, candidates, _) {
        final over = candidates.isNotEmpty || dropOver;
        final border = over
            ? Border.all(color: AppColors.accent, width: 2)
            : (staticBorder ? Border.all(color: AppColors.lineStrong) : null);
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: border,
            color: over ? AppColors.accent.withValues(alpha: 0.14) : null,
          ),
          child: child,
        );
      },
    );
  }

  Widget _video(PlaybackBridge bridge, Side side) {
    // Sem controlos por player (o rodapé controla todos em conjunto). O
    // overlay de sincronização fica no stage, centrado no painel do vídeo.
    return Video(controller: bridge.sideOf(side).controller, controls: NoVideoControls);
  }

  Widget _dropPane(PlaybackBridge bridge, Side side) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
          color: AppColors.panel,
        ),
        child: _DropZone(
          bridge: bridge,
          side: side,
          highlighted: _highlight == side,
        ),
      ),
    );
  }

  /// Splitters arrastáveis entre células adjacentes (3/4 vídeos): cada segmento
  /// atualiza a fronteira interior (`boundary`) do eixo correspondente. A caixa
  /// de toque fica centrada na linha (antes pendia +9 px para a direita).
  List<Widget> _buildDraggableDividers(
      Map<Side, CellRect> cells, Size size,
      {required bool enabled}) {
    const thickness = 2.0;
    const hitPadding = 9.0;
    // Largura/altura da caixa perpendicular à linha (linha + área de toque).
    final cross = thickness + hitPadding * 2;
    final activeDrag = enabled && (_dragging || _armed);
    return [
      for (final segment in layoutDividers(
          spec: layoutSpec(_lastSplitLayout ?? SplitLayout.sideBySide),
          cells: cells))
        Positioned(
          left: segment.horizontal
              ? segment.start
              : segment.coordinate - cross / 2,
          top: segment.horizontal
              ? segment.coordinate - cross / 2
              : segment.start,
          width: segment.horizontal ? segment.end - segment.start : cross,
          height: segment.horizontal ? cross : segment.end - segment.start,
          child: IgnorePointer(
            ignoring: !enabled,
            child: MouseRegion(
              cursor: enabled
                  ? (segment.horizontal
                      ? SystemMouseCursors.resizeRow
                      : SystemMouseCursors.resizeColumn)
                  : MouseCursor.defer,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => setState(() => _dragging = true),
                onPanUpdate: (details) {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null) return;
                  _updateSplitFromLocal(
                    box.globalToLocal(details.globalPosition),
                    size,
                    segment.horizontal,
                    boundary: segment.boundary,
                  );
                },
                onPanEnd: (_) => setState(() => _dragging = false),
                onDoubleTap: () => _center(
                  horizontal: segment.horizontal,
                  layout: _lastSplitLayout,
                ),
                child: Center(
                  child: Container(
                    width: segment.horizontal ? double.infinity : 2,
                    height: segment.horizontal ? 2 : double.infinity,
                    color: activeDrag
                        ? AppColors.accent
                        : AppColors.lineStrong,
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _buildDivider(bool horizontal, Size size, {required bool enabled}) {
    const thickness = 22.0;
    final splitX = _colSplits.isEmpty
        ? size.width / 2
        : size.width * _colSplits[0] / 100;
    final splitY = _rowSplits.isEmpty
        ? size.height / 2
        : size.height * _rowSplits[0] / 100;
    final active = enabled && (_dragging || _armed);

    final line = Container(
      width: horizontal ? double.infinity : 2,
      height: horizontal ? 2 : double.infinity,
      color: !enabled
          ? AppColors.line
          : (active ? AppColors.accent : AppColors.lineStrong),
    );
    final grip = Container(
      width: horizontal ? 46 : 10,
      height: horizontal ? 10 : 46,
      decoration: BoxDecoration(
        color: enabled ? AppColors.accent : AppColors.lineStrong,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 8),
        ],
      ),
    );

    return Positioned(
      left: horizontal ? 0 : splitX - thickness / 2,
      top: horizontal ? splitY - thickness / 2 : 0,
      right: horizontal ? 0 : null,
      bottom: horizontal ? null : 0,
      width: horizontal ? null : thickness,
      height: horizontal ? thickness : null,
      child: IgnorePointer(
        ignoring: !enabled,
        child: MouseRegion(
          cursor: enabled
              ? (horizontal
                  ? SystemMouseCursors.resizeRow
                  : SystemMouseCursors.resizeColumn)
              : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => setState(() => _dragging = true),
            onPanUpdate: (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              _updateSplitFromLocal(
                  box.globalToLocal(details.globalPosition), size, horizontal);
            },
            onPanEnd: (_) => setState(() => _dragging = false),
            onDoubleTap: () => _center(horizontal: horizontal),
            child: Stack(
              alignment: Alignment.center,
              children: [Center(child: line), Center(child: grip)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cornerLabel(String text) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xB30E1418),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.lineStrong),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: AppFonts.display,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.accent,
        ),
      ),
    );
  }

  /// Resolve o eixo vertical do HUD: o canto vai para o extremo da célula
  /// mais próximo da borda do palco (empate → topo).
  HudVPos _resolveHudV(HudVPos pos, CellRect cell, Size size) {
    if (pos != HudVPos.corner) return pos;
    return cell.top <= size.height - cell.bottom ? HudVPos.top : HudVPos.bottom;
  }

  /// Resolve o eixo horizontal do HUD: o canto vai para o extremo da célula
  /// mais próximo da borda do palco (empate → esquerda).
  HudHPos _resolveHudH(HudHPos pos, CellRect cell, Size size) {
    if (pos != HudHPos.corner) return pos;
    return cell.left <= size.width - cell.right
        ? HudHPos.left
        : HudHPos.right;
  }

  /// Grupos de informação por lado — sempre ancorados na própria célula, com
  /// os eixos vertical e horizontal resolvidos de forma independente (o canto
  /// resolve para o extremo da célula mais próximo da borda do palco; empate
  /// → topo/esquerda). A pill de desync evita os outros overlays (desce e,
  /// se preciso, sobe).
  /// Overlays por célula: pills (FPS/buffer) ou estatísticas completas.
  /// Em wipe o vídeo é layout a ecrã cheio (clipado), por isso a resolução
  /// visualizada usa o tamanho do palco; em grelha usa a célula.
  List<Widget> _buildOverlays(
    PlaybackBridge bridge,
    AppSettings settings,
    Strings strings,
    Size size,
    bool horizontal,
    Map<Side, CellRect> cells,
    List<Side> active, {
    required bool wipeOn,
  }) {
    final showFps = settings.fpsAlways || bridge.frameHudVisible;
    final blockH = settings.statsOverlay ? _statsHeight : _hudHeight;
    final twoVideo = active.length == 2;
    var loadedCount = 0;
    for (final side in active) {
      if (bridge.stateOf(side).loaded) loadedCount++;
    }
    final showDrift = settings.driftMeter && loadedCount >= 2;
    final widgets = <Widget>[];
    final occupied = <Rect>[];
    final dpr = MediaQuery.devicePixelRatioOf(context);

    Widget? groupFor(Side side, CellRect cell) {
      if (!bridge.stateOf(side).loaded) return null;
      if (settings.statsOverlay) {
        return _statsBlock(
          bridge,
          side,
          strings,
          viewBounds: wipeOn ? size : Size(cell.width, cell.height),
          devicePixelRatio: dpr,
        );
      }
      return _sideGroup(bridge, side, strings, settings, showFps: showFps);
    }

    for (final side in active) {
      final cell = cells[side];
      if (cell == null) continue;
      final group = groupFor(side, cell);
      if (group == null) continue;

      final v = _resolveHudV(settings.hudVertical, cell, size);
      final h = _resolveHudH(settings.hudHorizontal, cell, size);
      final xAlign = switch (h) {
        HudHPos.center => 0.0,
        HudHPos.right => 1.0,
        HudHPos.left || HudHPos.corner => -1.0,
      };
      final yAlign = switch (v) {
        HudVPos.center => 0.0,
        HudVPos.bottom => 1.0,
        HudVPos.top || HudVPos.corner => -1.0,
      };

      widgets.add(Positioned(
        left: cell.left,
        top: cell.top,
        width: cell.width,
        height: cell.height,
        child: Padding(
          padding: const EdgeInsets.all(_hudMargin),
          child: Align(
            alignment: Alignment(xAlign, yAlign),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _groupMaxWidth),
              child: group,
            ),
          ),
        ),
      ));

      // Retângulo aproximado do grupo (para a pill de desync desviar).
      final rectW = math.min(_groupMaxWidth, cell.width);
      final rectX = xAlign == 0.0
          ? cell.left + (cell.width - rectW) / 2
          : xAlign > 0
              ? cell.right - _hudMargin - rectW
              : cell.left + _hudMargin;
      final rectY = yAlign == 0.0
          ? cell.top + (cell.height - blockH) / 2
          : yAlign > 0
              ? cell.bottom - _hudMargin - blockH
              : cell.top + _hudMargin;
      occupied.add(Rect.fromLTWH(rectX, rectY, rectW, blockH));
    }

    if (showDrift) {
      final drift = _DriftPill(ms: bridge.driftMs);
      final pos = _avoidDrift(size, occupied, horizontal, cells, twoVideo);
      widgets.add(Positioned(
        left: pos.dx,
        top: pos.dy,
        width: _driftWidth,
        child: Align(alignment: Alignment.center, child: drift),
      ));
    }
    return widgets;
  }

  /// Escolhe uma posição para a pill de desync que não colida com os grupos:
  /// começa na posição preferida e, se preciso, desce e depois sobe.
  Offset _avoidDrift(
    Size size,
    List<Rect> occupied,
    bool horizontal,
    Map<Side, CellRect> cells,
    bool twoVideo,
  ) {
    const step = _driftHeight + _pillGap;
    double baseX;
    double baseY;
    if (twoVideo && !horizontal) {
      final cellA = cells[Side.a];
      final cellB = cells[Side.b];
      final splitX = cellA == null || cellB == null
          ? size.width / 2
          : (cellA.left <= cellB.left ? cellA.right : cellB.right);
      baseX = (splitX - _driftWidth / 2).clamp(0.0, size.width - _driftWidth);
      baseY = (size.height - _driftHeight) / 2;
    } else {
      baseX = (size.width - _driftWidth) / 2;
      baseY = (size.height - _driftHeight) / 2;
    }

    Rect candidateAt(double x, double y) => Rect.fromLTWH(
        x,
        y.clamp(_hudMargin, math.max(_hudMargin, size.height - _hudMargin - _driftHeight)),
        _driftWidth,
        _driftHeight);

    bool free(Rect r) => !occupied.any((o) => o.overlaps(r));

    final base = candidateAt(baseX, baseY);
    if (free(base)) return Offset(base.left, base.top);

    for (var i = 1; i <= 12; i++) {
      final down = candidateAt(baseX, baseY + i * step);
      if (free(down)) return Offset(down.left, down.top);
      final up = candidateAt(baseX, baseY - i * step);
      if (free(up)) return Offset(up.left, up.top);
    }
    return Offset(base.left, base.top);
  }

  /// Grupo de pills de um lado com ordem espelhada: A = FPS → buffer,
  /// B..D = buffer → FPS (o buffer fica junto à divisória no split de 2).
  Widget? _sideGroup(
    PlaybackBridge bridge,
    Side side,
    Strings strings,
    AppSettings settings, {
    required bool showFps,
  }) {
    final fps = showFps ? _sideFramePill(bridge, side, strings) : null;
    final buffer = settings.bufferIndicator
        ? _BufferPill(
            seconds: bridge.bufferSeconds(side),
            bytes: bridge.bufferBytes(side),
            dropped: bridge.droppedFrames(side),
          )
        : null;
    final children = side == Side.a
        ? <Widget>[?fps, ?buffer]
        : <Widget>[?buffer, ?fps];
    if (children.isEmpty) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: _pillGap),
          children[i],
        ],
      ],
    );
  }

  /// Bloco de estatísticas completas de um vídeo (substitui as pills de
  /// FPS + buffer no view): ficheiro, resolução original→visualizada,
  /// codecs/FPS/tamanho do ficheiro, quadro, tempo, buffer/drops e volume.
  ///
  /// A resolução visualizada é o retângulo do vídeo após `BoxFit.contain`
  /// no widget (célula ou palco no wipe), em pixels físicos do ecrã — não
  /// o `dwidth`/`dh` do mpv (que em vídeos 1:1 coincide com a original).
  Widget _statsBlock(
    PlaybackBridge bridge,
    Side side,
    Strings strings, {
    required Size viewBounds,
    required double devicePixelRatio,
  }) {
    final state = bridge.stateOf(side);
    final fps = bridge.fpsOf(side);
    final fpsLabel =
        fps == fps.roundToDouble() ? fps.round().toString() : fps.toStringAsFixed(1);
    final resolution = bridge.videoSize(side)?.replaceFirst('x', '×');
    final viewed = _viewedResolutionLabel(
      bridge,
      side,
      viewBounds: viewBounds,
      devicePixelRatio: devicePixelRatio,
    );
    final videoCodec = bridge.videoCodec(side);
    final audioCodec = bridge.audioCodec(side);
    final buffer = bridge.bufferSeconds(side);
    final bufferMem = bridge.bufferBytes(side);
    final dropped = bridge.droppedFrames(side);
    final fileSize = bridge.fileSize(side);
    final rate = bridge.rateOf(side);
    final displayName = _breakable(state.name ?? '');
    final total = state.duration > 0 ? (state.duration * fps).round() : null;

    String? resLine;
    if (resolution != null && viewed != null && resolution != viewed) {
      resLine = '$resolution → $viewed';
    } else {
      resLine = resolution ?? viewed;
    }

    final tech = <String>[
      ?videoCodec,
      ?audioCodec,
      '$fpsLabel FPS',
      if (fileSize != null) _fmtBytes(fileSize),
    ];
    String? bufferLabel;
    if (buffer >= 0 || bufferMem != null) {
      final parts = <String>[
        if (buffer >= 0) '${buffer.toStringAsFixed(1)} s',
        if (bufferMem case final bytes?) _fmtBufferMb(bytes),
      ];
      bufferLabel = 'buffer ${parts.join(' · ')}';
    }
    final frameParts = <String>[
      ?bufferLabel,
      if (dropped != null) 'drop $dropped',
    ];
    final audio = state.muted
        ? strings.mutedLabel
        : (state.hasAudio ? strings.audioOn : strings.audioNo);

    const mono = TextStyle(fontFamily: AppFonts.mono, fontSize: 11, height: 1.4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xE60E1418),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${side.label} · $displayName',
            softWrap: true,
            style: mono.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600),
          ),
          if (resLine != null)
            Text(resLine, style: mono.copyWith(color: AppColors.text)),
          Text(tech.join(' · '), style: mono.copyWith(color: AppColors.text)),
          if ((rate - 1).abs() > 0.01)
            Text(
              '$fpsLabel → ${(fps * rate).toStringAsFixed(1)} FPS',
              style: mono.copyWith(color: AppColors.accent),
            ),
          Text(
            '${strings.frame} ${bridge.frameNumber(side)}'
            '${total != null ? ' / $total' : ''}',
            style: mono.copyWith(color: AppColors.accent),
          ),
          Text(
            '${formatTime(state.position)} / ${formatTime(state.duration)}',
            style: mono.copyWith(color: AppColors.muted),
          ),
          if (frameParts.isNotEmpty)
            Text(
              frameParts.join(' · '),
              style: mono.copyWith(color: AppColors.teal),
            ),
          Text(
            'vol ${state.volume.round()}% · $audio',
            style: mono.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  /// Resolução on-screen do vídeo (`BoxFit.contain`) em pixels físicos.
  String? _viewedResolutionLabel(
    PlaybackBridge bridge,
    Side side, {
    required Size viewBounds,
    required double devicePixelRatio,
  }) {
    final aspect = _videoAspect(bridge, side);
    if (aspect == null || aspect <= 0) return null;
    if (viewBounds.width <= 0 || viewBounds.height <= 0) return null;

    final boundsAspect = viewBounds.width / viewBounds.height;
    final Size fitted;
    if (aspect > boundsAspect) {
      fitted = Size(viewBounds.width, viewBounds.width / aspect);
    } else {
      fitted = Size(viewBounds.height * aspect, viewBounds.height);
    }

    final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    final w = (fitted.width * dpr).round();
    final h = (fitted.height * dpr).round();
    if (w <= 0 || h <= 0) return null;
    return '$w×$h';
  }

  /// Aspect ratio do vídeo tal como o `FittedBox` o encaixa. Preferência:
  /// texture/`player.state` (já com rotação), depois `displaySize`, depois
  /// resolução nativa com troca manual em 90/270.
  double? _videoAspect(PlaybackBridge bridge, Side side) {
    Size? parse(String? raw) {
      if (raw == null) return null;
      final parts = raw.toLowerCase().split(RegExp(r'[x×]'));
      if (parts.length != 2) return null;
      final w = double.tryParse(parts[0].trim());
      final h = double.tryParse(parts[1].trim());
      if (w == null || h == null || w <= 0 || h <= 0) return null;
      return Size(w, h);
    }

    final rect = bridge.sideOf(side).controller.rect.value;
    if (rect != null && rect.width > 1 && rect.height > 1) {
      return rect.width / rect.height;
    }

    final player = bridge.sideOf(side).player;
    final pw = player.state.width;
    final ph = player.state.height;
    if (pw != null && ph != null && pw > 0 && ph > 0) {
      return pw / ph;
    }

    final display = parse(bridge.displaySize(side));
    if (display != null) return display.width / display.height;

    final native = parse(bridge.videoSize(side));
    if (native == null) return null;
    final rot = bridge.videoRotation(side);
    if (rot == 90 || rot == 270) return native.height / native.width;
    return native.width / native.height;
  }

  /// Toast de áudio dual centrado na célula do(s) vídeo(s) silenciado(s)
  /// pela política (não no footer).
  List<Widget> _buildDualAudioToasts(
    PlaybackBridge bridge,
    Strings strings,
    Map<Side, CellRect> cells,
    List<Side> active,
  ) {
    final sides = bridge.dualAudioToastSides;
    if (sides.isEmpty) return const [];
    final widgets = <Widget>[];
    for (final side in active) {
      if (!sides.contains(side)) continue;
      final cell = cells[side];
      if (cell == null) continue;
      widgets.add(Positioned(
        left: cell.left,
        top: cell.top,
        width: cell.width,
        height: cell.height,
        child: IgnorePointer(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(280, cell.width - 24),
              ),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xF2161D23),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.5)),
                ),
                child: Text(
                  strings.dualAudio,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 12,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
    }
    return widgets;
  }

  /// Spinners de sincronização: um por lado carregado, ao centro da sua
  /// célula (caminho unificado — sem âncora na divisória).
  List<Widget> _buildSyncSpinners(
    PlaybackBridge bridge,
    Strings strings,
    Map<Side, CellRect> cells,
    List<Side> active,
  ) {
    const boxW = 110.0;
    const boxH = 72.0;
    final widgets = <Widget>[];
    for (final side in active) {
      final cell = cells[side];
      if (cell == null || !bridge.stateOf(side).loaded) continue;
      widgets.add(_spinnerAt(
        bridge,
        strings,
        center: Offset(cell.centerX, cell.centerY),
        side: side,
        boxW: boxW,
        boxH: boxH,
      ));
    }
    return widgets;
  }

  /// Alças de arrasto por vídeo (canto superior da célula): largar sobre
  /// outra célula troca as posições dos dois vídeos (alça visível, sem
  /// long-press).
  List<Widget> _buildDragHandles(
    PlaybackBridge bridge,
    Size size,
    Map<Side, CellRect> cells,
    List<Side> active,
  ) {
    if (active.length < 2) return const [];
    final widgets = <Widget>[];
    for (final side in active) {
      final cell = cells[side];
      if (cell == null || !bridge.stateOf(side).loaded) continue;
      widgets.add(Positioned(
        right: size.width - cell.right + _hudMargin,
        top: cell.top + _hudMargin,
        child: _SwapHandle(side: side),
      ));
    }
    return widgets;
  }

  Widget _spinnerAt(
    PlaybackBridge bridge,
    Strings strings, {
    required Offset center,
    required Side side,
    required double boxW,
    required double boxH,
  }) {
    return Positioned(
      left: center.dx - boxW / 2,
      top: center.dy - boxH / 2,
      width: boxW,
      height: boxH,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: bridge.isSideSyncing(side) ? 1 : 0,
          duration: const Duration(milliseconds: 100),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _SyncSpinner(),
              const SizedBox(height: 6),
              Text(
                strings.syncing,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.text,
                  shadows: [
                    Shadow(
                      color: Color(0xF2000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                    Shadow(color: Color(0xBF000000), blurRadius: 2),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sideFramePill(PlaybackBridge bridge, Side side, Strings strings) {
    final fps = bridge.fpsOf(side);
    final fpsLabel =
        fps == fps.roundToDouble() ? fps.round().toString() : fps.toStringAsFixed(1);
    final text =
        '${side.label} · $fpsLabel FPS · ${strings.frame} ${bridge.frameNumber(side)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xE60E1418),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 11,
          color: AppColors.accent,
        ),
      ),
    );
  }

  /// Blink: letra do lado visível + FPS abaixo, na posição escolhida
  /// (centrada em 3/4; em 2 acompanha o lado — lado "primeiro"
  /// (esquerda/topo) à esquerda).
  Widget _buildBlinkLetter(
      PlaybackBridge bridge,
      Side visibleSide,
      BlinkLetterPosition position,
      int viewCount,
      Map<Side, CellRect> cells) {
    final y = switch (position) {
      BlinkLetterPosition.top => -0.82,
      BlinkLetterPosition.center => 0.0,
      BlinkLetterPosition.bottom => 0.82,
    };
    var x = 0.0;
    if (viewCount == 2) {
      final cellA = cells[Side.a];
      final cellB = cells[Side.b];
      final cell = cells[visibleSide];
      if (cellA != null && cellB != null && cell != null) {
        // Primeiro slot: menor left (lado a lado) ou menor top (empilhado).
        final stacked = (cellA.left - cellB.left).abs() < 0.5;
        final first = stacked
            ? (cellA.top <= cellB.top ? Side.a : Side.b)
            : (cellA.left <= cellB.left ? Side.a : Side.b);
        x = visibleSide == first ? -0.5 : 0.5;
      } else {
        x = visibleSide == Side.a ? -0.5 : 0.5;
      }
    }
    final fps = bridge.fpsOf(visibleSide);
    final fpsLabel =
        fps == fps.roundToDouble() ? fps.round().toString() : fps.toStringAsFixed(1);
    return Positioned.fill(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment(x, y),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                visibleSide.label,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 132,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  color: AppColors.accent.withValues(alpha: 0.85),
                  shadows: const [
                    Shadow(
                        color: Color(0xCC000000),
                        blurRadius: 24,
                        offset: Offset(0, 4)),
                  ],
                ),
              ),
              Text(
                '$fpsLabel FPS',
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: AppColors.accent.withValues(alpha: 0.85),
                  shadows: const [
                    Shadow(
                        color: Color(0xCC000000),
                        blurRadius: 16,
                        offset: Offset(0, 2)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Insere oportunidades de quebra (zero-width space) entre caracteres para
/// que nomes longos sem espaços (nomes de ficheiro) quebrem na própria linha
/// em vez de saltarem inteiros para a linha de baixo.
String _breakable(String text) =>
    text.isEmpty ? text : text.split('').join('\u200B');

/// Formata bytes como `x.x GB` / `x.x MB` / `x KB`.
String _fmtBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

/// Buffer em memória: sempre em MB (1 casa decimal).
String _fmtBufferMb(int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 10) return '${mb.round()} MB';
  return '${mb.toStringAsFixed(1)} MB';
}

class _CellClipper extends CustomClipper<Rect> {
  const _CellClipper({required this.cell});

  final CellRect cell;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(cell.left, cell.top, cell.right, cell.bottom);

  @override
  bool shouldReclip(_CellClipper oldClipper) =>
      oldClipper.cell.left != cell.left ||
      oldClipper.cell.top != cell.top ||
      oldClipper.cell.width != cell.width ||
      oldClipper.cell.height != cell.height;
}

/// Alça visível de um vídeo no canto da sua célula: arraste para outra
/// célula para trocar as posições dos dois vídeos. Cursor `move` em hover e
/// `grabbing` enquanto se arrasta (também no feedback que segue o ponteiro).
class _SwapHandle extends StatefulWidget {
  const _SwapHandle({required this.side});

  final Side side;

  @override
  State<_SwapHandle> createState() => _SwapHandleState();
}

class _SwapHandleState extends State<_SwapHandle> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xB30E1418),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.lineStrong),
      ),
      child: const Icon(Icons.drag_indicator, size: 16, color: AppColors.accent),
    );
    return MouseRegion(
      cursor:
          _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.move,
      child: Draggable<Side>(
        data: widget.side,
        onDragStarted: () => setState(() => _dragging = true),
        // `onDragEnd` cobre sucesso e cancelamento (sem alvo).
        onDragEnd: (_) => setState(() => _dragging = false),
        feedback: Material(
          color: Colors.transparent,
          child: MouseRegion(
            cursor: SystemMouseCursors.grabbing,
            child: Opacity(opacity: 0.85, child: box),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: box),
        child: box,
      ),
    );
  }
}

class _DropZone extends ConsumerWidget {
  const _DropZone({
    required this.bridge,
    required this.side,
    required this.highlighted,
  });

  final PlaybackBridge bridge;
  final Side side;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    return Material(
      color: highlighted ? AppColors.accentSoft : AppColors.panel,
      child: InkWell(
        onTap: () => pickFor(ref, bridge, side, strings),
        mouseCursor: SystemMouseCursors.click,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.video_library_outlined, size: 40, color: AppColors.muted),
              const SizedBox(height: 12),
              Text(
                strings.dropTitle,
                style: const TextStyle(fontSize: 13, color: AppColors.text),
              ),
              const SizedBox(height: 6),
              Text(
                strings.dropHint,
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill discreta com buffer (segundos + MB) e drops de um lado.
class _BufferPill extends StatelessWidget {
  const _BufferPill({
    required this.seconds,
    this.bytes,
    this.dropped,
  });

  /// Segundos em cache; negativo = sem dado.
  final double seconds;

  /// Bytes em memória (`null` = desconhecido).
  final int? bytes;

  /// Frames descartados (`null` = desconhecido).
  final int? dropped;

  @override
  Widget build(BuildContext context) {
    final known = seconds >= 0;
    final parts = <String>[
      known ? '${seconds.toStringAsFixed(1)}s' : '—',
      if (bytes != null) _fmtBufferMb(bytes!),
      if (dropped != null) 'drop $dropped',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xE60E1418),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: known
              ? AppColors.teal.withValues(alpha: 0.55)
              : AppColors.lineStrong,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: known ? AppColors.teal : AppColors.muted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'buffer ${parts.join(' · ')}',
            style: TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 10,
              color: known ? AppColors.teal : AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill do medidor de dessincronia entre os lados: rótulo "desync" por cima
/// e o valor por baixo, centrada na zona escolhida do view.
class _DriftPill extends StatelessWidget {
  const _DriftPill({required this.ms});

  final double ms;

  @override
  Widget build(BuildContext context) {
    final abs = ms.abs();
    final label = abs >= 10 ? abs.round().toString() : abs.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xE60E1418),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'desync',
            style: TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 9,
              height: 1.1,
              letterSpacing: 0.4,
              color: AppColors.muted,
            ),
          ),
          Text(
            '$label ms',
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: AppColors.teal,
            ),
          ),
        ],
      ),
    );
  }
}

/// Spinner moderno mostrado no lado que está à espera da sincronização:
/// dois aros em contrarotação (accent) + ponto pulsante sobre fundo escuro.
class _SyncSpinner extends StatefulWidget {
  const _SyncSpinner();

  @override
  State<_SyncSpinner> createState() => _SyncSpinnerState();
}

class _SyncSpinnerState extends State<_SyncSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xB30E1418),
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.lineStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 14,
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) =>
            CustomPaint(painter: _SyncSpinnerPainter(_controller.value)),
      ),
    );
  }
}

class _SyncSpinnerPainter extends CustomPainter {
  const _SyncSpinnerPainter(this.t);

  /// Progresso 0..1 da animação.
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    final outer = Rect.fromCircle(center: center, radius: size.width * 0.36);
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = AppColors.accent;
    canvas.drawArc(outer, t * 2 * math.pi, 1.5, false, outerPaint);

    final inner = Rect.fromCircle(center: center, radius: size.width * 0.22);
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = AppColors.accent.withValues(alpha: 0.55);
    canvas.drawArc(inner, -t * 2 * math.pi * 1.4, 1.2, false, innerPaint);

    final dotPaint = Paint()
      ..color = AppColors.accent
          .withValues(alpha: 0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * 2 * math.pi)));
    canvas.drawCircle(center, 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _SyncSpinnerPainter oldDelegate) =>
      oldDelegate.t != t;
}

/// Overlay do menu de contexto do quadro: fade rápido, dismiss translúcido
/// (permite reabrir noutro quadro no mesmo clique direito) e cabeçalho com
/// letra + nome do ficheiro.
class _FrameContextMenuOverlay extends StatefulWidget {
  const _FrameContextMenuOverlay({
    required this.left,
    required this.top,
    required this.title,
    required this.changeLabel,
    required this.removeLabel,
    required this.rotateLabel,
    required this.muteLabel,
    required this.muteIcon,
    required this.onDismiss,
    required this.onSelect,
  });

  final double left;
  final double top;
  final String title;
  final String changeLabel;
  final String removeLabel;
  final String rotateLabel;
  final String muteLabel;
  final IconData muteIcon;
  final VoidCallback onDismiss;
  final Future<void> Function(String action) onSelect;

  @override
  State<_FrameContextMenuOverlay> createState() =>
      _FrameContextMenuOverlayState();
}

class _FrameContextMenuOverlayState extends State<_FrameContextMenuOverlay>
    with SingleTickerProviderStateMixin {
  static const _fadeMs = 70;
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _fadeMs),
  )..forward();

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => widget.onDismiss(),
          ),
        ),
        Positioned(
          left: widget.left,
          top: widget.top,
          child: FadeTransition(
            opacity: _fade,
            child: Material(
              color: const Color(0xF2161D23),
              elevation: 10,
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.lineStrong),
                      _item(
                        Icons.folder_open_outlined,
                        widget.changeLabel,
                        'change',
                      ),
                      _item(
                        Icons.delete_outline,
                        widget.removeLabel,
                        'remove',
                      ),
                      _item(
                        Icons.rotate_90_degrees_cw_outlined,
                        widget.rotateLabel,
                        'rotate',
                      ),
                      _item(widget.muteIcon, widget.muteLabel, 'mute'),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _item(IconData icon, String label, String action) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: () => unawaited(widget.onSelect(action)),
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 13.5, color: AppColors.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
