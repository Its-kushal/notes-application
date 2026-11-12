import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/shared_widgets.dart';
import '../../../../l10n/l10n_extension.dart';
import '../controllers/backup_provider.dart';

class BackupSettingsScreen extends ConsumerWidget {
  const BackupSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = contextL10n(context);
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final backupNotifier = ref.watch(backupProvider);
    final state = backupNotifier.state;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.backupAndRestore),
      ),
      body: state.isLoading
          ? Center(
              child: LoadingState(message: state.statusMessage ?? l10n.backupCreating),
            )
          : ListView(
              children: [
                // Status Header Card
                Container(
                  margin: AppSpacing.paddingMd,
                  padding: AppSpacing.paddingLg,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: AppSpacing.borderRadiusMd,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.cloud_off_rounded,
                          color: AppColors.primary,
                          size: 28,
                        ),
                      ),
                      AppSpacing.hGapMd,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.lastBackupDate == null
                                  ? l10n.lastBackupNever
                                  : l10n.lastBackupLabel(
                                      DateFormat.yMMMd().add_jm().format(state.lastBackupDate!),
                                    ),
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            AppSpacing.vGapXs,
                            Text(
                              l10n.backupAndRestoreSubtitle,
                              style: textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                SectionHeader(title: l10n.backupSectionHeader),
                ListTile(
                  leading: const Icon(Icons.save_alt_rounded, color: AppColors.primary),
                  title: Text(l10n.backupNow),
                  subtitle: Text(l10n.backupNowSubtitle),
                  onTap: () => backupNotifier.performSafBackup(context),
                ),
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: Text(l10n.shareBackupAction),
                  subtitle: Text(l10n.backupShareTitle),
                  onTap: () => backupNotifier.shareBackup(context),
                ),

                const Divider(),
                SectionHeader(title: l10n.restoreSectionHeader),
                ListTile(
                  leading: const Icon(Icons.restore_page_outlined, color: AppColors.primary),
                  title: Text(l10n.restoreBackup),
                  subtitle: Text(l10n.restoreBackupSubtitle),
                  onTap: () => backupNotifier.performRestore(context),
                ),

                const Divider(),
                SectionHeader(title: l10n.backupReminderTitle),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: Text(l10n.backupReminderTitle),
                  subtitle: Text(l10n.backupReminderSubtitle),
                  value: state.isReminderEnabled,
                  onChanged: (val) => backupNotifier.toggleReminder(val),
                ),

                const Divider(),
                SectionHeader(title: l10n.about),
                Padding(
                  padding: AppSpacing.paddingLg,
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppSpacing.borderRadiusMd,
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: AppSpacing.paddingLg,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.lock_outline, color: AppColors.primary, size: 20),
                              AppSpacing.hGapSm,
                              Text(
                                l10n.backupAboutArchitectureTitle,
                                style: textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          AppSpacing.vGapSm,
                          Text(
                            l10n.backupAboutArchitectureDesc,
                            style: textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                AppSpacing.vGapLg,
              ],
            ),
    );
  }
}
