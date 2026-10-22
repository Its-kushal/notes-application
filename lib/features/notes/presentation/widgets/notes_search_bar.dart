import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/spacing.dart';

class NotesSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final Widget? trailing;

  const NotesSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: theme.textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Search notes...',
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark ? AppColors.darkTextHint : AppColors.lightTextHint,
                ),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        color: isDark
                            ? AppColors.darkTextHint
                            : AppColors.lightTextHint,
                        onPressed: onClear,
                        tooltip: 'Clear search',
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                border: OutlineInputBorder(
                  borderRadius: AppSpacing.borderRadiusMd,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (trailing != null) ...[
            AppSpacing.hGapSm,
            trailing!,
          ],
        ],
      ),
    );
  }
}
