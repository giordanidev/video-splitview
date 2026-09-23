/// Captura da comparação para PNG (ficheiro ou área de transferência).
///
/// Usa `Player.screenshot()` de cada lado e compõe a imagem em Dart, porque os
/// vídeos são texturas de plataforma (o `RepaintBoundary` não as capturaria).
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/painting.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../models/models.dart';
import '../services/playback_bridge.dart';
import '../state/settings.dart';

Future<ui.Image?> _screenshot(Side side, PlaybackBridge bridge) async {
  if (!bridge.stateOf(side).loaded) return null;
  try {
    final bytes = await bridge.sideOf(side).player.screenshot();
    if (bytes == null) return null;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (_) {
    return null;
  }
}

Rect _containedRect(ui.Image image, Size target) {
  final imageAspect = image.width / image.height;
  final targetAspect = target.width / target.height;
  double width;
  double height;
  if (imageAspect > targetAspect) {
    width = target.width;
    height = width / imageAspect;
  } else {
    height = target.height;
    width = height * imageAspect;
  }
  return Rect.fromLTWH(
    (target.width - width) / 2,
    (target.height - height) / 2,
    width,
    height,
  );
}

Future<Uint8List?> _compose(PlaybackBridge bridge, AppSettings settings) async {
  final viewCount = settings.effectiveViewCount;
  final active = Side.forViewCount(viewCount);
  final available = <Side, ui.Image>{};
  for (final side in active) {
    final image = await _screenshot(side, bridge);
    if (image != null) available[side] = image;
  }
  if (available.isEmpty) return null;

  // Só um lado carregado: desenha-o a tamanho natural (inalterado).
  if (available.length == 1) {
    final only = available.values.first;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      only,
      Rect.fromLTWH(0, 0, only.width.toDouble(), only.height.toDouble()),
      Rect.fromLTWH(0, 0, only.width.toDouble(), only.height.toDouble()),
      Paint(),
    );
    return _encode(recorder, Size(only.width.toDouble(), only.height.toDouble()));
  }

  final horizontal = settings.effectiveLayout == SplitLayout.stacked;
  final mode = settings.effectiveViewMode;
  final activeSides = Side.forViewCount(viewCount);

  // Quadros fixos: o slot i é always activeSides[i] (conteúdo já foi
  // trocado nos players — não remapeamos geometria).
  Side sideAtSlot(int slot) {
    if (slot < 0 || slot >= activeSides.length) return Side.a;
    return activeSides[slot];
  }

  // Blink: só o lado visível (aproximado — usa o primeiro slot).
  if (mode == ViewMode.blink) {
    final image = available[sideAtSlot(0)] ?? available.values.first;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Paint(),
    );
    return _encode(
        recorder, Size(image.width.toDouble(), image.height.toDouble()));
  }

  // Wipe (N≥2): cada imagem contained no output, clipada à sua célula.
  if (mode == ViewMode.wipe && viewCount >= 2) {
    var outW = 0.0;
    var outH = 0.0;
    for (final image in available.values) {
      outW = math.max(outW, image.width.toDouble());
      outH = math.max(outH, image.height.toDouble());
    }
    final output = Size(outW, outH);
    final cells = resolveLayoutCells(
      viewCount: viewCount,
      layout: settings.effectiveLayout,
      width: output.width,
      height: output.height,
    );
    final recorder = ui.PictureRecorder();
    final canvas =
        Canvas(recorder, Rect.fromLTWH(0, 0, output.width, output.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, output.width, output.height),
      Paint()..color = const Color(0xFF090C0F),
    );
    final paint = Paint();
    for (final side in active) {
      final image = available[side];
      final cell = cells[side];
      if (image == null || cell == null) continue;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(
          cell.left, cell.top, cell.width, cell.height));
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        _containedRect(image, output),
        paint,
      );
      canvas.restore();
    }
    return _encode(recorder, output);
  }

  // 2 vídeos: composição clássica natural (colunas/empilhado), com rotação.
  if (viewCount <= 2) {
    final first = available[sideAtSlot(0)] ?? available.values.first;
    final second = available[sideAtSlot(1)] ?? available.values.last;
    final Size output = switch (mode) {
      ViewMode.columns => horizontal
          ? Size(
              math.max(first.width, second.width).toDouble(),
              (first.height + second.height).toDouble(),
            )
          : Size(
              (first.width + second.width).toDouble(),
              math.max(first.height, second.height).toDouble(),
            ),
      _ => Size(
          math.max(first.width, second.width).toDouble(),
          math.max(first.height, second.height).toDouble(),
        ),
    };

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, output.width, output.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, output.width, output.height),
      Paint()..color = const Color(0xFF090C0F),
    );

    final paint = Paint();
    if (mode == ViewMode.columns) {
      if (horizontal) {
        canvas.drawImageRect(
          first,
          Rect.fromLTWH(0, 0, first.width.toDouble(), first.height.toDouble()),
          _containedRect(first, Size(output.width, first.height.toDouble())),
          paint,
        );
        final secondRect = _containedRect(
          second,
          Size(output.width, second.height.toDouble()),
        ).shift(Offset(0, first.height.toDouble()));
        canvas.drawImageRect(
          second,
          Rect.fromLTWH(
              0, 0, second.width.toDouble(), second.height.toDouble()),
          secondRect,
          paint,
        );
      } else {
        canvas.drawImageRect(
          first,
          Rect.fromLTWH(0, 0, first.width.toDouble(), first.height.toDouble()),
          _containedRect(first, Size(first.width.toDouble(), output.height)),
          paint,
        );
        final secondRect = _containedRect(
          second,
          Size(second.width.toDouble(), output.height),
        ).shift(Offset(first.width.toDouble(), 0));
        canvas.drawImageRect(
          second,
          Rect.fromLTWH(
              0, 0, second.width.toDouble(), second.height.toDouble()),
          secondRect,
          paint,
        );
      }
    } else {
      // Fallback wipe 2 vídeos (sem células explícitas acima): metades.
      canvas.drawImageRect(
        first,
        Rect.fromLTWH(0, 0, first.width.toDouble(), first.height.toDouble()),
        _containedRect(first, output),
        paint,
      );
      canvas.save();
      if (horizontal) {
        canvas.clipRect(
            Rect.fromLTWH(0, output.height / 2, output.width, output.height / 2));
      } else {
        canvas.clipRect(
            Rect.fromLTWH(output.width / 2, 0, output.width / 2, output.height));
      }
      canvas.drawImageRect(
        second,
        Rect.fromLTWH(0, 0, second.width.toDouble(), second.height.toDouble()),
        _containedRect(second, output),
        paint,
      );
      canvas.restore();
    }

    return _encode(recorder, output);
  }

  // 3/4 vídeos: grelha do layout (spans respeitados).
  final spec = layoutSpec(settings.effectiveLayout);
  var cellW = 0.0;
  var cellH = 0.0;
  for (final cell in spec.cells) {
    final image = available[sideAtSlot(_slotOfSpec(spec, cell))];
    if (image == null) continue;
    cellW = math.max(cellW, image.width / cell.colSpan);
    cellH = math.max(cellH, image.height / cell.rowSpan);
  }
  if (cellW <= 0 || cellH <= 0) return null;
  final output = Size(cellW * spec.cols, cellH * spec.rows);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, output.width, output.height));
  canvas.drawRect(
    Rect.fromLTWH(0, 0, output.width, output.height),
    Paint()..color = const Color(0xFF090C0F),
  );
  final paint = Paint();
  for (final cell in spec.cells) {
    final image = available[sideAtSlot(_slotOfSpec(spec, cell))];
    if (image == null) continue;
    final dest = Rect.fromLTWH(
      cell.col * cellW,
      cell.row * cellH,
      cell.colSpan * cellW,
      cell.rowSpan * cellH,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      _containedRect(image, dest.size).translate(dest.left, dest.top),
      paint,
    );
  }
  return _encode(recorder, output);
}

