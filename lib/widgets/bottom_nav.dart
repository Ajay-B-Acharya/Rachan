import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'glass_card.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNav({super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        color: Colors.transparent,
        child: GlassCard(
          borderRadius: 24,
          blurSigma: 0, // no BackdropFilter — sits over PageView content
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          color: const Color(0xFF0F0F1A),
          borderColor: Colors.white.withValues(alpha: 0.10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tabWidth = constraints.maxWidth / 4;
              return Stack(
                children: [
                  // Animated sliding pill background for active tab
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    left: currentIndex * tabWidth,
                    top: 2,
                    bottom: 2,
                    width: tabWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.accent.withValues(alpha: 0.25),
                            AppColors.accent.withValues(alpha: 0.12),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.accentLight.withValues(alpha: 0.35),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.2),
                            blurRadius: 10,
                            spreadRadius: -2,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Navigation items
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNavItem(
                        context,
                        index: 0,
                        icon: Icons.home_rounded,
                        selectedIcon: Icons.home_rounded,
                        label: "Home",
                        width: tabWidth,
                      ),
                      _buildNavItem(
                        context,
                        index: 1,
                        icon: Icons.search_rounded,
                        selectedIcon: Icons.search_rounded,
                        label: "Search",
                        width: tabWidth,
                      ),
                      _buildNavItem(
                        context,
                        index: 2,
                        icon: Icons.library_music_outlined,
                        selectedIcon: Icons.library_music_rounded,
                        label: "Library",
                        width: tabWidth,
                      ),
                      _buildNavItem(
                        context,
                        index: 3,
                        icon: Icons.phone_android_rounded,
                        selectedIcon: Icons.phone_android_rounded,
                        label: "Local",
                        width: tabWidth,
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required double width,
  }) {
    final isSelected = currentIndex == index;
    final color = isSelected ? AppColors.accentLight : AppColors.textSecondary;

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: Icon(
                  isSelected ? selectedIcon : icon,
                  color: color,
                  size: 23,
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: isSelected ? 0.3 : 0.0,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
