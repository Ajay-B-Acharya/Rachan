import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF101113);
  static const Color backgroundSurface = Color(0xFF1C1D21);
  static const Color accent = Color(0xFFBBAAFF);
  static const Color accentLight = Color(0xFFD7CCFF);
  static const Color heartColor = Color(0xFFF28EAA);

  static final Color glassBackground = Colors.white.withValues(alpha: 0.04);
  static final Color glassBorder = Colors.white.withValues(alpha: 0.08);
  static final Color glassShadow = Colors.black.withValues(alpha: 0.18);

  static const Color textPrimary = Color(0xFFF4F2EE);
  static const Color textSecondary = Color(0xFFABAAB2);
  static const Color textMuted = Color(0xFF85848E);

  static const List<Color> gradientSunset = [
    Color(0xFF9B665A),
    Color(0xFF4E3544),
  ];
  static const List<Color> gradientOcean = [
    Color(0xFF567F87),
    Color(0xFF253842),
  ];
  static const List<Color> gradientVapor = [
    Color(0xFF8A7BB0),
    Color(0xFF39304E),
  ];
  static const List<Color> gradientEmerald = [
    Color(0xFF748C78),
    Color(0xFF2B403A),
  ];
  static const List<Color> gradientMidnight = [
    Color(0xFF4C5878),
    Color(0xFF222A3C),
  ];
  static const List<Color> gradientFiery = [
    Color(0xFFB19361),
    Color(0xFF54412D),
  ];
  static const List<Color> gradientAmethyst = [
    Color(0xFF956D88),
    Color(0xFF442D48),
  ];
  static const List<Color> gradientAura = [
    Color(0xFFAD9188),
    Color(0xFF575060),
  ];

  static const List<List<Color>> allGradients = [
    gradientVapor,
    gradientOcean,
    gradientSunset,
    gradientEmerald,
    gradientMidnight,
    gradientFiery,
    gradientAmethyst,
    gradientAura,
  ];

  static List<Color> getGradientForId(int id) =>
      allGradients[id % allGradients.length];
}
