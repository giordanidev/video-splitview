/// Persistência da posição/tamanho da janela ("lembrar a janela").
///
/// Guarda os *bounds* normais (nunca minimizados: no Windows essa posição é
/// (-32000,-32000) e faria o app reabrir fora do ecrã) e restaura-os no
/// arranque quando a definição `rememberWindowState` está ativa.
///
/// Os bounds vivem em `settings.json` (chave `window`), no mesmo ficheiro
/// das restantes definições.
library;

import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'settings.dart';

class WindowStateStore with WindowListener {
  WindowStateStore(this._settings);

  final SettingsStore _settings;

  bool _enabled = false;
  Timer? _debounce;

  /// Bounds guardados via [SettingsStore] (`null` se não houver registos
  /// usáveis).
  SavedWindowBounds? loadBounds() => _settings.loadWindowBounds();

  /// Liga a escuta de move/resize da janela.
  void attach({required bool enabled}) {
    _enabled = enabled;
    windowManager.addListener(this);
  }

  /// Ativa/desativa a gravação; ao ativar, guarda os bounds atuais.
  void setEnabled(bool value) {
    _enabled = value;
    if (!value) {
      _debounce?.cancel();
      return;
    }
    unawaited(persistNow());
  }

  /// Grava os bounds atuais (imediato). Nunca grava com a janela
  /// minimizada, em ecrã inteiro ou com valores implausíveis.
  Future<void> persistNow() async {
    _debounce?.cancel();
    if (!_enabled) return;
    try {
      if (await windowManager.isMinimized()) return;
      if (await windowManager.isFullScreen()) return;
      final bounds = await windowManager.getBounds();
      if (!_plausible(bounds)) return;
      await _settings.saveWindowBounds(
        x: bounds.left,
        y: bounds.top,
        width: bounds.width,
        height: bounds.height,
      );
    } catch (_) {
      // Melhor não guardar do que guardar errado.
    }
  }

  static bool _plausible(Rect bounds) =>
      bounds.width.isFinite &&
      bounds.height.isFinite &&
      bounds.width >= 400 &&
      bounds.height >= 300 &&
      bounds.width <= 32768 &&
      bounds.height <= 32768 &&
      bounds.left.abs() <= 16384 &&
      bounds.top.abs() <= 16384;

  void _schedulePersist() {
    if (!_enabled) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(persistNow());
    });
  }

  @override
  void onWindowMove() => _schedulePersist();

  @override
  void onWindowResize() => _schedulePersist();

  @override
  void onWindowMoved() => unawaited(persistNow());

  @override
  void onWindowResized() => unawaited(persistNow());

  @override
  void onWindowMinimize() => _debounce?.cancel();

  @override
  void onWindowClose() => unawaited(persistNow());
}

/// Provider do store — substituído em `main()` com a instância real.
final windowStateStoreProvider = Provider<WindowStateStore>((ref) {
  throw UnimplementedError('windowStateStoreProvider deve ser substituído em main()');
});
