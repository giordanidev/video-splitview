/// Tokens de design (porte de `src/style.css`) e tema Material.
library;

import 'package:flutter/material.dart';

class AppColors {
  const AppColors._();

  static const Color shell = Color(0xFF090C0F);
  static const Color bg = Color(0xFF070A0D);
  static const Color panel = Color(0xFF101519);
  static const Color panel2 = Color(0xFF161D23);
  static const Color panel3 = Color(0xFF1D252D);
  static const Color line = Color(0x17FFFFFF);
  static const Color lineStrong = Color(0x2EFFFFFF);
  static const Color text = Color(0xFFE9EEF3);
  static const Color muted = Color(0xFF8C9AA6);
  static const Color accent = Color(0xFFE8A33D);
  static const Color accentSoft = Color(0x29E8A33D);
  static const Color teal = Color(0xFF3FB8A0);
  static const Color danger = Color(0xFFFF8F6B);
  static const Color track = Color(0x24FFFFFF);
}

class AppFonts {
  const AppFonts._();

  static const String display = 'Inter';
  static const String body = 'Inter';
  static const String mono = 'JetBrainsMono';
}

class AppTheme {
  const AppTheme._();

  static ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);
    final scheme = const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: Color(0xFF1A1206),
      secondary: AppColors.teal,
      surface: AppColors.panel,
      onSurface: AppColors.text,
      error: AppColors.danger,
      onError: Color(0xFF210c06),
      outline: AppColors.lineStrong,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.shell,
      colorScheme: scheme,
      textTheme: base.textTheme.apply(
        fontFamily: AppFonts.body,
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration.zero,
        decoration: BoxDecoration(
          color: Color(0xF2161D23),
          borderRadius: BorderRadius.all(Radius.circular(8)),
          border: Border.fromBorderSide(BorderSide(color: AppColors.lineStrong)),
        ),
        textStyle: TextStyle(
          color: AppColors.text,
          fontFamily: AppFonts.body,
          fontSize: 12,
        ),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 4,
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.track,
        thumbColor: AppColors.accent,
        overlayColor: AppColors.accentSoft,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      ),
    );
  }
}
