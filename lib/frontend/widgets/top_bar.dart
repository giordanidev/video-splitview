/// Barra superior com nomes A/B e ações por lado.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/generated/version.dart';
import '../../backend/i18n/strings.dart';
import '../../backend/models/models.dart';
import '../../backend/services/file_picker_service.dart';
import '../../backend/services/playback_bridge.dart';
import '../../backend/state/providers.dart';
import '../../backend/state/settings.dart';
import '../theme/theme.dart';
import 'common.dart';

/// Atribui caminhos escolhidos: o 1.º ao lado indicado e os seguintes aos
/// lados ativos (por ordem, com wrap). Com **vários** ficheiros, ajusta o
/// número de views para `min(n, 4)` antes de carregar.
Future<void> assignPaths(
  WidgetRef ref,
  PlaybackBridge bridge,
  Side side,
  List<String> paths,
) async {
  if (paths.isEmpty) return;

  if (paths.length > 1) {
    final needed = clampViewCount(paths.length);
    final current = ref.read(settingsProvider).effectiveViewCount;
    if (needed != current) {
      ref.read(settingsProvider.notifier).mutate((s) => s.withViewCount(needed));
      await bridge.applyVideoOptions(ref.read(settingsProvider));
    }
  }

  final active = bridge.activeSides();
  if (active.isEmpty) return;

  var startIndex = active.indexOf(side);
  if (startIndex < 0) startIndex = 0;

  final limit = paths.length < active.length ? paths.length : active.length;
  for (var i = 0; i < limit; i++) {
    final target = active[(startIndex + i) % active.length];
    await bridge.loadFile(target, paths[i]);
  }
}

Future<void> pickFor(
  WidgetRef ref,
  PlaybackBridge bridge,
  Side side,
  Strings strings,
) async {
  final paths = await pickVideoPaths(strings);
  await assignPaths(ref, bridge, side, paths);
}

class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(playbackBridgeProvider);
    return ListenableBuilder(
      listenable: bridge,
      builder: (context, _) {
        final active = bridge.activeSides();
        final compact = active.length >= 3;

        Widget group(Side side) => _SideGroup(
              bridge: bridge,
              side: side,
              compact: compact,
            );

        // Divisória vertical entre grupos de vídeos (à direita).
        Widget divider() => Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
              child: Container(
                width: 2,
                height: compact ? 48 : 56,
                color: AppColors.lineStrong,
              ),
            );

        return Container(
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 20, vertical: compact ? 8 : 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
            color: AppColors.shell,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Brand à esquerda: encolhe e trunca o slogan se os botões
              // dos quadros precisarem do espaço.
              const Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _Brand(),
                ),
              ),
              const SizedBox(width: 12),
              for (var i = 0; i < active.length; i++) ...[
                if (i > 0) divider(),
                group(active[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Brand extends ConsumerWidget {
  const _Brand();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/icon/video_splitview.png',
            width: 48,
            height: 48,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.brandName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  strings.slogan,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'v$appVersion ($appCommit)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 10,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideGroup extends ConsumerWidget {
  const _SideGroup({
    required this.bridge,
    required this.side,
    this.compact = false,
  });

  final PlaybackBridge bridge;
  final Side side;

  /// Modo compacto (3-4 vídeos): botões só com ícone + nome curto, para os
  /// quatro grupos caberem na barra.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    final state = bridge.stateOf(side);

    final letter = Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.line),
        color: AppColors.panel2,
      ),
      child: Text(
        side.label,
        style: const TextStyle(
          fontFamily: AppFonts.display,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.accent,
        ),
      ),
    );

    final name = Tooltip(
      message: state.path ?? '',
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compact ? 72 : 160),
        child: Text(
          state.loaded ? (state.name ?? strings.noVideo) : strings.noVideo,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 11.5 : 12.5,
            color: state.loaded ? AppColors.text : AppColors.muted,
          ),
        ),
      ),
    );

    final openLabel = state.loaded ? strings.change : strings.open;
    final Widget openButton = compact
        ? SVIconButton(
            size: 32,
            tooltip: openLabel,
            onPressed: () => pickFor(ref, bridge, side, strings),
            child: const Icon(Icons.folder_open_outlined),
          )
        : SVTextButton(
            label: openLabel,
            onPressed: () => pickFor(ref, bridge, side, strings),
          );
    final Widget removeButton = compact
        ? SVIconButton(
            size: 32,
            tooltip: strings.removeVideo,
            onPressed: state.loaded ? () => bridge.unloadSide(side) : null,
            child: const Icon(Icons.delete_outline),
          )
        : SVTextButton(
            label: strings.remove,
            tooltip: strings.removeVideo,
            onPressed: state.loaded ? () => bridge.unloadSide(side) : null,
          );
    final muted = state.muted || state.volume <= 0;
    final muteButton = SVIconButton(
      size: compact ? 32 : 34,
      active: muted,
      tooltip: muted ? strings.unmuteSide : strings.muteSide,
      onPressed: state.loaded ? () => bridge.toggleMuteSide(side) : null,
      child: Icon(muted ? Icons.volume_off : Icons.volume_up),
    );
    // Gira o vídeo no próprio eixo (+90º) — distinto de "rodar posições".
    final Widget rotateButton = compact
        ? SVIconButton(
            size: 32,
            tooltip: strings.rotateVideo,
            onPressed:
                state.loaded ? () => bridge.rotateVideo(side) : null,
            child: const Icon(Icons.rotate_90_degrees_cw_outlined),
          )
        : SVTextButton(
            label: strings.rotateVideo,
            tooltip: strings.rotateVideo,
            onPressed:
                state.loaded ? () => bridge.rotateVideo(side) : null,
          );

    final gap = SizedBox(width: compact ? 6 : 8);
    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [letter, const SizedBox(width: 8), name],
    );
    final actionsRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [openButton, gap, removeButton, gap, rotateButton, gap, muteButton],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        labelRow,
        SizedBox(height: compact ? 5 : 8),
        actionsRow,
      ],
    );
  }
}
