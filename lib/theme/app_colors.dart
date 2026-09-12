import 'package:flutter/material.dart';

class AppColors {
  // Backgrounds
  static const Color background = Color(0xFF08080C);
  static const Color backgroundSurface = Color(0xFF101018);

  // Accent Colors
  static const Color accent = Color(0xFF9E86FF);
  static const Color accentLight = Color(0xFFBFAFFF);
  static const Color heartColor = Color(
    0xFFFF3B30,
  ); // Premium iOS/Spotify red for favorites

  // Glassmorphic Colors
  static final Color glassBackground = Colors.white.withValues(alpha: 0.06);
  static final Color glassBorder = Colors.white.withValues(alpha: 0.10);
  static final Color glassShadow = Colors.black.withValues(alpha: 0.3);

  // Text Colors
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFA0A0B0);
  static const Color textMuted = Color(0xFF606070);

  // Premium Predefined Gradients (for Dynamic Album Artwork and Screen Overlay Backdrops)
  static const List<Color> gradientSunset = [
    Color(0xFFFF512F),
    Color(0xFFDD2476),
  ];
  static const List<Color> gradientOcean = [
    Color(0xFF1A2980),
    Color(0xFF26D0CE),
  ];
  static const List<Color> gradientVapor = [
    Color(0xFF7F00FF),
    Color(0xFFFF007F),
  ];
  static const List<Color> gradientEmerald = [
    Color(0xFF11998e),
    Color(0xFF38ef7d),
  ];
  static const List<Color> gradientMidnight = [
    Color(0xFF0F2027),
    Color(0xFF203A43),
    Color(0xFF2C5364),
  ];
  static const List<Color> gradientFiery = [
    Color(0xFFf12711),
    Color(0xFFf5af19),
  ];
  static const List<Color> gradientAmethyst = [
    Color(0xFF9E2A2B),
    Color(0xFF6A0DAD),
  ];
  static const List<Color> gradientAura = [
    Color(0xFF3A1C71),
    Color(0xFFD76D77),
    Color(0xFFFFAF7B),
  ];

  // List of all gradients to dynamically select from
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

  static List<Color> getGradientForId(int id) {
    return allGradients[id % allGradients.length];
  }
}
