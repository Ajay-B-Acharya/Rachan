import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'glass_card.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNav({super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      color: Colors.transparent,
      child: GlassCard(
        borderRadius: 22,
        blurSigma: 15,
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: Colors.black.withOpacity(0.55),
        borderColor: Colors.white.withOpacity(0.1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(
              context,
              index: 0,
              icon: Icons.home_rounded,
              label: "Home",
            ),
            _buildNavItem(
              context,
              index: 1,
              icon: Icons.search_rounded,
              label: "Search",
            ),
            _buildNavItem(
              context,
              index: 2,
              icon: Icons.library_music_rounded,
              label: "Library",
            ),
            _buildNavItem(
              context,
              index: 3,
              icon: Icons.phone_android_rounded,
              label: "Local",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = currentIndex == index;
    final color = isSelected ? AppColors.accent : AppColors.textSecondary;

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 3),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
