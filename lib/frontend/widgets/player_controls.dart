/// Barra de controlos inferior (transporte, timeline, extras).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../backend/i18n/strings.dart';
import '../../backend/models/models.dart';
import '../../backend/services/capture_service.dart';
import '../../backend/services/playback_bridge.dart';
import '../../backend/state/providers.dart';
import '../../backend/state/settings.dart';
import '../../backend/state/update.dart';
import '../theme/theme.dart';
import 'common.dart';

class PlayerControls extends ConsumerStatefulWidget {
  const PlayerControls({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  ConsumerState<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends ConsumerState<PlayerControls> {
  bool _scrubbing = false;
  bool _wasPlaying = false;
  double _scrubValue = 0;
  String? _feedback;
  int _feedbackToken = 0;

  // Popover do Blink (hover do botão, acima dele).
  final LayerLink _blinkLink = LayerLink();
  final OverlayPortalController _blinkOverlay = OverlayPortalController();
  Timer? _blinkHideTimer;

  // Popover do volume (% acima do slider; some 3 s após a última interação).
  final LayerLink _volumeLink = LayerLink();
  final OverlayPortalController _volumeOverlay = OverlayPortalController();
  Timer? _volumeHideTimer;
  Timer? _volumeIdleTimer;

  // Popover da velocidade (hover do botão, acima dele).
  final LayerLink _rateLink = LayerLink();
  final OverlayPortalController _rateOverlay = OverlayPortalController();
  Timer? _rateHideTimer;

  // Popover do número de vídeos (hover do botão, acima dele).
  final LayerLink _viewsLink = LayerLink();
  final OverlayPortalController _viewsOverlay = OverlayPortalController();
  Timer? _viewsHideTimer;

  // Popover do layout de divisão (hover do botão, acima dele).
  final LayerLink _layoutLink = LayerLink();
  final OverlayPortalController _layoutOverlay = OverlayPortalController();
  Timer? _layoutHideTimer;

  void _showBlinkOverlay() {
    _blinkHideTimer?.cancel();
    _blinkHideTimer = null;
    if (!_blinkOverlay.isShowing) _blinkOverlay.show();
  }

  void _scheduleHideBlinkOverlay() {
    _blinkHideTimer?.cancel();
    _blinkHideTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted && _blinkOverlay.isShowing) _blinkOverlay.hide();
    });
  }

