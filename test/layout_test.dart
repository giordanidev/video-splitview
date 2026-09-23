import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:video_splitview/backend/models/models.dart';
import 'package:video_splitview/backend/state/settings.dart';

const _width = 1200.0;
const _height = 800.0;

double _overlapArea(CellRect a, CellRect b) {
  final w = math.min(a.right, b.right) - math.max(a.left, b.left);
  final h = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  return w > 0 && h > 0 ? w * h : 0;
}

void main() {
  test('resolveLayoutCells: 1 vídeo ocupa a área toda', () {
    final cells = resolveLayoutCells(
      viewCount: 1,
      layout: SplitLayout.sideBySide,
      width: _width,
      height: _height,
    );
    expect(cells.keys, [Side.a]);
    final rect = cells[Side.a]!;
    expect(rect.left, 0);
    expect(rect.top, 0);
    expect(rect.width, _width);
    expect(rect.height, _height);
  });

  test('resolveLayoutCells: 2 vídeos respeitam splitPercent', () {
    final cells = resolveLayoutCells(
      viewCount: 2,
      layout: SplitLayout.sideBySide,
      width: _width,
      height: _height,
      splitPercent: 30,
    );
    expect(cells[Side.a]!.width, closeTo(_width * 0.3, 0.001));
    expect(cells[Side.b]!.left, closeTo(_width * 0.3, 0.001));

    final stacked = resolveLayoutCells(
      viewCount: 2,
      layout: SplitLayout.stacked,
      width: _width,
      height: _height,
      splitPercent: 25,
    );
    expect(stacked[Side.a]!.height, closeTo(_height * 0.25, 0.001));
    expect(stacked[Side.b]!.top, closeTo(_height * 0.25, 0.001));
  });

  test('resolveLayoutCells: cada layout cobre a área sem sobreposição', () {
    for (final count in const [2, 3, 4]) {
      for (final layout in SplitLayout.forViewCount(count)) {
        final cells = resolveLayoutCells(
          viewCount: count,
          layout: layout,
          width: _width,
          height: _height,
          splitPercent: 50,
        );
        expect(cells.length, count, reason: '$layout ($count vídeos)');

        final rects = cells.values.toList(growable: false);
        final total = rects.fold<double>(0, (sum, r) => sum + r.width * r.height);
        expect(total, closeTo(_width * _height, 0.01), reason: 'área $layout');

        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            expect(
              _overlapArea(rects[i], rects[j]),
              0,
              reason: 'sobreposição ${layout.name} ${i}x$j',
            );
          }
        }
      }
    }
  });

  test('resolveLayoutCells: layout incompatível cai no default do contador', () {
    final cells = resolveLayoutCells(
      viewCount: 4,
      layout: SplitLayout.columns3,
      width: _width,
      height: _height,
    );
    final expected = resolveLayoutCells(
      viewCount: 4,
      layout: SplitLayout.defaultFor(4),
      width: _width,
      height: _height,
    );
    expect(cells.keys, expected.keys);
    for (final side in cells.keys) {
      expect(cells[side]!.left, expected[side]!.left);
      expect(cells[side]!.top, expected[side]!.top);
      expect(cells[side]!.width, expected[side]!.width);
      expect(cells[side]!.height, expected[side]!.height);
    }
  });

  test('layoutDividers: columns3 tem 2 divisórias verticais', () {
    final layout = SplitLayout.columns3;
    final cells = resolveLayoutCells(
      viewCount: 3,
      layout: layout,
      width: _width,
      height: _height,
    );
    final dividers = layoutDividers(spec: layoutSpec(layout), cells: cells);
    expect(dividers.length, 2);
    expect(dividers.every((d) => !d.horizontal), isTrue);
    expect(dividers[0].coordinate, closeTo(_width / 3, 0.001));
    expect(dividers[1].coordinate, closeTo(_width * 2 / 3, 0.001));
    expect(dividers.map((d) => d.boundary).toSet(), {1, 2});
  });

  test('layoutDividers: grid2x2 tem cruz (2+2 segmentos)', () {
    final layout = SplitLayout.grid2x2;
    final cells = resolveLayoutCells(
      viewCount: 4,
      layout: layout,
      width: _width,
      height: _height,
    );
    final dividers = layoutDividers(spec: layoutSpec(layout), cells: cells);
    expect(dividers.where((d) => !d.horizontal).length, 2);
    expect(dividers.where((d) => d.horizontal).length, 2);
    expect(dividers.where((d) => !d.horizontal).every((d) => d.boundary == 1),
        isTrue);
    expect(dividers.where((d) => d.horizontal).every((d) => d.boundary == 1),
        isTrue);
  });

  test('migração: orientation antiga vira layout', () {
    final horizontal =
        AppSettings.fromMap(const {'orientation': 'horizontal'});
    expect(horizontal.layout, SplitLayout.stacked);
    expect(horizontal.effectiveLayout, SplitLayout.stacked);

    final vertical = AppSettings.fromMap(const {'orientation': 'vertical'});
    expect(vertical.layout, SplitLayout.sideBySide);
    expect(vertical.effectiveLayout, SplitLayout.sideBySide);
  });

  test('SplitLayout.fromId migra chaves legadas', () {
    expect(SplitLayout.fromId('vertical'), SplitLayout.sideBySide);
    expect(SplitLayout.fromId('horizontal'), SplitLayout.stacked);
    expect(SplitLayout.fromId('grid2x2'), SplitLayout.grid2x2);
    expect(SplitLayout.fromId('desconhecido'), SplitLayout.sideBySide);
  });

  test('withViewCount ajusta layouts incompatíveis', () {
    var settings = const AppSettings(viewCount: 3, layout: SplitLayout.columns3);
    settings = settings.withViewCount(4);
    expect(settings.viewCount, 4);
    expect(settings.layout, SplitLayout.grid2x2);

    settings = settings.withViewCount(4).withViewCount(1);
    expect(settings.effectiveViewCount, 1);
    expect(settings.withViewCount(9).effectiveViewCount, 4);
    expect(settings.withViewCount(0).effectiveViewCount, 1);
  });

  test('withLayout ignora layouts de outro contador', () {
    const settings = AppSettings(viewCount: 2);
    final next = settings.withLayout(SplitLayout.grid2x2);
    expect(next.layout, SplitLayout.sideBySide);
    expect(next.withLayout(SplitLayout.stacked).layout, SplitLayout.stacked);
  });

  test('effectiveViewMode: wipe existe para ≥2 vídeos', () {
    expect(
      const AppSettings(viewCount: 2, splitMode: SplitMode.wipe).effectiveViewMode,
      ViewMode.wipe,
    );
    expect(
      const AppSettings(viewCount: 3, splitMode: SplitMode.wipe).effectiveViewMode,
      ViewMode.wipe,
    );
    expect(
      const AppSettings(viewCount: 4, splitMode: SplitMode.wipe).effectiveViewMode,
      ViewMode.wipe,
    );
    expect(
      const AppSettings(viewCount: 1, splitMode: SplitMode.wipe).effectiveViewMode,
      ViewMode.columns,
    );
    expect(
      const AppSettings(viewCount: 2, blinkEnabled: true).effectiveViewMode,
      ViewMode.blink,
    );
  });

  test('resolveLayoutCells: colSplits/rowSplits respeitados', () {
    // grid2x2: 1 fronteira de coluna (cols-1=1) e 1 de linha.
    final cells = resolveLayoutCells(
      viewCount: 4,
      layout: SplitLayout.grid2x2,
      width: _width,
      height: _height,
      colSplits: const [30],
      rowSplits: const [40],
    );
    expect(cells[Side.a]!.width, closeTo(_width * 0.3, 0.001));
    expect(cells[Side.b]!.left, closeTo(_width * 0.3, 0.001));
    expect(cells[Side.b]!.width, closeTo(_width * 0.7, 0.001));
    expect(cells[Side.c]!.top, closeTo(_height * 0.4, 0.001));
    expect(cells[Side.c]!.height, closeTo(_height * 0.6, 0.001));
    expect(cells[Side.a]!.height, closeTo(_height * 0.4, 0.001));

    // columns3: 2 fronteiras de coluna.
    final cols3 = resolveLayoutCells(
      viewCount: 3,
      layout: SplitLayout.columns3,
      width: _width,
      height: _height,
      colSplits: const [20, 70],
    );
    expect(cols3[Side.a]!.width, closeTo(_width * 0.2, 0.001));
    expect(cols3[Side.b]!.left, closeTo(_width * 0.2, 0.001));
    expect(cols3[Side.b]!.width, closeTo(_width * 0.5, 0.001));
    expect(cols3[Side.c]!.left, closeTo(_width * 0.7, 0.001));
    expect(cols3[Side.c]!.width, closeTo(_width * 0.3, 0.001));
  });

  test('resolveLayoutCells: rotation roda lados entre slots', () {
    final base = resolveLayoutCells(
      viewCount: 3,
      layout: SplitLayout.columns3,
      width: _width,
      height: _height,
      rotation: 0,
    );
    final rotated = resolveLayoutCells(
      viewCount: 3,
      layout: SplitLayout.columns3,
      width: _width,
      height: _height,
      rotation: 1,
    );
    // Sem rotação: A no slot0, B slot1, C slot2.
    expect(base[Side.a]!.left, 0);
    // Com rotation=1: slot i mostra active[(i+1)%3] → slot0=b, slot1=c, slot2=a.
    expect(rotated[Side.b]!.left, 0);
    expect(rotated[Side.a]!.left, closeTo(_width * 2 / 3, 0.001));

    // Cobertura e sem sobreposição mantêm-se em qualquer rotação.
    for (final rot in const [0, 1, 2, 3, 4, 5]) {
      final cells = resolveLayoutCells(
        viewCount: 3,
        layout: SplitLayout.columns3,
        width: _width,
        height: _height,
        rotation: rot,
      );
      expect(cells.length, 3);
      final rects = cells.values.toList(growable: false);
      final total =
          rects.fold<double>(0, (sum, r) => sum + r.width * r.height);
      expect(total, closeTo(_width * _height, 0.01));
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(_overlapArea(rects[i], rects[j]), 0);
        }
      }
      // Cada lado aparece exatamente 1×.
      expect(cells.keys.toSet(), {Side.a, Side.b, Side.c});
    }
  });

  test('viewRotation: default 0, withViewCount reset, roundtrip', () {
    const defaults = AppSettings();
    expect(defaults.viewRotation, 0);

    var s = defaults.copyWith(viewRotation: 2);
    expect(s.viewRotation, 2);
    s = s.withViewCount(3);
    expect(s.viewRotation, 0);

    final map = defaults.copyWith(viewRotation: 1).toMap();
    expect(AppSettings.fromMap(map).viewRotation, 1);

    // Clamp: valor fora de faixa é aceite mas effectiveRotation faz % n.
    final big = AppSettings.fromMap({'viewRotation': 7, 'viewCount': 3});
    expect(big.viewRotation, 7);
    expect(big.effectiveRotation, 1);
  });

  test('resolveLayoutCells: order tem prioridade sobre rotation', () {
    final cells = resolveLayoutCells(
      viewCount: 3,
      layout: SplitLayout.columns3,
      width: _width,
      height: _height,
      rotation: 1,
      order: const [Side.c, Side.a, Side.b],
    );
    expect(cells[Side.c]!.left, 0);
    expect(cells[Side.a]!.left, closeTo(_width / 3, 0.001));
    expect(cells[Side.b]!.left, closeTo(_width * 2 / 3, 0.001));
  });

  test('fitFrameOrder: mantém a ordem dada e completa o que falta', () {
    expect(fitFrameOrder(const [Side.b, Side.b, Side.d], Side.forViewCount(3)),
        [Side.b, Side.a, Side.c]);
    expect(fitFrameOrder(const [], Side.forViewCount(2)), [Side.a, Side.b]);
  });

  test('withSwappedFrames troca a ordem base; a rotação compõe por cima', () {
    var s = const AppSettings(viewCount: 2).withSwappedFrames(Side.a, Side.b);
    expect(s.frameOrder, ['b', 'a']);
    expect(s.effectiveFrameOrder, [Side.b, Side.a]);

    // Rotação +1 sobre a base [b,a]: slot0 = base[1] = a, slot1 = base[0] = b.
    s = s.copyWith(viewRotation: 1);
    expect(s.effectiveFrameOrder, [Side.a, Side.b]);

    // Troca de um lado inativo é ignorada.
    expect(const AppSettings(viewCount: 2)
        .withSwappedFrames(Side.a, Side.c)
        .frameOrder,
        isEmpty);

    // Mudar o contador repõe a ordem.
    expect(s.withViewCount(3).frameOrder, isEmpty);
    expect(s.withViewCount(3).effectiveFrameOrder, [Side.a, Side.b, Side.c]);
  });

  test('frameOrder roundtrip em toMap/fromMap', () {
    const s = AppSettings(frameOrder: ['c', 'a', 'b', 'd']);
    expect(AppSettings.fromMap(s.toMap()).frameOrder, ['c', 'a', 'b', 'd']);
  });

  test('blink default é 1000 ms (igual ao máximo)', () {
    expect(blinkDefaultMs, blinkMaxMs);
    expect(const AppSettings().blinkIntervalMs, blinkDefaultMs);
    expect(AppSettings.fromMap(const {}).blinkIntervalMs, blinkDefaultMs);
  });

  test('migração: hudPosition antigo vira eixos (default topo/meio)', () {
    AppSettings withLegacy(String id) =>
        AppSettings.fromMap({'hudPosition': id});

    expect(withLegacy('top').hudVertical, HudVPos.top);
    expect(withLegacy('top').hudHorizontal, HudHPos.center);

    expect(withLegacy('bottom').hudVertical, HudVPos.bottom);
    expect(withLegacy('bottom').hudHorizontal, HudHPos.center);

    expect(withLegacy('center').hudVertical, HudVPos.center);
    expect(withLegacy('center').hudHorizontal, HudHPos.center);

    expect(withLegacy('topCorner').hudVertical, HudVPos.top);
    expect(withLegacy('topCorner').hudHorizontal, HudHPos.corner);

    expect(withLegacy('bottomCorner').hudVertical, HudVPos.bottom);
    expect(withLegacy('bottomCorner').hudHorizontal, HudHPos.corner);

    // Defaults e roundtrip dos novos campos.
    const fresh = AppSettings();
    expect(fresh.hudVertical, HudVPos.top);
    expect(fresh.hudHorizontal, HudHPos.center);
    const custom =
        AppSettings(hudVertical: HudVPos.bottom, hudHorizontal: HudHPos.right);
    final restored = AppSettings.fromMap(custom.toMap());
    expect(restored.hudVertical, HudVPos.bottom);
    expect(restored.hudHorizontal, HudHPos.right);
  });
}
