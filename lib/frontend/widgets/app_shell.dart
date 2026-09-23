/// Estrutura principal da aplicação: topbar + stage + controlos + modais.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../backend/services/playback_bridge.dart';
import '../../backend/state/providers.dart';
import '../../backend/state/settings.dart';
import '../../backend/state/update.dart';
import '../theme/theme.dart';
import 'assist_modal.dart';
import 'player_controls.dart';
import 'settings_modal.dart';
import 'stage.dart';
import 'top_bar.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _settingsOpen = false;
  String? _timeToast;
  int _timeToastToken = 0;

  Timer? _holdDelay;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bridge = ref.read(playbackBridgeProvider);
      final assist = ref.read(assistProvider);
      bridge.onLoadError = assist.show;
      // Verificação de atualizações em segundo plano (não bloqueia o arranque).
      ref.read(updateProvider);
      await bridge.init();
      await bridge.applyVideoOptions(ref.read(settingsProvider));
    });
  }

  @override
  void dispose() {
    _holdDelay?.cancel();
    _holdTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggleFullscreen() async {
    try {
      final active = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!active);
    } catch (_) {}
  }

  Future<void> _exitFullscreen() async {
    try {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      }
    } catch (_) {}
  }

  void _showTimeToast(double seconds) {
    final sign = seconds < 0 ? '\u2212' : '+';
    setState(() => _timeToast = '$sign${seconds.abs().toStringAsFixed(1)} s');
    final token = ++_timeToastToken;
    Timer(const Duration(milliseconds: 1200), () {
      if (mounted && token == _timeToastToken) setState(() => _timeToast = null);
    });
  }

  void _startHold(PlaybackBridge bridge, int direction) {
    if (_holdDelay != null || _holdTimer != null) return;
    bridge.frameStep(direction);
    final interval = holdIntervalMs(ref.read(settingsProvider));
    _holdDelay = Timer(const Duration(milliseconds: 300), () {
      _holdDelay = null;
      if (direction > 0) {
        // Frente: jog contínuo. Trás: passos exact — o play-direction=backward
        // do mpv não funciona de forma fiável neste libmpv (reproduz para a
        // frente com áudio).
        unawaited(bridge.startJog(
          direction: direction,
          holdIntervalMs: interval,
        ));
        return;
      }
      _holdTimer = Timer.periodic(Duration(milliseconds: interval), (_) {
        bridge.frameStep(direction);
      });
    });
  }

  void _stopHold(PlaybackBridge bridge) {
    _holdDelay?.cancel();
    _holdDelay = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    unawaited(bridge.endHold());
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event, PlaybackBridge bridge) {
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;

    if (event is KeyUpEvent) {
      if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
        _stopHold(bridge);
      }
      return KeyEventResult.ignored;
    }

    switch (key) {
      case LogicalKeyboardKey.escape:
        if (_settingsOpen) {
          setState(() => _settingsOpen = false);
        } else if (ref.read(assistProvider).open) {
          ref.read(assistProvider).close();
        } else {
          _exitFullscreen();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.f11:
        _toggleFullscreen();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        bridge.playPause();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyM:
        bridge.toggleMute();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyF:
        _toggleFullscreen();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowRight:
        final direction = key == LogicalKeyboardKey.arrowLeft ? -1 : 1;
        if (keyboard.isShiftPressed) {
          _stopHold(bridge);
          bridge.nudgeBy(direction * 1.0);
          _showTimeToast(direction * 1.0);
          return KeyEventResult.handled;
        }
        if (keyboard.isControlPressed || keyboard.isMetaPressed) {
          _stopHold(bridge);
          bridge.nudgeBy(direction * 5.0);
          _showTimeToast(direction * 5.0);
          return KeyEventResult.handled;
        }
        if (event is KeyRepeatEvent) return KeyEventResult.handled;
        bridge.setHoldActive(true);
        _startHold(bridge, direction);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(playbackBridgeProvider);
    final assist = ref.watch(assistProvider);
    final strings = ref.watch(stringsProvider);
    ref.listen<AppSettings>(settingsProvider, (previous, next) {
      bridge.applyVideoOptions(next);
    });

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => _onKey(node, event, bridge),
      child: Scaffold(
        backgroundColor: AppColors.shell,
        body: Stack(
          children: [
            Column(
              children: [
                const TopBar(),
                Expanded(child: Stack(children: [
                  const Stage(),
                  if (bridge.runtime.error != null)
                    _RuntimeAlert(
                      title: strings.runtimeAlert,
                      message: bridge.runtime.error!,
                    ),
                ])),
                PlayerControls(onOpenSettings: () => setState(() => _settingsOpen = true)),
              ],
            ),
            if (_timeToast != null) _ToastOverlay(text: _timeToast!),
            if (assist.open)
              AssistModal(
                bridge: bridge,
                onPickAnother: () => pickFor(ref, bridge, assist.side, strings),
              ),
            if (_settingsOpen) SettingsModal(onClose: () => setState(() => _settingsOpen = false)),
          ],
        ),
      ),
    );
  }
}

class _RuntimeAlert extends StatelessWidget {
  const _RuntimeAlert({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xF2161D23),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.6)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8)),
                const SizedBox(height: 6),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.text)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastOverlay extends StatelessWidget {
  const _ToastOverlay({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 96,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xF2161D23),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
            ),
            child: Text(text,
                style: const TextStyle(
                    fontFamily: AppFonts.mono, fontSize: 12.5, color: AppColors.text)),
          ),
        ),
      ),
    );
  }
}
