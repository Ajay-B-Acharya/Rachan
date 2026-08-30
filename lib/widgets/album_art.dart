import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AlbumArt extends StatelessWidget {
  final int gradientId;
  final double size;
  final double borderRadius;
  final bool showShadow;
  final IconData? overlayIcon;

  const AlbumArt({
    super.key,
    required this.gradientId,
    this.size = 120,
    this.borderRadius = 16,
    this.showShadow = true,
    this.overlayIcon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.getGradientForId(gradientId);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: colors[0].withOpacity(0.35),
                  blurRadius: 15,
                  spreadRadius: -3,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
          ),
          child: Stack(
            children: [
              // Subtle circular overlays inside the art
              Positioned(
                top: -size * 0.25,
                left: -size * 0.25,
                child: Container(
                  width: size * 0.7,
                  height: size * 0.7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
              ),
              Positioned(
                bottom: -size * 0.15,
                right: -size * 0.15,
                child: Container(
                  width: size * 0.6,
                  height: size * 0.6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.12),
                  ),
                ),
              ),
              // Central subtle music icon
              Center(
                child: Icon(
                  overlayIcon ?? Icons.music_note_rounded,
                  color: Colors.white.withOpacity(0.20),
                  size: size * 0.32,
                ),
              ),
              // Thin overlay border
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.10),
                    width: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
