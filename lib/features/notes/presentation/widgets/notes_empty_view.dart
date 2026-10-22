import 'package:flutter/material.dart';
import '../../../../core/theme/spacing.dart';

class NotesEmptyView extends StatelessWidget {
  final bool isSearch;
  final String? customTitle;
  final String? customSubtitle;
  final IconData? icon;

  const NotesEmptyView({
    super.key,
    this.isSearch = false,
    this.customTitle,
    this.customSubtitle,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final defaultIcon = isSearch ? Icons.search_off_outlined : Icons.shield_outlined;
    final defaultTitle = isSearch ? 'No matching notes' : 'No notes yet';
    final defaultSubtitle = isSearch
        ? 'Try searching with different terms or check for typos.'
        : 'Tap the + button below to create your first encrypted note.';

    return Center(
      child: Padding(
        padding: AppSpacing.paddingXxl,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon ?? defaultIcon,
                size: 40,
                color: theme.colorScheme.primary,
              ),
            ),
            AppSpacing.vGapXl,
            Text(
              customTitle ?? defaultTitle,
              style: textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            AppSpacing.vGapSm,
            Text(
              customSubtitle ?? defaultSubtitle,
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
