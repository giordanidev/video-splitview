/// Modelos de domínio da aplicação.
library;

import 'dart:math' as math;

enum Side {
  a,
  b,
  c,
  d;

  String get id => name;

  /// Etiqueta de apresentação (A / B / C / D).
  String get label => switch (this) {
        Side.a => 'A',
        Side.b => 'B',
        Side.c => 'C',
        Side.d => 'D',
      };

  /// Nome humano do lado, usado no modal de assistência.
  String get human => switch (this) {
        Side.a => 'A (esquerda)',
        Side.b => 'B (direita)',
        Side.c => 'C',
        Side.d => 'D',
      };

  /// Lados ativos para um número de vídeos (1..4), por ordem de leitura.
  static List<Side> forViewCount(int viewCount) =>
      values.take(_clampViewCount(viewCount)).toList(growable: false);

  static Side fromId(String value) => switch (value) {
        'b' || 'right' => Side.b,
        'c' => Side.c,
        'd' => Side.d,
        _ => Side.a,
      };
}

int _clampViewCount(num value) =>
    value.isFinite ? value.round().clamp(1, 4) : 2;

/// Número de vídeos visíveis na view (1..4).
int clampViewCount(num value) => _clampViewCount(value);

/// Como os dois vídeos são apresentados quando o Blink está desligado.
enum SplitMode {
  wipe,
  columns;

  static SplitMode fromId(Object? value) =>
      value == 'columns' ? SplitMode.columns : SplitMode.wipe;
}

/// Layout de divisão da view. Cada layout é válido para um número fixo de
/// vídeos (2, 3 ou 4); o 1 vídeo não tem divisão.
enum SplitLayout {
  // 2 vídeos
  sideBySide,
  stacked,

  // 3 vídeos
  columns3,
  rows3,

  /// `A|B` sobre `C` (C ocupa a base toda).
  topPairBottomSingle,

  /// `A` sobre `B|C` (A ocupa o topo todo).
  topSingleBottomPair,

  /// `A` à esquerda (altura toda) com `B`/`C` empilhados à direita.
  singleLeftPairRight,

  /// `A`/`B` empilhados à esquerda com `C` à direita (altura toda).
  pairLeftSingleRight,

  // 4 vídeos
  columns4,
  rows4,

  /// `A|B` sobre `C|D`.
  grid2x2,
  topTripleBottomSingle,
  topSingleBottomTriple,
  singleLeftTripleRight,
  tripleLeftSingleRight;

  static SplitLayout fromId(Object? value) => switch (value) {
        'sideBySide' || 'vertical' => SplitLayout.sideBySide,
        'stacked' || 'horizontal' => SplitLayout.stacked,
        'columns3' => SplitLayout.columns3,
        'rows3' => SplitLayout.rows3,
        'topPairBottomSingle' => SplitLayout.topPairBottomSingle,
        'topSingleBottomPair' => SplitLayout.topSingleBottomPair,
        'singleLeftPairRight' => SplitLayout.singleLeftPairRight,
        'pairLeftSingleRight' => SplitLayout.pairLeftSingleRight,
        'columns4' => SplitLayout.columns4,
        'rows4' => SplitLayout.rows4,
        'grid2x2' => SplitLayout.grid2x2,
        'topTripleBottomSingle' => SplitLayout.topTripleBottomSingle,
        'topSingleBottomTriple' => SplitLayout.topSingleBottomTriple,
        'singleLeftTripleRight' => SplitLayout.singleLeftTripleRight,
        'tripleLeftSingleRight' => SplitLayout.tripleLeftSingleRight,
        _ => SplitLayout.sideBySide,
      };

  /// Layouts disponíveis para o número de vídeos (ordem de apresentação).
  static List<SplitLayout> forViewCount(int viewCount) => switch (viewCount) {
        1 => const <SplitLayout>[],
        3 => const [
          SplitLayout.columns3,
          SplitLayout.rows3,
          SplitLayout.topPairBottomSingle,
          SplitLayout.topSingleBottomPair,
          SplitLayout.singleLeftPairRight,
          SplitLayout.pairLeftSingleRight,
        ],
        4 => const [
          SplitLayout.grid2x2,
          SplitLayout.columns4,
          SplitLayout.rows4,
          SplitLayout.topTripleBottomSingle,
          SplitLayout.topSingleBottomTriple,
          SplitLayout.singleLeftTripleRight,
          SplitLayout.tripleLeftSingleRight,
        ],
        _ => const [SplitLayout.sideBySide, SplitLayout.stacked],
      };

