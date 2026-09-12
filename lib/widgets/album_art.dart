import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AlbumArt extends StatelessWidget {
  final int gradientId;
  final double size;
  final double borderRadius;
  final bool showShadow;
  final IconData? overlayIcon;
  final String? imageUrl;

  const AlbumArt({
    super.key,
    required this.gradientId,
    this.size = 120,
    this.borderRadius = 16,
    this.showShadow = true,
    this.overlayIcon,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.getGradientForId(gradientId);
    final hasNetworkImage = imageUrl != null && imageUrl!.trim().isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: colors[0].withValues(alpha: 0.35),
                  blurRadius: 15,
                  spreadRadius: -3,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Base gradient artwork (always serves as vibrant fallback)
            Container(
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
                        color: Colors.white.withValues(alpha: 0.06),
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
                        color: Colors.black.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  // Central subtle music icon
                  Center(
                    child: Icon(
                      overlayIcon ?? Icons.music_note_rounded,
                      color: Colors.white.withValues(alpha: 0.20),
                      size: size * 0.32,
                    ),
                  ),
                ],
              ),
            ),

            // High-res Online Network Artwork
            if (hasNetworkImage)
              Image.network(
                imageUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  // Gracefully falls back to gradient underneath
                  return const SizedBox.shrink();
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return AnimatedOpacity(
                    opacity: 0.4,
                    duration: const Duration(milliseconds: 200),
                    child: child,
                  );
                },
              ),

            // Thin glassy overlay border
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 0.8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
