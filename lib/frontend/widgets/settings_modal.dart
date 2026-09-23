/// Modal de definições + seletor de idioma.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/generated/version.dart';
import '../../backend/i18n/strings.dart';
import '../../backend/models/models.dart';
import '../../backend/services/update_service.dart';
import '../../backend/state/providers.dart';
import '../../backend/state/settings.dart';
import '../../backend/state/update.dart';
import '../../backend/state/window_state.dart';
import '../theme/theme.dart';
import 'common.dart';
import 'flag.dart';

class SettingsModal extends ConsumerWidget {
  const SettingsModal({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final strings = ref.watch(stringsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return _ModalShell(
      title: strings.settings,
      closeTooltip: strings.close,
      onClose: onClose,
      children: [
        _LanguageRow(
          label: strings.languageLabel,
          value: settings.language,
          onChanged: (value) => notifier.mutate((s) => s.copyWith(language: value)),
        ),
        const Divider(color: AppColors.line),
        _Section(strings.sectionWindow),
        _SwitchRow(
          label: strings.rememberWindowState,
          value: settings.rememberWindowState,
          onChanged: (value) {
            notifier.mutate((s) => s.copyWith(rememberWindowState: value));
            ref.read(windowStateStoreProvider).setEnabled(value);
          },
        ),
        const Divider(color: AppColors.line),
        _Section(strings.sectionViews),
        _ViewCountRow(
          strings: strings,
          value: settings.effectiveViewCount,
          onChanged: (value) => notifier.mutate((s) => s.withViewCount(value)),
        ),
        if (settings.effectiveViewCount >= 2) ...[
          const SizedBox(height: 16),
          _Section(strings.sectionView),
          Row(
            children: [
              Expanded(
                child: _Choice(
                  title: strings.wipe,
                  hint: strings.wipeHint,
                  selected:
                      settings.splitMode == SplitMode.wipe && !settings.blinkEnabled,
                  onTap: () =>
                      notifier.mutate((s) => s.copyWith(splitMode: SplitMode.wipe)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Choice(
                  title: strings.columns,
                  hint: strings.columnsHint,
                  selected: settings.splitMode == SplitMode.columns &&
                      !settings.blinkEnabled,
                  onTap: () =>
                      notifier.mutate((s) => s.copyWith(splitMode: SplitMode.columns)),
                ),
              ),
            ],
          ),
        ],
        if (settings.effectiveViewCount >= 2) ...[
          const SizedBox(height: 16),
          _Section(strings.sectionOrientation),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final layout
                  in SplitLayout.forViewCount(settings.effectiveViewCount))
                _LayoutChoice(
                  layout: layout,
                  label: layoutName(layout, strings),
                  selected: settings.effectiveLayout == layout,
                  onTap: () => notifier.mutate((s) => s.withLayout(layout)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Rotacionar/Girar: só ícone, canto direito, logo abaixo dos layouts.
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SVIconButton(
                size: 34,
                tooltip: strings.rotateFrames,
                onPressed: () =>
                    ref.read(playbackBridgeProvider).rotateVideoPositions(),
                child: const Icon(Icons.rotate_right),
              ),
              const SizedBox(width: 8),
              SVIconButton(
                size: 34,
                tooltip: strings.rotateVideos,
                onPressed: () =>
                    ref.read(playbackBridgeProvider).rotateAllVideos(),
                child: const Icon(Icons.rotate_90_degrees_cw),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SwitchRow(
            label: strings.blinkToggle,
            value: settings.blinkEnabled,
            onChanged: (value) =>
                notifier.mutate((s) => s.copyWith(blinkEnabled: value)),
          ),
          _SliderRow(
            label: strings.blinkInterval,
            valueLabel: '${settings.blinkIntervalMs} ms',
            value: settings.blinkIntervalMs.toDouble(),
            min: blinkMinMs.toDouble(),
            max: blinkMaxMs.toDouble(),
            divisions: (blinkMaxMs - blinkMinMs) ~/ 10,
            onChanged: (value) =>
                notifier.mutate((s) => s.copyWith(blinkIntervalMs: value.round())),
          ),
          _PositionRow(
            strings: strings,
            value: settings.blinkLetterPosition,
            onChanged: (value) =>
                notifier.mutate((s) => s.copyWith(blinkLetterPosition: value)),
          ),
        ],
        const SizedBox(height: 16),
        _SliderRow(
          label: strings.holdSpeed,
          valueLabel: '${settings.holdSpeedPercent}%',
          value: settings.holdSpeedPercent.toDouble(),
          min: 10,
          max: 100,
          divisions: 18,
          onChanged: (value) =>
              notifier.mutate((s) => s.copyWith(holdSpeedPercent: value.round())),
        ),
        const Divider(color: AppColors.line),
        _Section(strings.sectionHud),
        _HudAxisRow<HudVPos>(
          label: strings.hudVerticalLabel,
          value: settings.hudVertical,
          options: [
            (HudVPos.top, strings.posTop),
            (HudVPos.center, strings.posCenter),
            (HudVPos.bottom, strings.posBottom),
            (HudVPos.corner, strings.posCorner),
          ],
          onChanged: (value) =>
              notifier.mutate((s) => s.copyWith(hudVertical: value)),
        ),
        _HudAxisRow<HudHPos>(
          label: strings.hudHorizontalLabel,
          value: settings.hudHorizontal,
          options: [
            (HudHPos.left, strings.posLeft),
            (HudHPos.center, strings.posCenter),
            (HudHPos.right, strings.posRight),
            (HudHPos.corner, strings.posCorner),
          ],
          onChanged: (value) =>
              notifier.mutate((s) => s.copyWith(hudHorizontal: value)),
        ),
        _SwitchRow(
          label: strings.fpsAlways,
          value: settings.fpsAlways,
          onChanged: (value) => notifier.mutate((s) => s.copyWith(fpsAlways: value)),
        ),
        _SwitchRow(
          label: strings.statsOverlay,
          value: settings.statsOverlay,
          onChanged: (value) => notifier.mutate((s) => s.copyWith(statsOverlay: value)),
        ),
        const Divider(color: AppColors.line),
        _Section(strings.sectionPerf),
        _DropdownRow<Scaler>(
          label: strings.scaler,
          value: settings.scaler,
          items: {
            Scaler.bilinear: strings.scalerBilinear,
            Scaler.bicubic: strings.scalerBicubic,
            Scaler.lanczos: strings.scalerLanczos,
          },
          onChanged: (value) => notifier.mutate((s) => s.copyWith(scaler: value)),
        ),
        _DropdownRow<VideoSyncMode>(
          label: strings.videoSync,
          value: settings.videoSync,
          items: {
            VideoSyncMode.audio: strings.syncAudio,
            VideoSyncMode.displayResample: strings.syncResample,
            VideoSyncMode.desync: strings.syncDesync,
          },
          onChanged: (value) => notifier.mutate((s) => s.copyWith(videoSync: value)),
        ),
        _DropdownRow<HardwareDecode>(
          label: strings.hwdec,
          value: settings.hardwareDecode,
          items: {
            HardwareDecode.off: strings.hwdecOff,
            HardwareDecode.compat: strings.hwdecCompat,
            HardwareDecode.direct: strings.hwdecDirect,
          },
          onChanged: (value) => notifier.mutate((s) => s.copyWith(hardwareDecode: value)),
        ),
        _SwitchRow(
          label: strings.framedrop,
          value: settings.framedrop,
          onChanged: (value) => notifier.mutate((s) => s.copyWith(framedrop: value)),
        ),
        _SwitchRow(
          label: strings.interpolation,
          value: settings.interpolation,
          onChanged: (value) => notifier.mutate((s) => s.copyWith(interpolation: value)),
        ),
        _DropdownRow<BufferProfile>(
          label: strings.bufferProfile,
          value: settings.bufferProfile,
          items: {
            BufferProfile.small: strings.bufferSmall,
            BufferProfile.normal: strings.bufferNormal,
            BufferProfile.large: strings.bufferLarge,
          },
          onChanged: (value) => notifier.mutate((s) => s.copyWith(bufferProfile: value)),
        ),
        _SwitchRow(
          label: strings.bufferIndicator,
          value: settings.bufferIndicator,
          onChanged: (value) => notifier.mutate((s) => s.copyWith(bufferIndicator: value)),
        ),
        const Divider(color: AppColors.line),
        _Section(strings.sectionPlayback),
        _DropdownRow<int>(
          label: strings.frameStepCount,
          value: settings.frameStepCount,
          items: {
            1: strings.stepFrames1,
            2: strings.stepFrames2,
            5: strings.stepFrames5,
          },
          onChanged: (value) => notifier.mutate((s) => s.copyWith(frameStepCount: value)),
        ),
        _SwitchRow(
          label: strings.driftMeter,
          value: settings.driftMeter,
          onChanged: (value) => notifier.mutate((s) => s.copyWith(driftMeter: value)),
        ),
        const SizedBox(height: 4),
        Text(
          strings.settingsNote,
          style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
        ),
        const Divider(color: AppColors.line),
        _Section(strings.sectionUpdates),
        _UpdatesSection(strings: strings),
      ],
    );
  }
}

/// Linha simples rótulo → valor (mono), usada na secção de atualizações.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Secção de atualizações: versão atual, estado da verificação e links.
class _UpdatesSection extends ConsumerWidget {
  const _UpdatesSection({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final check = ref.watch(updateProvider);
    final controller = ref.read(updateProvider.notifier);
    final checking = check.isLoading;

    final (statusText, statusColor) = switch (check) {
      AsyncData(:final value) => switch (value.phase) {
          UpdatePhase.upToDate => (strings.updateUpToDate, AppColors.teal),
          UpdatePhase.available => (
              '${strings.updateAvailable} — v${value.latestVersion}',
              AppColors.accent,
            ),
          UpdatePhase.failed => (strings.updateFailed, AppColors.muted),
        },
      AsyncError() => (strings.updateFailed, AppColors.muted),
      _ => (strings.updateChecking, AppColors.muted),
    };

    final result = check.value;
    final available = result?.hasUpdate ?? false;
    final releaseUrl = result?.releaseUrl ?? appReleasesUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoRow(label: strings.updateCurrent, value: 'v$appVersion'),
        const SizedBox(height: 6),
        Text(
          statusText,
          style: TextStyle(fontSize: 12, color: statusColor, height: 1.3),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SVTextButton(
              label: checking ? strings.updateChecking : strings.updateCheckNow,
              onPressed: checking ? null : () => controller.recheck(),
            ),
            if (available)
              SVTextButton(
                label: strings.updateDownload,
                primary: true,
                onPressed: () => openExternalUrl(releaseUrl),
              ),
            SVTextButton(
              label: strings.updateOpenReleases,
              onPressed: () => openExternalUrl(appReleasesUrl),
            ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: AppColors.muted,
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected ? AppColors.accentSoft : Colors.white.withValues(alpha: 0.02),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.line,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(hint,
                style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text(valueLabel, style: const TextStyle(fontSize: 12, color: AppColors.accent)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _DropdownRow<T> extends StatelessWidget {
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          SizedBox(
            width: 250,
            child: Align(
              alignment: Alignment.centerRight,
              child: DropdownButton<T>(
                value: value,
                underline: const SizedBox.shrink(),
                dropdownColor: AppColors.panel2,
                mouseCursor: SystemMouseCursors.click,
                style: const TextStyle(fontSize: 12.5, color: AppColors.text),
                items: items.entries
                    .map((entry) => DropdownMenuItem<T>(
                          value: entry.key,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Text(entry.value),
                          ),
                        ))
                    .toList(),
                onChanged: (selected) {
                  if (selected != null) onChanged(selected);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Linha com interruptor alinhado à direita, consistente com `_DropdownRow`.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Switch(
              value: value,
              activeThumbColor: AppColors.accent,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Seletor segmentado da posição vertical das letras do Blink.
class _PositionRow extends StatelessWidget {
  const _PositionRow({
    required this.strings,
    required this.value,
    required this.onChanged,
  });

  final Strings strings;
  final BlinkLetterPosition value;
  final ValueChanged<BlinkLetterPosition> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(strings.letterPosition, style: const TextStyle(fontSize: 13)),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _seg(strings.posTop, BlinkLetterPosition.top),
                _seg(strings.posCenter, BlinkLetterPosition.center),
                _seg(strings.posBottom, BlinkLetterPosition.bottom),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seg(String label, BlinkLetterPosition option) {
    final selected = value == option;
    return InkWell(
      onTap: () => onChanged(option),
      mouseCursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppColors.text : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

/// Seletor segmentado de um eixo da posição das informações (HUD) — linhas
/// verticais e horizontais independentes.
class _HudAxisRow<T> extends StatelessWidget {
  const _HudAxisRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (option, text) in options) _seg(text, option),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seg(String text, T option) {
    final selected = value == option;
    return InkWell(
      onTap: () => onChanged(option),
      mouseCursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppColors.text : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

/// Seletor segmentado do número de vídeos visíveis (1..4).
class _ViewCountRow extends StatelessWidget {
  const _ViewCountRow({
    required this.strings,
    required this.value,
    required this.onChanged,
  });

  final Strings strings;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(strings.sectionViews, style: const TextStyle(fontSize: 13)),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final count in const [1, 2, 3, 4])
                  _seg(viewCountLabel(count, strings), count),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seg(String label, int option) {
    final selected = value == option;
    return InkWell(
      onTap: () => onChanged(option),
      mouseCursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppColors.text : AppColors.muted,
          ),
        ),
      ),
    );
  }
}

/// Chip de escolha de um layout de divisão ( Wrap da secção de layouts),
/// com mini-previsualização desenhada.
class _LayoutChoice extends StatelessWidget {
  const _LayoutChoice({
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
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 96,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(10),
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

/// Seletor de idioma em dropdown, com bandeira + nome e o rótulo à esquerda.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final AppLanguage value;
  final ValueChanged<AppLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          SizedBox(
            width: 250,
            child: Align(
              alignment: Alignment.centerRight,
              child: DropdownButton<AppLanguage>(
                value: value,
                underline: const SizedBox.shrink(),
                dropdownColor: AppColors.panel2,
                borderRadius: BorderRadius.circular(10),
                mouseCursor: SystemMouseCursors.click,
                style: const TextStyle(fontSize: 12.5, color: AppColors.text),
                items: AppLanguage.values
                    .map((language) => DropdownMenuItem<AppLanguage>(
                          value: language,
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FlagIcon(language: language),
                                const SizedBox(width: 8),
                                Text('${language.label} (${language.code})'),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
                onChanged: (selected) {
                  if (selected != null) onChanged(selected);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModalShell extends StatefulWidget {
  const _ModalShell({
    required this.title,
    required this.closeTooltip,
    required this.onClose,
    required this.children,
  });

  final String title;
  final String closeTooltip;
  final VoidCallback onClose;
  final List<Widget> children;

  @override
  State<_ModalShell> createState() => _ModalShellState();
}

class _ModalShellState extends State<_ModalShell> {
  /// Deslocação do cartão (arrastável pelo cabeçalho/áreas soltas).
  Offset _offset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Positioned.fill(
      child: Stack(
        children: [
          // Sem barreira: o resto da app continua clicável; fechar só pelo
          // botão X ou ESC (tratado em AppShell).
          Center(
            child: Transform.translate(
              offset: _offset,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) {
                  setState(() {
                    _offset = Offset(
                      (_offset.dx + details.delta.dx)
                          .clamp(-screen.width / 3, screen.width / 3),
                      (_offset.dy + details.delta.dy)
                          .clamp(-screen.height / 3, screen.height / 3),
                    );
                  });
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 512, maxHeight: 700),
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    // Direita sem padding: o viewport encosta ao bordo do card
                    // e a scrollbar desenha-se no limite do modal; o conteúdo
                    // ganha o seu próprio padding-right para ficar alinhado.
                    padding:
                        const EdgeInsets.only(left: 22, top: 22, bottom: 22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.lineStrong),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF131A20), Color(0xFF0C1116)],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 22),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.title,
                                  style: const TextStyle(
                                    fontFamily: AppFonts.display,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              SVIconButton(
                                size: 34,
                                tooltip: widget.closeTooltip,
                                onPressed: widget.onClose,
                                child: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 22),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: widget.children,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