  /// Layout predefinido para o número de vídeos.
  static SplitLayout defaultFor(int viewCount) => switch (viewCount) {
        3 => SplitLayout.columns3,
        4 => SplitLayout.grid2x2,
        _ => SplitLayout.sideBySide,
      };

  bool supportsViewCount(int viewCount) =>
      SplitLayout.forViewCount(viewCount).contains(this);

  /// Verdadeiro quando o splitter principal é horizontal (células empilhadas).
  bool get isStackedAxis => this == SplitLayout.stacked;
}

/// Posição de uma célula na grelha subjacente ao layout.
class LayoutCell {
  const LayoutCell({
    required this.side,
    this.col = 0,
    this.row = 0,
    this.colSpan = 1,
    this.rowSpan = 1,
  });

  final Side side;
  final int col;
  final int row;
  final int colSpan;
  final int rowSpan;
}

/// Grelha (colunas × linhas) + colocação das células de um layout.
class LayoutSpec {
  const LayoutSpec({required this.cols, required this.rows, required this.cells});

  final int cols;
  final int rows;
  final List<LayoutCell> cells;
}

/// Especificação da grelha de um layout (o eixo do splitter de 2 vídeos é
/// resolvido com a percentagem `_split`, não com divisão igual).
LayoutSpec layoutSpec(SplitLayout layout) => switch (layout) {
      SplitLayout.sideBySide => const LayoutSpec(
          cols: 2,
          rows: 1,
          cells: [
            LayoutCell(side: Side.a, col: 0),
            LayoutCell(side: Side.b, col: 1),
          ],
        ),
      SplitLayout.stacked => const LayoutSpec(
          cols: 1,
          rows: 2,
          cells: [
            LayoutCell(side: Side.a, row: 0),
            LayoutCell(side: Side.b, row: 1),
          ],
        ),
      SplitLayout.columns3 => const LayoutSpec(
          cols: 3,
          rows: 1,
          cells: [
            LayoutCell(side: Side.a, col: 0),
            LayoutCell(side: Side.b, col: 1),
            LayoutCell(side: Side.c, col: 2),
          ],
        ),
      SplitLayout.rows3 => const LayoutSpec(
          cols: 1,
          rows: 3,
          cells: [
            LayoutCell(side: Side.a, row: 0),
            LayoutCell(side: Side.b, row: 1),
            LayoutCell(side: Side.c, row: 2),
          ],
        ),
      SplitLayout.topPairBottomSingle => const LayoutSpec(
          cols: 2,
          rows: 2,
          cells: [
            LayoutCell(side: Side.a, col: 0, row: 0),
            LayoutCell(side: Side.b, col: 1, row: 0),
            LayoutCell(side: Side.c, col: 0, row: 1, colSpan: 2),
          ],
        ),
      SplitLayout.topSingleBottomPair => const LayoutSpec(
          cols: 2,
          rows: 2,
          cells: [
            LayoutCell(side: Side.a, col: 0, row: 0, colSpan: 2),
            LayoutCell(side: Side.b, col: 0, row: 1),
            LayoutCell(side: Side.c, col: 1, row: 1),
          ],
        ),
      SplitLayout.singleLeftPairRight => const LayoutSpec(
          cols: 2,
          rows: 2,
          cells: [
            LayoutCell(side: Side.a, col: 0, row: 0, rowSpan: 2),
            LayoutCell(side: Side.b, col: 1, row: 0),
            LayoutCell(side: Side.c, col: 1, row: 1),
          ],
        ),
      SplitLayout.pairLeftSingleRight => const LayoutSpec(
          cols: 2,
          rows: 2,
          cells: [
            LayoutCell(side: Side.a, col: 0, row: 0),
            LayoutCell(side: Side.b, col: 0, row: 1),
            LayoutCell(side: Side.c, col: 1, row: 0, rowSpan: 2),
          ],
        ),
      SplitLayout.columns4 => const LayoutSpec(
          cols: 4,
          rows: 1,
          cells: [
            LayoutCell(side: Side.a, col: 0),
            LayoutCell(side: Side.b, col: 1),
            LayoutCell(side: Side.c, col: 2),
            LayoutCell(side: Side.d, col: 3),
          ],
        ),
      SplitLayout.rows4 => const LayoutSpec(
          cols: 1,
          rows: 4,
          cells: [
            LayoutCell(side: Side.a, row: 0),
            LayoutCell(side: Side.b, row: 1),
            LayoutCell(side: Side.c, row: 2),
            LayoutCell(side: Side.d, row: 3),
          ],
        ),
      SplitLayout.grid2x2 => const LayoutSpec(
          cols: 2,
          rows: 2,
          cells: [
            LayoutCell(side: Side.a, col: 0, row: 0),
            LayoutCell(side: Side.b, col: 1, row: 0),
            LayoutCell(side: Side.c, col: 0, row: 1),
            LayoutCell(side: Side.d, col: 1, row: 1),
          ],
        ),
      SplitLayout.topTripleBottomSingle => const LayoutSpec(
          cols: 3,
          rows: 2,
          cells: [
            LayoutCell(side: Side.a, col: 0, row: 0),
            LayoutCell(side: Side.b, col: 1, row: 0),
            LayoutCell(side: Side.c, col: 2, row: 0),
            LayoutCell(side: Side.d, col: 0, row: 1, colSpan: 3),
          ],
        ),
      SplitLayout.topSingleBottomTriple => const LayoutSpec(
          cols: 3,
          rows: 2,
          cells: [
            LayoutCell(side: Side.a, col: 0, row: 0, colSpan: 3),
            LayoutCell(side: Side.b, col: 0, row: 1),
            LayoutCell(side: Side.c, col: 1, row: 1),
            LayoutCell(side: Side.d, col: 2, row: 1),
          ],
        ),
      SplitLayout.singleLeftTripleRight => const LayoutSpec(
          cols: 2,
          rows: 3,
          cells: [
            LayoutCell(side: Side.a, col: 0, row: 0, rowSpan: 3),
            LayoutCell(side: Side.b, col: 1, row: 0),
            LayoutCell(side: Side.c, col: 1, row: 1),
            LayoutCell(side: Side.d, col: 1, row: 2),
          ],
        ),
      SplitLayout.tripleLeftSingleRight => const LayoutSpec(
          cols: 2,
          rows: 3,
          cells: [
            LayoutCell(side: Side.a, col: 0, row: 0),
            LayoutCell(side: Side.b, col: 0, row: 1),
            LayoutCell(side: Side.c, col: 0, row: 2),
            LayoutCell(side: Side.d, col: 1, row: 0, rowSpan: 3),
          ],
        ),
    };

