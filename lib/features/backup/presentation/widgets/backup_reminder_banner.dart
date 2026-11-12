import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../l10n/l10n_extension.dart';
import '../controllers/backup_provider.dart';

class BackupReminderBanner extends ConsumerWidget {
  const BackupReminderBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = contextL10n(context);
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final backupNotifier = ref.watch(backupProvider);
    final state = backupNotifier.state;

    if (!state.shouldShowBanner) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: isDark ? AppColors.charcoal : AppColors.primary.withValues(alpha: 0.08),
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.backup_outlined,
                color: AppColors.primary,
                size: 22,
              ),
              AppSpacing.hGapSm,
              Expanded(
                child: Text(
                  l10n.backupReminderBannerTitle,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: l10n.remindInThreeDays,
                visualDensity: VisualDensity.compact,
                onPressed: () => backupNotifier.snoozeReminder(),
              ),
            ],
          ),
          AppSpacing.vGapXs,
          Text(
            l10n.backupReminderBannerMessage,
            style: textTheme.bodySmall?.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
          AppSpacing.vGapSm,
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => backupNotifier.snoozeReminder(),
                child: Text(l10n.remindInThreeDays),
              ),
              AppSpacing.hGapSm,
              FilledButton(
                onPressed: () => backupNotifier.performSafBackup(context),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(l10n.backupNowButton),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
