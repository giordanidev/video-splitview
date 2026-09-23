/// Providers Riverpod globais (bridge de reprodução + assistência).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/strings.dart';
import '../services/playback_bridge.dart';
import 'assist.dart';
import 'settings.dart';

final playbackBridgeProvider = Provider<PlaybackBridge>((ref) {
  final bridge = PlaybackBridge();
  ref.onDispose(bridge.dispose);
  return bridge;
});

final assistProvider = Provider<AssistController>((ref) {
  final controller = AssistController();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Catálogo de textos do idioma ativo (reativo).
final stringsProvider = Provider<Strings>((ref) {
  final language = ref.watch(settingsProvider.select((s) => s.language));
  return Strings.forLanguage(language);
});