/// Percentagem mínima de uma célula num eixo (folga ao arrastar splits).
const double splitMinCellPercent = 8;

/// Splits interiores iguais para `cols` colunas (`cols-1` fronteiras).
List<double> defaultColSplits(int cols) =>
    [for (var i = 1; i < cols; i++) i * 100.0 / cols];

/// Splits interiores iguais para `rows` linhas (`rows-1` fronteiras).
List<double> defaultRowSplits(int rows) =>
    [for (var i = 1; i < rows; i++) i * 100.0 / rows];

/// Clamp de uma frontearra ao arrastar: mantém `splitMinCellPercent` entre
/// vizinhos (ou borda).
double clampSplitValue(double value, {double? min, double? max}) =>
    value.clamp(min ?? splitMinCellPercent, max ?? 100 - splitMinCellPercent)
        .toDouble();

/// Retângulo simples de uma célula (sem dependências de UI).
class CellRect {
  const CellRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  bool contains(double x, double y) =>
      x >= left && x < right && y >= top && y < bottom;
}

/// Resolve os retângulos de cada lado ativo para o tamanho dado.
///
/// 1 vídeo ocupa a área toda. 2+ vídeos usam a grelha do layout com as
/// fronteiras interiores dadas por `colSplits`/`rowSplits` (percentagens,
/// `cols-1`/`rows-1` valores; default igual). `splitPercent` mantém-se como
/// atalho para 2 vídeos quando não há splits explícitos.
///
/// Posição dos vídeos nos quadros: `order` (se fornecido) diz directamente
/// que lado mostra em cada slot *i* (tem prioridade); senão `rotation`
/// (0..n-1) roda os vídeos entre os quadros.
Map<Side, CellRect> resolveLayoutCells({
  required int viewCount,
  required SplitLayout layout,
  required double width,
  required double height,
  double splitPercent = 50,
  List<double>? colSplits,
  List<double>? rowSplits,
  int rotation = 0,
  List<Side>? order,
}) {
  final count = clampViewCount(viewCount);
  if (count <= 1) {
    return {
      Side.a: CellRect(left: 0, top: 0, width: width, height: height),
    };
  }
  final effective =
      layout.supportsViewCount(count) ? layout : SplitLayout.defaultFor(count);
  final spec = layoutSpec(effective);

  var effCol = colSplits;
  var effRow = rowSplits;
  if (effCol == null && effRow == null) {
    if (count == 2 && effective == SplitLayout.stacked) {
      effRow = [splitPercent];
    } else if (count == 2) {
      effCol = [splitPercent];
    } else {
      effCol = defaultColSplits(spec.cols);
      effRow = defaultRowSplits(spec.rows);
    }
  }
  // Normaliza tamanhos ao spec (faltantes → igual; extra → ignorados).
  effCol = _fitSplits(effCol ?? const [], spec.cols - 1);
  effRow = _fitSplits(effRow ?? const [], spec.rows - 1);

  final colB = <double>[0, ...effCol, 100];
  final rowB = <double>[0, ...effRow, 100];
  final bySide = <Side, CellRect>{
    for (final cell in spec.cells)
      cell.side: CellRect(
        left: colB[cell.col] / 100 * width,
        top: rowB[cell.row] / 100 * height,
        width: (colB[cell.col + cell.colSpan] - colB[cell.col]) / 100 * width,
        height:
            (rowB[cell.row + cell.rowSpan] - rowB[cell.row]) / 100 * height,
      ),
  };

  final active = Side.forViewCount(count);
  if (order != null) {
    final effective = fitFrameOrder(order, active);
    return {
      for (var i = 0; i < count; i++) effective[i]: bySide[active[i]]!,
    };
  }
  final rot = rotation % count;
  if (rot == 0) return bySide;
  // Rotação: o slot i passa a mostrar o lado ativo (i + rot) % n.
  return {
    for (var i = 0; i < count; i++)
      active[(i + rot) % count]: bySide[active[i]]!,
  };
}

