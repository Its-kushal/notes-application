import 'package:flutter/material.dart';
import '../theme/spacing.dart';

/// Clean, accessible section header styled using typography and AppSpacing.
class SectionHeader extends StatelessWidget {
  final String title;
  final EdgeInsetsGeometry padding;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.xl,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.xs,
    ),
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
