/// Widgets comuns (botões, previsções e formatação) alinhados com o design
/// system.
library;

import 'package:flutter/material.dart';

import '../../backend/models/models.dart';
import '../theme/theme.dart';

/// Formata segundos como `m:ss` ou `h:mm:ss`.
String formatTime(double totalSeconds) {
  if (!totalSeconds.isFinite || totalSeconds <= 0) return '0:00';
  final seconds = totalSeconds.floor() % 60;
  final minutes = (totalSeconds ~/ 60) % 60;
  final hours = totalSeconds ~/ 3600;
  String pad(int value) => value.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:${pad(minutes)}:${pad(seconds)}' : '$minutes:${pad(seconds)}';
}

class SVIconButton extends StatelessWidget {
  const SVIconButton({
    super.key,
    required this.child,
    this.onPressed,
    this.active = false,
    this.tooltip,
    this.size = 40,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool active;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final button = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: active ? AppColors.accentSoft : AppColors.panel2,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          borderRadius: BorderRadius.circular(10),
          hoverColor: AppColors.panel3,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? AppColors.accent : AppColors.lineStrong,
              ),
            ),
            child: IconTheme(
              data: IconThemeData(
                size: 19,
                color: active ? AppColors.accent : AppColors.text,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class SVTextButton extends StatelessWidget {
  const SVTextButton({
    super.key,
    required this.label,
    this.onPressed,
    this.primary = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final button = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: primary ? AppColors.accent : AppColors.panel2,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          borderRadius: BorderRadius.circular(10),
          hoverColor: primary ? AppColors.accent : AppColors.panel3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: primary ? AppColors.accent : AppColors.lineStrong,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: primary ? const Color(0xFF1A1206) : AppColors.text,
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Mini-previsualização esquemática de um layout de divisão (grelha de
/// células), partilhada pelas escolhas de layout do rodapé e das definições.
class LayoutPreview extends StatelessWidget {
  const LayoutPreview({super.key, required this.layout, required this.selected});

  final SplitLayout layout;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    const width = 82.0;
    const height = 44.0;
    const inset = 1.5;
    const radius = 3.0;
    final spec = layoutSpec(layout);
    final cellW = width / spec.cols;
    final cellH = height / spec.rows;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(radius + 1),
        border: Border.all(color: AppColors.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            for (final cell in spec.cells)
              Positioned(
                left: cell.col * cellW + inset,
                top: cell.row * cellH + inset,
                width: cell.colSpan * cellW - inset * 2,
                height: cell.rowSpan * cellH - inset * 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.accent.withValues(alpha: 0.55)
                        : AppColors.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(radius),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