/// Normaliza uma ordem de quadros aos lados ativos: mantém a ordem dada
/// (só lados válidos e uma única vez) e completa o que faltar por ordem.
List<Side> fitFrameOrder(List<Side> order, List<Side> active) {
  final result = <Side>[];
  for (final side in order) {
    if (active.contains(side) && !result.contains(side)) result.add(side);
  }
  for (final side in active) {
    if (!result.contains(side)) result.add(side);
  }
  return result;
}

List<double> _fitSplits(List<double> splits, int expected) {
  if (expected <= 0) return const [];
  final result = <double>[];
  for (var i = 0; i < expected; i++) {
    result.add(i < splits.length && splits[i].isFinite
        ? splits[i].clamp(0.0, 100.0)
        : (i + 1) * 100.0 / (expected + 1));
  }
  // Garante ordem crescente (evita células negativas com dados corrompidos).
  for (var i = 1; i < result.length; i++) {
    if (result[i] <= result[i - 1]) result[i] = result[i - 1];
  }
  return result;
}

/// Segmento de splitter entre duas células adjacentes.
class DividerSegment {
  const DividerSegment({
    required this.horizontal,
    required this.coordinate,
    required this.start,
    required this.end,
    required this.boundary,
  });

  /// `true` = linha horizontal (varia em x); `false` = vertical (varia em y).
  final bool horizontal;
  final double coordinate;
  final double start;
  final double end;

  /// Índice da fronteira interior (1..cols-1 para vertical → `colSplits[
  /// boundary-1]`; 1..rows-1 para horizontal → `rowSplits[boundary-1]`).
  final int boundary;
}

