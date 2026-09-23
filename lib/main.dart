import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'frontend/app.dart';
import 'backend/state/settings.dart';
import 'backend/state/window_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  final settingsStore = SettingsStore.portable();
  final settings = settingsStore.load();
  final windowStore = WindowStateStore(settingsStore);
  windowStore.attach(enabled: settings.rememberWindowState);
  final savedBounds =
      settings.rememberWindowState ? windowStore.loadBounds() : null;

  final options = WindowOptions(
    size: savedBounds != null
        ? Size(savedBounds.width, savedBounds.height)
        : const Size(1360, 820),
    minimumSize: const Size(960, 600),
    center: savedBounds == null,
    backgroundColor: const Color(0xFF090C0F),
    title: 'Video Splitview',
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    if (savedBounds != null) {
      try {
        await windowManager.setBounds(Rect.fromLTWH(
          savedBounds.x,
          savedBounds.y,
          savedBounds.width,
          savedBounds.height,
        ));
      } catch (_) {
        // Ignora bounds inválidos — abre centrado.
      }
    }
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(settingsStore),
        windowStateStoreProvider.overrideWithValue(windowStore),
      ],
      child: const VideoSplitviewApp(),
    ),
  );
}
