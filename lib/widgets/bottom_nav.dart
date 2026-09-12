import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'motion.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNav({super.key, required this.currentIndex, required this.onTap});

  static const _labels = ['Home', 'Search', 'Library', 'Local'];
  static const _icons = [
    Icons.home_outlined,
    Icons.search_rounded,
    Icons.library_music_outlined,
    Icons.phone_android_rounded,
  ];
  static const _selectedIcons = [
    Icons.home_rounded,
    Icons.search_rounded,
    Icons.library_music_rounded,
    Icons.phone_android_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.background,
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: List.generate(4, (index) {
                final selected = index == currentIndex;
                return Expanded(
                  child: Semantics(
                    selected: selected,
                    child: Pressable(
                      onTap: () => onTap(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: motionDuration(context),
                              curve: Curves.easeOutCubic,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.accent.withValues(alpha: 0.13)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                selected
                                    ? _selectedIcons[index]
                                    : _icons[index],
                                size: 23,
                                color: selected
                                    ? AppColors.accent
                                    : AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _labels[index],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? AppColors.textPrimary
                                    : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