/// Splitters entre células adjacentes, com o índice da fronteira que cada
/// segmento controla (para drag em 2-4 vídeos; a geometria vem das cells
/// já resolvidas com os splits atuais).
List<DividerSegment> layoutDividers({
  required LayoutSpec spec,
  required Map<Side, CellRect> cells,
}) {
  const eps = 0.75;
  final segments = <DividerSegment>[];

  for (var i = 0; i < spec.cells.length; i++) {
    for (var j = i + 1; j < spec.cells.length; j++) {
      final ca = spec.cells[i];
      final cb = spec.cells[j];
      final ra = cells[ca.side];
      final rb = cells[cb.side];
      if (ra == null || rb == null) continue;

      final rowsOverlap =
          ca.row < cb.row + cb.rowSpan && cb.row < ca.row + ca.rowSpan;
      final colsOverlap =
          ca.col < cb.col + cb.colSpan && cb.col < ca.col + ca.colSpan;

      // Vertical: colunas justapostas com sobreposição de linhas.
      if (rowsOverlap) {
        if (ca.col + ca.colSpan == cb.col && (ra.right - rb.left).abs() < eps) {
          _addSegment(segments,
              horizontal: false,
              coordinate: ra.right,
              start: math.max(ra.top, rb.top),
              end: math.min(ra.bottom, rb.bottom),
              boundary: cb.col);
        } else if (cb.col + cb.colSpan == ca.col &&
            (rb.right - ra.left).abs() < eps) {
          _addSegment(segments,
              horizontal: false,
              coordinate: rb.right,
              start: math.max(ra.top, rb.top),
              end: math.min(ra.bottom, rb.bottom),
              boundary: ca.col);
        }
      }

      // Horizontal: linhas justapostas com sobreposição de colunas.
      if (colsOverlap) {
        if (ca.row + ca.rowSpan == cb.row && (ra.bottom - rb.top).abs() < eps) {
          _addSegment(segments,
              horizontal: true,
              coordinate: ra.bottom,
              start: math.max(ra.left, rb.left),
              end: math.min(ra.right, rb.right),
              boundary: cb.row);
        } else if (cb.row + cb.rowSpan == ca.row &&
            (rb.bottom - ra.top).abs() < eps) {
          _addSegment(segments,
              horizontal: true,
              coordinate: rb.bottom,
              start: math.max(ra.left, rb.left),
              end: math.min(ra.right, rb.right),
              boundary: ca.row);
        }
      }
    }
  }
  return segments;
}

void _addSegment(
  List<DividerSegment> segments, {
  required bool horizontal,
  required double coordinate,
  required double start,
  required double end,
  required int boundary,
}) {
  if (end - start > 0.75) {
    segments.add(DividerSegment(
      horizontal: horizontal,
      coordinate: coordinate,
      start: start,
      end: end,
      boundary: boundary,
    ));
  }
}

/// Modo efetivo enviado à apresentação (Blink tem prioridade sobre o split).
enum ViewMode { wipe, columns, blink }

/// Posição vertical das letras A/B durante o Blink.
enum BlinkLetterPosition {
  top,
  center,
  bottom;

  static BlinkLetterPosition fromId(Object? value) => switch (value) {
        'top' => BlinkLetterPosition.top,
        'bottom' => BlinkLetterPosition.bottom,
        _ => BlinkLetterPosition.center,
      };
}

/// Eixo vertical da posição das informações sobrepostas (relativo à célula).
enum HudVPos {
  top,
  center,
  bottom,

  /// Canto: resolve para o extremo mais próximo da borda do palco.
  corner;

  static HudVPos fromId(Object? value) => switch (value) {
        'center' => HudVPos.center,
        'bottom' => HudVPos.bottom,
        'corner' => HudVPos.corner,
        _ => HudVPos.top,
      };
}

/// Eixo horizontal da posição das informações sobrepostas (relativo à célula).
enum HudHPos {
  left,
  center,
  right,

  /// Canto: resolve para o extremo mais próximo da borda do palco.
  corner;