/// Índice de slot de uma célula na ordem do spec (0..n-1).
int _slotOfSpec(LayoutSpec spec, LayoutCell cell) =>
    spec.cells.indexOf(cell);

Future<Uint8List?> _encode(ui.PictureRecorder recorder, Size size) async {
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data?.buffer.asUint8List();
}

Future<void> copyComparisonToClipboard(
  PlaybackBridge bridge,
  AppSettings settings,
) async {
  final bytes = await _compose(bridge, settings);
  if (bytes == null) throw StateError('Não há nada para capturar.');
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) throw StateError('Área de transferência indisponível.');
  final item = DataWriterItem();
  item.add(Formats.png(bytes));
  await clipboard.write([item]);
}

String defaultCaptureName() {
  final stamp = DateTime.now()
      .toIso8601String()
      .replaceAll(RegExp('[:.]'), '-')
      .substring(0, 19);
  return 'comparacao-$stamp.png';
}

Future<String?> saveComparisonPng(
  PlaybackBridge bridge,
  AppSettings settings,
) async {
  final bytes = await _compose(bridge, settings);
  if (bytes == null) return null;
  final name = defaultCaptureName();
  final location = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Imagem PNG', extensions: ['png']),
    ],
  );
  if (location == null) return null;
  await File(location.path).writeAsBytes(bytes);
  return location.path;
}
