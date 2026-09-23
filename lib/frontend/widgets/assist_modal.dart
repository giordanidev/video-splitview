/// Modal de assistência de reprodução.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/i18n/strings.dart';
import '../../backend/services/playback_bridge.dart';
import '../../backend/state/providers.dart';
import '../theme/theme.dart';
import 'common.dart';

class AssistModal extends ConsumerWidget {
  const AssistModal({super.key, required this.bridge, required this.onPickAnother});

  final PlaybackBridge bridge;
  final VoidCallback onPickAnother;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assist = ref.watch(assistProvider);
    final strings = ref.watch(stringsProvider);
    if (!assist.open) return const SizedBox.shrink();

    final sideLabel = sideLabelOf(assist.side, strings);
    final message =
        assist.message.trim().isEmpty ? strings.assistFallback : assist.message;

    return Positioned.fill(
      child: GestureDetector(
        onTap: assist.close,
        child: Container(
          color: Colors.black.withValues(alpha: 0.6),
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 480,
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(22),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: AppColors.danger, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.assistTitle,
                              style: const TextStyle(
                                fontFamily: AppFonts.display,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${strings.diagSide} $sideLabel · ${assist.fileName ?? strings.diagUnknown}',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      SVIconButton(
                        size: 34,
                        tooltip: strings.close,
                        onPressed: assist.close,
                        child: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(message, style: const TextStyle(fontSize: 13, height: 1.4)),
                  const SizedBox(height: 12),
                  Text(
                    strings.assistNote,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.muted, height: 1.4),
                  ),
                  if (assist.engine != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: assist.engine!.ok
                              ? AppColors.teal.withValues(alpha: 0.6)
                              : AppColors.danger.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${strings.engineLabel}: '
                            '${assist.engine!.ok ? strings.engineOk : strings.engineProblem}'
                            '${assist.engine!.bundled ? ' · ${strings.engineBundled}' : ''}',
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                          if (assist.engine!.version != null)
                            Text(assist.engine!.version!,
                                style: const TextStyle(
                                    fontFamily: AppFonts.mono,
                                    fontSize: 11,
                                    color: AppColors.muted)),
                          Text(assist.engine!.message,
                              style: const TextStyle(
                                  fontSize: 11.5, color: AppColors.muted)),
                        ],
                      ),
                    ),
                  ],
                  if (assist.feedback != null) ...[
                    const SizedBox(height: 10),
                    Text(assist.feedback!,
                        style: const TextStyle(fontSize: 12, color: AppColors.teal)),
                  ],
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SVTextButton(
                        label: assist.busy ? strings.verifying : strings.verifyEngine,
                        onPressed: assist.busy ? null : () => assist.verify(bridge),
                      ),
                      SVTextButton(
                        label: strings.copyDiagnostic,
                        onPressed: assist.busy
                            ? null
                            : () => assist.copyDiagnostic(bridge, strings),
                      ),
                      SVTextButton(
                        label: strings.chooseAnother,
                        primary: true,
                        onPressed: () {
                          assist.close();
                          onPickAnother();
                        },
                      ),
                      SVTextButton(label: strings.close, onPressed: assist.close),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