  static HudHPos fromId(Object? value) => switch (value) {
        'center' => HudHPos.center,
        'right' => HudHPos.right,
        'corner' => HudHPos.corner,
        _ => HudHPos.left,
      };
}

/// Filtro de escala do `vo=gpu` (`--scale`).
enum Scaler {
  bilinear,
  bicubic,
  lanczos;

  static Scaler fromId(Object? value) => switch (value) {
        'bilinear' => Scaler.bilinear,
        'lanczos' => Scaler.lanczos,
        _ => Scaler.bicubic,
      };
}

/// Modo de sincronização de vídeo do mpv (`--video-sync`).
enum VideoSyncMode {
  audio,
  displayResample,
  desync;

  String get mpvValue => switch (this) {
        VideoSyncMode.audio => 'audio',
        VideoSyncMode.displayResample => 'display-resample',
        VideoSyncMode.desync => 'desync',
      };

  static VideoSyncMode fromId(Object? value) => switch (value) {
        'display-resample' => VideoSyncMode.displayResample,
        'desync' => VideoSyncMode.desync,
        _ => VideoSyncMode.audio,
      };
}

/// Perfil de buffer do demuxer (`--demuxer-max-bytes`).
enum BufferProfile {
  small,
  normal,
  large;

  String get mpvMaxBytes => switch (this) {
        BufferProfile.small => '${64 * 1024 * 1024}',
        BufferProfile.normal => '${150 * 1024 * 1024}',
        BufferProfile.large => '${512 * 1024 * 1024}',
      };

  static BufferProfile fromId(Object? value) => switch (value) {
        'small' => BufferProfile.small,
        'large' => BufferProfile.large,
        _ => BufferProfile.normal,
      };
}

/// Descodificação por hardware.
///
/// Nota: no Windows o `media_kit` só suporta modos de *copy-back*. O modo
/// `direct` existe no modelo para preservar a UI, mas é aplicado como
/// `auto-copy` (ver `playback_bridge.dart`).
enum HardwareDecode {
  off,
  compat,
  direct;

  static HardwareDecode fromId(Object? value, {Object? legacy}) => switch (value) {
        'off' => HardwareDecode.off,
        'compat' => HardwareDecode.compat,
        'direct' => HardwareDecode.direct,
        _ => legacy == false ? HardwareDecode.off : HardwareDecode.compat,
      };
}

/// Estado observável de um lado do player.
class PlayerState {
  const PlayerState({
    this.loaded = false,
    this.path,
    this.name,
    this.duration = 0,
    this.position = 0,
    this.paused = true,
    this.volume = 100,
    this.muted = false,
    this.error,
    this.hasAudio = false,
    this.ended = false,
  });

  final bool loaded;
  final String? path;
  final String? name;
  final double duration;
  final double position;
  final bool paused;
  final double volume;
  final bool muted;
  final String? error;

  /// Verdadeiro quando o ficheiro tem faixa de áudio (`aid` != `no`).
  final bool hasAudio;

  /// Verdadeiro após EOF (`completed` / pos ≈ duração).
  final bool ended;

  PlayerState copyWith({
    bool? loaded,
    Object? path = _sentinel,
    Object? name = _sentinel,
    double? duration,
    double? position,
    bool? paused,
    double? volume,
    bool? muted,
    Object? error = _sentinel,
    bool? hasAudio,
    bool? ended,
  }) {
    return PlayerState(
      loaded: loaded ?? this.loaded,
      path: path == _sentinel ? this.path : path as String?,
      name: name == _sentinel ? this.name : name as String?,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      paused: paused ?? this.paused,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      error: error == _sentinel ? this.error : error as String?,
      hasAudio: hasAudio ?? this.hasAudio,
      ended: ended ?? this.ended,
    );
  }
}

const Object _sentinel = Object();

/// Retângulo do stage físico (px CSS + escala de DPI).
class StageLayout {
  const StageLayout({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.scale,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double scale;
}

/// Informação sobre o motor de vídeo (libmpv via media_kit).
class EngineInfo {
  const EngineInfo({
    required this.found,
    required this.ok,
    required this.bundled,
    this.path,
    this.version,
    required this.message,
  });

  final bool found;
  final bool ok;
  final bool bundled;
  final String? path;
  final String? version;
  final String message;
}
