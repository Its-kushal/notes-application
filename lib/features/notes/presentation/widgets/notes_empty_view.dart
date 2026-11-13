import 'package:flutter/material.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../l10n/l10n_extension.dart';

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

    final l10n = contextL10n(context);
    final defaultIcon = isSearch ? Icons.search_off_outlined : Icons.shield_outlined;
    final defaultTitle = isSearch ? l10n.noSearchResultsTitle : l10n.noNotesTitle;
    final defaultSubtitle = isSearch
        ? l10n.noSearchResultsMessage
        : l10n.noNotesMessage;

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