  /// Mostra/atualiza o popover de volume e reinicia o timer de 3 s.
  void _touchVolumeOverlay() {
    _volumeHideTimer?.cancel();
    _volumeHideTimer = null;
    if (!_volumeOverlay.isShowing) _volumeOverlay.show();
    _volumeIdleTimer?.cancel();
    _volumeIdleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _volumeOverlay.isShowing) _volumeOverlay.hide();
    });
  }

  void _scheduleHideVolumeOverlay() {
    _volumeHideTimer?.cancel();
    _volumeHideTimer = Timer(const Duration(milliseconds: 260), () {
      _volumeIdleTimer?.cancel();
      if (mounted && _volumeOverlay.isShowing) _volumeOverlay.hide();
    });
  }

  void _showRateOverlay() {
    _rateHideTimer?.cancel();
    _rateHideTimer = null;
    if (!_rateOverlay.isShowing) _rateOverlay.show();
  }

  void _scheduleHideRateOverlay() {
    _rateHideTimer?.cancel();
    _rateHideTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted && _rateOverlay.isShowing) _rateOverlay.hide();
    });
  }

  void _showViewsOverlay() {
    _viewsHideTimer?.cancel();
    _viewsHideTimer = null;
    if (!_viewsOverlay.isShowing) _viewsOverlay.show();
  }

  void _scheduleHideViewsOverlay() {
    _viewsHideTimer?.cancel();
    _viewsHideTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted && _viewsOverlay.isShowing) _viewsOverlay.hide();
    });
  }

  void _showLayoutOverlay() {
    _layoutHideTimer?.cancel();
    _layoutHideTimer = null;
    if (!_layoutOverlay.isShowing) _layoutOverlay.show();
  }

  void _scheduleHideLayoutOverlay() {
    _layoutHideTimer?.cancel();
    _layoutHideTimer = Timer(const Duration(milliseconds: 260), () {
      if (mounted && _layoutOverlay.isShowing) _layoutOverlay.hide();
    });
  }

  @override
  void dispose() {
    _blinkHideTimer?.cancel();
    _volumeHideTimer?.cancel();
    _volumeIdleTimer?.cancel();
    _rateHideTimer?.cancel();
    _viewsHideTimer?.cancel();
    _layoutHideTimer?.cancel();
    super.dispose();
  }

  void _showFeedback(String message) {
    setState(() => _feedback = message);
    final token = ++_feedbackToken;
    Future<void>.delayed(const Duration(milliseconds: 3200), () {
      if (mounted && token == _feedbackToken) setState(() => _feedback = null);
    });
  }

  Future<void> _toggleFullscreen() async {
    try {
      final active = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!active);
    } catch (_) {}
  }

  Future<void> _onCopy(PlaybackBridge bridge, Strings strings) async {
    try {
      await copyComparisonToClipboard(bridge, ref.read(settingsProvider));
      _showFeedback(strings.copiedImage);
    } catch (_) {
      _showFeedback(strings.copyImageFailed);
    }
  }

  Future<void> _onSave(PlaybackBridge bridge, Strings strings) async {
    try {
      final path = await saveComparisonPng(bridge, ref.read(settingsProvider));
      if (path != null) _showFeedback(strings.savedImage);
    } catch (_) {
      _showFeedback(strings.saveImageFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(playbackBridgeProvider);
    final settings = ref.watch(settingsProvider);
    final strings = ref.watch(stringsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final updateAvailable =
        ref.watch(updateProvider).value?.hasUpdate ?? false;

    return ListenableBuilder(
      listenable: bridge,
      builder: (context, _) {
        final loaded = bridge.loadedSides().isNotEmpty;
        final reference = bridge.stateOf(bridge.authority());
        final duration = reference.duration;
        final position = _scrubbing ? _scrubValue : reference.position;
        final canSeek = loaded && duration > 0;
        final playing = bridge.isPlaying();
        final ended = bridge.isEnded();
        final muted = reference.muted || reference.volume <= 0;
        final volumePercent = reference.volume.round();
        final splitLabel =
            settings.splitMode == SplitMode.wipe ? strings.splitWipe : strings.splitColumns;

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
                color: AppColors.shell,
              ),
              child: Row(
                children: [
                  Row(
                    children: [
                      SVIconButton(
                        size: 42,
                        active: true,
                        tooltip: ended
                            ? strings.repeat
                            : playing
                                ? strings.pause
                                : strings.play,
                        onPressed: loaded ? () => bridge.playPause() : null,
                        child: Icon(
                          ended
                              ? Icons.replay
                              : playing
                                  ? Icons.pause
                                  : Icons.play_arrow,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SVIconButton(
                        tooltip: strings.stop,
                        onPressed: loaded ? () => bridge.stop() : null,
                        child: const Icon(Icons.stop),
                      ),
                    ],
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 52,
                              child: Text(
                                formatTime(position),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: AppFonts.mono,
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                min: 0,
                                max: canSeek ? duration : 1,
                                value: canSeek ? position.clamp(0, duration) : 0,
                                onChangeStart: canSeek
                                    ? (value) {
                                        setState(() {
                                          _scrubbing = true;
                                          _wasPlaying = playing;
                                          _scrubValue = value;
                                        });
                                        bridge.setScrubbing(true);
                                        if (playing) bridge.pauseAll();
                                      }
                                    : null,
                                onChanged: canSeek
                                    ? (value) => setState(() => _scrubValue = value)
                                    : null,
                                onChangeEnd: canSeek
                                    ? (value) async {
                                        setState(() => _scrubbing = false);
                                        bridge.setScrubbing(false);
                                        await bridge.seek(value, exact: true);
                                        if (_wasPlaying) await bridge.playPause();
                                      }
                                    : null,
                              ),
                            ),
                            SizedBox(
                              width: 52,
                              child: Text(
                                formatTime(duration),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: AppFonts.mono,
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Row(
                    children: [
                      SVIconButton(
                        active: muted,
                        tooltip: muted ? strings.unmute : strings.mute,
                        onPressed: loaded ? () => bridge.toggleMute() : null,
                        child: Icon(muted ? Icons.volume_off : Icons.volume_up),
                      ),
                      const SizedBox(width: 12),
                      OverlayPortal(
                        controller: _volumeOverlay,
                        overlayChildBuilder: (context) =>
                            CompositedTransformFollower(
                              link: _volumeLink,
                              showWhenUnlinked: false,
                              targetAnchor: Alignment.topCenter,
                              followerAnchor: Alignment.bottomCenter,
                              offset: const Offset(0, -10),
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: SizedBox(
                                  width: 74,
                                  child: MouseRegion(
                                    onEnter: (_) => _touchVolumeOverlay(),
                                    onExit: (_) => _scheduleHideVolumeOverlay(),
                                    child: _VolumePopover(percent: volumePercent),
                                  ),
                                ),
                              ),
                            ),
                        child: CompositedTransformTarget(
                          link: _volumeLink,
                          child: MouseRegion(
                            onEnter: (_) => _touchVolumeOverlay(),
                            onExit: (_) => _scheduleHideVolumeOverlay(),
                            child: SizedBox(
                              width: 96,
                              child: Slider(
                                min: 0,
                                max: 100,
                                value: volumePercent.toDouble().clamp(0, 100),
                                onChanged: loaded
                                    ? (value) {
                                        bridge.setVolume(value);
                                        _touchVolumeOverlay();
                                      }
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OverlayPortal(
                        controller: _rateOverlay,
                        overlayChildBuilder: (context) => CompositedTransformFollower(
                          link: _rateLink,
                          showWhenUnlinked: false,
                          targetAnchor: Alignment.topCenter,
                          followerAnchor: Alignment.bottomCenter,
                          offset: const Offset(0, -10),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: SizedBox(
                              width: 252,
                              child: MouseRegion(
                                onEnter: (_) => _showRateOverlay(),
                                onExit: (_) => _scheduleHideRateOverlay(),
                                child: const _RatePopover(),
                              ),
                            ),
                          ),
                        ),
                        child: CompositedTransformTarget(
                          link: _rateLink,
                          child: MouseRegion(
                            onEnter: (_) => _showRateOverlay(),
                            onExit: (_) => _scheduleHideRateOverlay(),
                            child: SVIconButton(
                              active: (settings.playbackRate - 1.0).abs() > 0.001,
                              tooltip: strings.playbackRate,
                              onPressed: () {
                                if (_rateOverlay.isShowing) {
                                  _scheduleHideRateOverlay();
                                } else {
                                  _showRateOverlay();
                                }
                              },
                              child: const Icon(Icons.speed),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OverlayPortal(
                        controller: _viewsOverlay,
                        overlayChildBuilder: (context) => CompositedTransformFollower(
                          link: _viewsLink,
                          showWhenUnlinked: false,
                          targetAnchor: Alignment.topCenter,
                          followerAnchor: Alignment.bottomCenter,
                          offset: const Offset(0, -10),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: SizedBox(
                              width: 300,
                              child: MouseRegion(
                                onEnter: (_) => _showViewsOverlay(),
                                onExit: (_) => _scheduleHideViewsOverlay(),
                                child: const _ViewsPopover(),
                              ),
                            ),
                          ),
                        ),
                        child: CompositedTransformTarget(
                          link: _viewsLink,
                          child: MouseRegion(
                            onEnter: (_) => _showViewsOverlay(),
                            onExit: (_) => _scheduleHideViewsOverlay(),
                            child: SVIconButton(
                              active: settings.effectiveViewCount != 2,
                              tooltip:
                                  '${strings.sectionViews}: ${viewCountLabel(settings.effectiveViewCount, strings)}',
                              onPressed: () {
                                if (_viewsOverlay.isShowing) {
                                  _scheduleHideViewsOverlay();
                                } else {
                                  _showViewsOverlay();
                                }
                              },
                              child: Icon(switch (settings.effectiveViewCount) {
                                1 => Icons.crop_original,
                                3 => Icons.grid_3x3,
                                4 => Icons.grid_view,
                                _ => Icons.view_agenda,
                              }),
                            ),
                          ),
                        ),
                      ),
                      if (settings.effectiveViewCount >= 2) ...[
                        const SizedBox(width: 12),
                        SVIconButton(
                          active: !settings.blinkEnabled &&
                              settings.splitMode == SplitMode.wipe,
                          tooltip:
                              '${strings.splitWipe}/${strings.splitColumns}: $splitLabel',
                          onPressed: () => notifier.mutate((s) => s.copyWith(
                                splitMode: s.splitMode == SplitMode.wipe
                                    ? SplitMode.columns
                                    : SplitMode.wipe,
                                blinkEnabled: false,
                              )),
                          child: Icon(settings.splitMode == SplitMode.wipe
                              ? Icons.vertical_split
                              : Icons.view_column),
                        ),
                      ],
                      if (settings.effectiveViewCount >= 2) ...[
                        const SizedBox(width: 12),
                        OverlayPortal(
                          controller: _layoutOverlay,
                          overlayChildBuilder: (context) =>
                              CompositedTransformFollower(
                            link: _layoutLink,
                            showWhenUnlinked: false,
                            targetAnchor: Alignment.topCenter,
                            followerAnchor: Alignment.bottomCenter,
                            offset: const Offset(0, -10),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: SizedBox(
                                width: 448,
                                child: MouseRegion(
                                  onEnter: (_) => _showLayoutOverlay(),
                                  onExit: (_) => _scheduleHideLayoutOverlay(),
                                  child: const _LayoutPopover(),
                                ),
                              ),
                            ),
                          ),
                          child: CompositedTransformTarget(
                            link: _layoutLink,
                            child: MouseRegion(
                              onEnter: (_) => _showLayoutOverlay(),
                              onExit: (_) => _scheduleHideLayoutOverlay(),
                              child: SVIconButton(
                                active: settings.effectiveLayout !=
                                    SplitLayout.defaultFor(
                                        settings.effectiveViewCount),
                                tooltip: strings.toggleOrientation,
                                onPressed: () {
                                  if (_layoutOverlay.isShowing) {
                                    _scheduleHideLayoutOverlay();
                                  } else {
                                    _showLayoutOverlay();
                                  }
                                },
                                child: Icon(switch (settings.effectiveLayout) {
                                  SplitLayout.stacked =>
                                    Icons.horizontal_split,
                                  SplitLayout.columns4 ||
                                  SplitLayout.grid2x2 ||
                                  SplitLayout.rows4 =>
                                    Icons.grid_view,
                                  SplitLayout.columns3 ||
                                  SplitLayout.rows3 =>
                                    Icons.grid_3x3,
                                  _ => Icons.vertical_split,
                                }),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OverlayPortal(
                          controller: _blinkOverlay,
                          overlayChildBuilder: (context) =>
                              CompositedTransformFollower(
                            link: _blinkLink,
                            showWhenUnlinked: false,
                            // O Overlay impõe constraints "tight" (tamanho do
                            // ecrã) ao entry, por isso não dá para dimensionar o
                            // follower pelo conteúdo. Ancora-se pelo canto
                            // inferior esquerdo do follower e alinha-se o
                            // popover a bottomLeft: fica logo acima do botão,
                            // centrado, com a largura fixa e a altura do próprio
                            // conteúdo.
                            targetAnchor: Alignment.topCenter,
                            followerAnchor: Alignment.bottomLeft,
                            offset: const Offset(-140, -10),
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: SizedBox(
                                width: 280,
                                child: MouseRegion(
                                  onEnter: (_) => _showBlinkOverlay(),
                                  onExit: (_) => _scheduleHideBlinkOverlay(),
                                  child: const _BlinkPopover(),
                                ),
                              ),
                            ),
                          ),
                          child: CompositedTransformTarget(
                            link: _blinkLink,
                            child: MouseRegion(
                              onEnter: (_) => _showBlinkOverlay(),
                              onExit: (_) => _scheduleHideBlinkOverlay(),
                              child: SVIconButton(
                                active: settings.blinkEnabled,
                                tooltip: strings.blink,
                                onPressed: () => notifier.mutate(
                                    (s) => s.copyWith(blinkEnabled: !s.blinkEnabled)),
                                child: const Icon(Icons.compare_arrows),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 12),
                      SVIconButton(
                        tooltip: strings.fullscreen,
                        onPressed: _toggleFullscreen,
                        child: const Icon(Icons.fullscreen),
                      ),
                      const SizedBox(width: 12),
                      SVIconButton(
                        tooltip: strings.copyImage,
                        onPressed: () => _onCopy(bridge, strings),
                        child: const Icon(Icons.image_outlined),
                      ),
                      const SizedBox(width: 12),
                      SVIconButton(
                        tooltip: strings.saveImage,
                        onPressed: () => _onSave(bridge, strings),
                        child: const Icon(Icons.photo_camera_outlined),
                      ),
                      const SizedBox(width: 12),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          SVIconButton(
                            tooltip: updateAvailable
                                ? '${strings.settings} · ${strings.updateAvailable}'
                                : strings.settings,
                            onPressed: widget.onOpenSettings,
                            child: const Icon(Icons.settings),
                          ),
                          if (updateAvailable)
                            Positioned(
                              top: 3,
                              right: 3,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.shell,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_feedback != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _Toast(text: _feedback!),
              ),
          ],
        );
      },
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xF2161D23),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.text)),
    );
  }
}

/// Popover mostrado no hover do slider de volume: só a percentagem, no
/// mesmo estilo do popover do Blink (some 3 s após a última interação).
class _VolumePopover extends StatelessWidget {
  const _VolumePopover({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xF70E1418),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lineStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Text(
        '$percent%',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

/// Popover mostrado no hover do botão de velocidade: slider 0.25×–2× (passo
/// de 0.1) e chips rápidos 0.5/1.0/1.5/2.0 (estilo do popover do Blink).
class _RatePopover extends ConsumerWidget {
  const _RatePopover();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final strings = ref.watch(stringsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    void setRate(double value) =>
        notifier.mutate((s) => s.copyWith(playbackRate: clampPlaybackRate(value)));

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xF70E1418),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lineStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.playbackRate,
                  style: const TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _formatRate(settings.playbackRate),
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Slider(
            min: playbackRateMin,
            max: playbackRateMax,
            value: settings.playbackRate.clamp(playbackRateMin, playbackRateMax),
            onChanged: (value) => setRate(_snapRateStep(value)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final rate in const [0.5, 1.0, 1.5, 2.0]) ...[
                _RateChip(
                  label: _formatRate(rate),
                  selected: (settings.playbackRate - rate).abs() < 0.001,
                  onTap: () => setRate(rate),
                ),
                if (rate != 2.0) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Arredonda a velocidade ao passo de 0.1 a partir do mínimo (0.25×).
double _snapRateStep(double value) {
  final tenths = ((value - playbackRateMin) * 10).round();
  return clampPlaybackRate(playbackRateMin + tenths / 10);
}

/// Formata a velocidade para apresentação (`1.0×`, `0.75×`, `0.3×`).
String _formatRate(double value) {
  var text = value.toStringAsFixed(2);
  // Remove um único zero final: `1.00` → `1.0`, `0.50` → `0.5`.
  if (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  return '$text×';
}

class _RateChip extends StatelessWidget {
  const _RateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 11.5,
            color: selected ? AppColors.text : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

/// Popover mostrado no hover do botão Blink: intervalo + posição das letras.
class _BlinkPopover extends ConsumerWidget {
  const _BlinkPopover();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final strings = ref.watch(stringsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xF70E1418),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lineStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                strings.blinkTitle,
                style: const TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${settings.blinkIntervalMs} ms',
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Slider(
            min: blinkMinMs.toDouble(),
            max: blinkMaxMs.toDouble(),
            divisions: (blinkMaxMs - blinkMinMs) ~/ 10,
            value: settings.blinkIntervalMs
                .toDouble()
                .clamp(blinkMinMs.toDouble(), blinkMaxMs.toDouble()),
            onChanged: (value) =>
                notifier.mutate((s) => s.copyWith(blinkIntervalMs: value.round())),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(strings.letterPosition, style: const TextStyle(fontSize: 12.5)),
              ),
              _PositionChips(
                strings: strings,
                value: settings.blinkLetterPosition,
                onChanged: (value) =>
                    notifier.mutate((s) => s.copyWith(blinkLetterPosition: value)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PositionChips extends StatelessWidget {
  const _PositionChips({
    required this.strings,
    required this.value,
    required this.onChanged,
  });

  final Strings strings;
  final BlinkLetterPosition value;
  final ValueChanged<BlinkLetterPosition> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip(strings.posTop, BlinkLetterPosition.top),
          _chip(strings.posCenter, BlinkLetterPosition.center),
          _chip(strings.posBottom, BlinkLetterPosition.bottom),
        ],
      ),
    );
  }

  Widget _chip(String label, BlinkLetterPosition option) {
    final selected = value == option;
    return InkWell(
      onTap: () => onChanged(option),
      mouseCursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: selected ? AppColors.text : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

/// Popover mostrado no hover do botão de views: escolha de 1..4 vídeos.
class _ViewsPopover extends ConsumerWidget {
  const _ViewsPopover();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final strings = ref.watch(stringsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xF70E1418),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lineStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.sectionViews,
            style: const TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final count in const [1, 2, 3, 4]) ...[
                Tooltip(
                  message: viewCountLabel(count, strings),
                  child: _ViewsChip(
                    label: '$count',
                    selected: settings.effectiveViewCount == count,
                    onTap: () =>
                        notifier.mutate((s) => s.withViewCount(count)),
                  ),
                ),
                if (count != 4) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ViewsChip extends StatelessWidget {
  const _ViewsChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 58,
        padding: const EdgeInsets.symmetric(vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.text : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

/// Popover mostrado no hover do botão de layout: mini-previsões dos layouts
/// disponíveis para o número de vídeos ativo.
class _LayoutPopover extends ConsumerWidget {
  const _LayoutPopover();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final strings = ref.watch(stringsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final count = settings.effectiveViewCount;
    final layouts = SplitLayout.forViewCount(count);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xF70E1418),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lineStrong),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.sectionOrientation,
                  style: const TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                layoutName(settings.effectiveLayout, strings),
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: strings.rotateFrames,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  mouseCursor: SystemMouseCursors.click,
                  onTap: () =>
                      ref.read(playbackBridgeProvider).rotateVideoPositions(),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.lineStrong),
                    ),
                    child: const Icon(
                      Icons.rotate_right,
                      size: 16,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Girar global: todos os vídeos +90º no próprio eixo.
              Tooltip(
                message: strings.rotateVideos,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  mouseCursor: SystemMouseCursors.click,
                  onTap: () =>
                      ref.read(playbackBridgeProvider).rotateAllVideos(),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.lineStrong),
                    ),
                    child: const Icon(
                      Icons.rotate_90_degrees_cw,
                      size: 16,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final layout in layouts)
                _LayoutChip(
                  layout: layout,
                  label: layoutName(layout, strings),
                  selected: settings.effectiveLayout == layout,
                  onTap: () => notifier.mutate((s) => s.withLayout(layout)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LayoutChip extends StatelessWidget {
  const _LayoutChip({
    required this.layout,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final SplitLayout layout;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 96,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.line,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutPreview(layout: layout, selected: selected),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: selected ? AppColors.text : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
