import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A rounded card with optional glassmorphism blur.
///
/// **Performance note:** Pass [blurSigma] = 0 (or leave it unset and set
/// [noBlur] = true) to skip the [BackdropFilter] entirely and render a plain
/// opaque surface. Do this for any card that sits on top of moving content
/// (scrolling lists, playing animations) to avoid expensive per-frame GPU
/// blur recomposition.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;

  /// Set to 0 to disable BackdropFilter completely (best for MiniPlayer,
  /// BottomNav, or any card over frequently-repainting content).
  final double blurSigma;

  final Color? color;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.blurSigma = 12,
    this.color,
    this.borderColor,
    this.padding,
    this.margin,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.glassBackground,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? AppColors.glassBorder,
          width: 1.0,
        ),
      ),
      child: child,
    );

    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: AppColors.glassShadow,
            blurRadius: 15,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        // Only pay the BackdropFilter GPU cost when blur is actually needed.
        child: blurSigma > 0
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: inner,
              )
            : inner,
      ),
    );
  }
}
