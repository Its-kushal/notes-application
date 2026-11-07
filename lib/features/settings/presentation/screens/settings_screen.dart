import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/crypto/vault_service.dart';
import '../../../../core/database/benchmark_seeder.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/shared_widgets.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../locked_notes/presentation/controllers/vault_providers.dart';
import '../../../locked_notes/presentation/widgets/reset_vault_dialog.dart';
import '../../../notes/domain/note_sort.dart';
import '../../../notes/presentation/controllers/notes_providers.dart';
import '../controllers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    final l10n = contextL10n(context);
    final currentTheme = ref.read(settingsProvider).settings.themeMode;
    SelectionDialog.show<ThemeMode>(
      context: context,
      title: l10n.theme,
      selectedValue: currentTheme,
      items: [
        SelectionItem(title: l10n.themeSystem, value: ThemeMode.system),
        SelectionItem(title: l10n.themeLight, value: ThemeMode.light),
        SelectionItem(title: l10n.themeDark, value: ThemeMode.dark),
      ],
      onSelected: (mode) => ref.read(settingsProvider.notifier).setThemeMode(mode),
    );
  }

  void _showFontScaleDialog(BuildContext context, WidgetRef ref) {
    final l10n = contextL10n(context);
    final currentScale = ref.read(settingsProvider).settings.fontSizeMultiplier;
    SelectionDialog.show<double>(
      context: context,
      title: l10n.fontSizeMultiplier,
      selectedValue: currentScale,
      items: [
        SelectionItem(title: l10n.smallFont, value: 0.85),
        SelectionItem(title: l10n.defaultFont, value: 1.0),
        SelectionItem(title: l10n.largeFont, value: 1.15),
        SelectionItem(title: l10n.extraLargeFont, value: 1.3),
      ],
      onSelected: (val) => ref.read(settingsProvider.notifier).setFontSizeMultiplier(val),
    );
  }

  void _showSortDialog(BuildContext context, WidgetRef ref) {
    final l10n = contextL10n(context);
    final settings = ref.read(settingsProvider).settings;
    SelectionDialog.showSectioned(
      context: context,
      title: l10n.defaultSort,
      sections: [
        SelectionSection<NoteSortField>(
          title: l10n.sortField,
          selectedValue: settings.defaultSortField,
          items: [
            SelectionItem(title: l10n.lastEdited, value: NoteSortField.modified),
            SelectionItem(title: l10n.dateCreated, value: NoteSortField.created),
            SelectionItem(title: l10n.sortFieldTitle, value: NoteSortField.title),
          ],
          onSelected: (f) => ref.read(settingsProvider.notifier).setDefaultSortField(f),
        ),
        SelectionSection<NoteSortOrder>(
          title: l10n.order,
          selectedValue: settings.defaultSortOrder,
          items: [
            SelectionItem(title: l10n.ascending, value: NoteSortOrder.ascending),
            SelectionItem(title: l10n.descending, value: NoteSortOrder.descending),
          ],
          onSelected: (o) => ref.read(settingsProvider.notifier).setDefaultSortOrder(o),
        ),
      ],
    );
  }

  void _showRetentionDialog(BuildContext context, WidgetRef ref) {
    final l10n = contextL10n(context);
    final currentDays = ref.read(settingsProvider).settings.trashRetentionDays;
    SelectionDialog.show<int>(
      context: context,
      title: l10n.trashRetentionPeriod,
      selectedValue: currentDays,
      items: [
        SelectionItem(title: l10n.daysRetentionCount(7), value: 7),
        SelectionItem(title: l10n.daysRetentionCount(14), value: 14),
        SelectionItem(title: l10n.daysRetentionCountDefault(30), value: 30),
        SelectionItem(title: l10n.daysRetentionCount(60), value: 60),
        SelectionItem(title: l10n.daysRetentionCount(90), value: 90),
      ],
      onSelected: (days) => ref.read(settingsProvider.notifier).setTrashRetentionDays(days),
    );
  }

  void _showAutoLockDialog(BuildContext context, WidgetRef ref) {
    final l10n = contextL10n(context);
    final current = ref.read(vaultProvider).state.autoLockTimeout;
    SelectionDialog.show<String>(
      context: context,
      title: l10n.autoLockTimeout,
      selectedValue: current,
      items: [
        SelectionItem(title: l10n.whenBackgrounded, value: 'background'),
        SelectionItem(title: l10n.immediately, value: 'immediately'),
        SelectionItem(title: l10n.afterOneMinute, value: '1_min'),
        SelectionItem(title: l10n.afterFiveMinutes, value: '5_min'),
        SelectionItem(title: l10n.afterFifteenMinutes, value: '15_min'),
      ],
      onSelected: (val) {
        ref.read(vaultProvider).setAutoLockTimeout(val);
      },
    );
  }

  Future<void> _showResetConfirmationDialog(BuildContext context, WidgetRef ref) async {
    final l10n = contextL10n(context);
    final reset = await ResetVaultDialog.show(context);
    if (reset == true && context.mounted) {
      AppSnackBar.show(context, message: l10n.lockedNotesVaultReset);
    }
  }

  Future<void> _handleChangeSecret(BuildContext context, WidgetRef ref) async {
    final l10n = contextL10n(context);
    final vaultNotifier = ref.read(vaultProvider);
    if (!vaultNotifier.isUnlocked) {
      await context.push('/unlock');
      if (!ref.read(vaultProvider).isUnlocked) return;
    }

    if (context.mounted) {
      final changed = await context.push<bool>('/setup', extra: true);
      if (changed == true && context.mounted) {
        AppSnackBar.show(context, message: l10n.secretChangedSuccessfully);
      }
    }
  }

  Future<void> _handleSwitchCredential(BuildContext context, WidgetRef ref) async {
    final l10n = contextL10n(context);
    final vaultNotifier = ref.read(vaultProvider);
    if (!vaultNotifier.isUnlocked) {
      await context.push('/unlock');
      if (!ref.read(vaultProvider).isUnlocked) return;
    }

    if (context.mounted) {
      final changed = await context.push<bool>('/setup', extra: true);
      if (changed == true && context.mounted) {
        AppSnackBar.show(context, message: l10n.credentialUpdatedSuccessfully);
      }
    }
  }

  Future<void> _handleSeedNotes(BuildContext context, WidgetRef ref) async {
    final l10n = contextL10n(context);
    AppSnackBar.show(context, message: l10n.seedingProgress);
    final appDb = ref.read(appDatabaseProvider);
    await BenchmarkSeeder.seed5000Notes(appDb);
    await ref.read(notesListProvider).loadNotes();
    if (context.mounted) {
      AppSnackBar.show(context, message: l10n.seedingSuccess);
    }
  }

  Future<void> _handlePurgeNotes(BuildContext context, WidgetRef ref) async {
    final l10n = contextL10n(context);
    final appDb = ref.read(appDatabaseProvider);
    await BenchmarkSeeder.purgeSeededNotes(appDb);
    await ref.read(notesListProvider).loadNotes();
    if (context.mounted) {
      AppSnackBar.show(context, message: l10n.purgingSuccess);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(vaultProvider).loadVaultState();
    });
    final settingsNotifier = ref.watch(settingsProvider);
    final settings = settingsNotifier.settings;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final l10n = contextL10n(context);

    String themeLabel = l10n.themeSystem;
    switch (settings.themeMode) {
      case ThemeMode.light:
        themeLabel = l10n.themeLight;
        break;
      case ThemeMode.dark:
        themeLabel = l10n.themeDark;
        break;
      case ThemeMode.system:
        themeLabel = l10n.themeSystem;
        break;
    }

    String sortLabel = settings.defaultSortField == NoteSortField.modified
        ? l10n.lastEdited
        : (settings.defaultSortField == NoteSortField.created
            ? l10n.dateCreated
            : l10n.sortFieldTitle);
    sortLabel += ' (${settings.defaultSortOrder == NoteSortOrder.ascending ? l10n.ascending : l10n.descending})';

    String fontScaleLabel = l10n.defaultFont;
    if (settings.fontSizeMultiplier == 0.85) fontScaleLabel = l10n.smallFont;
    if (settings.fontSizeMultiplier == 1.15) fontScaleLabel = l10n.largeFont;
    if (settings.fontSizeMultiplier == 1.3) fontScaleLabel = l10n.extraLargeFont;

    final vaultState = ref.watch(vaultProvider).state;
    String autoLockLabel = l10n.whenBackgrounded;
    switch (vaultState.autoLockTimeout) {
      case 'immediately':
        autoLockLabel = l10n.immediately;
        break;
      case '1_min':
        autoLockLabel = l10n.afterOneMinute;
        break;
      case '5_min':
        autoLockLabel = l10n.afterFiveMinutes;
        break;
      case '15_min':
        autoLockLabel = l10n.afterFifteenMinutes;
        break;
      default:
        autoLockLabel = l10n.whenBackgrounded;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: ListView(
        children: [
          SectionHeader(title: l10n.appearanceSection),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(l10n.theme),
            subtitle: Text(themeLabel),
            onTap: () => _showThemeDialog(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.format_size_outlined),
            title: Text(l10n.fontSizeMultiplier),
            subtitle: Text(fontScaleLabel),
            onTap: () => _showFontScaleDialog(context, ref),
          ),
          const Divider(),
          SectionHeader(title: l10n.notesAndDisplaySection),
          ListTile(
            leading: const Icon(Icons.sort_outlined),
            title: Text(l10n.defaultSort),
            subtitle: Text(sortLabel),
            onTap: () => _showSortDialog(context, ref),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.schedule_outlined),
            title: Text(l10n.showTimestamps),
            subtitle: Text(l10n.showTimestampsSubtitle),
            value: settings.showTimestamps,
            onChanged: (val) {
              ref.read(settingsProvider.notifier).setShowTimestamps(val);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notes_outlined),
            title: Text(l10n.showWordCount),
            subtitle: Text(l10n.showWordCountSubtitle),
            value: settings.showWordCount,
            onChanged: (val) {
              ref.read(settingsProvider.notifier).setShowWordCount(val);
            },
          ),
          const Divider(),
          SectionHeader(title: l10n.trashAndStorageSection),
          ListTile(
            leading: const Icon(Icons.auto_delete_outlined),
            title: Text(l10n.trashRetention),
            subtitle: Text(l10n.trashRetentionSubtitle(settings.trashRetentionDays)),
            onTap: () => _showRetentionDialog(context, ref),
          ),
          const Divider(),
          SectionHeader(title: l10n.securitySection),
          if (vaultState.hasVault && vaultState.isDelayedResetRequested) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
              padding: const EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: vaultState.isDelayedResetReady
                    ? AppColors.error.withValues(alpha: isDark ? 0.25 : 0.1)
                    : AppColors.warning.withValues(alpha: isDark ? 0.25 : 0.1),
                borderRadius: BorderRadius.circular(Spacing.sm),
                border: Border.all(
                  color: vaultState.isDelayedResetReady ? AppColors.error : AppColors.warning,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: vaultState.isDelayedResetReady ? AppColors.error : AppColors.warning,
                        size: 20,
                      ),
                      const SizedBox(width: Spacing.xs),
                      Expanded(
                        child: Text(
                          vaultState.isDelayedResetReady
                              ? l10n.vaultResetReadyToComplete
                              : l10n.vaultResetRequestedOn(
                                  vaultState.delayedResetRequestedAt?.toLocal().toString().split('.')[0] ?? '',
                                ),
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: vaultState.isDelayedResetReady ? AppColors.error : AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!vaultState.isDelayedResetReady) ...[
                    const SizedBox(height: Spacing.xs),
                    Text(
                      l10n.timeRemaining(
                        '${vaultState.delayedResetRemainingSeconds ~/ 3600}h ${(vaultState.delayedResetRemainingSeconds % 3600) ~/ 60}m ${vaultState.delayedResetRemainingSeconds % 60}s',
                      ),
                      style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: Spacing.xs),
                  TextButton(
                    onPressed: () => _showResetConfirmationDialog(context, ref),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: Text(
                      vaultState.isDelayedResetReady ? l10n.completeResetNow : l10n.manageCancelResetRequest,
                      style: textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!vaultState.hasVault)
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(l10n.setUpLockedNotes),
              subtitle: Text(l10n.setUpLockedNotesSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/setup'),
            )
          else ...[
            if (!vaultState.hasRecoveryKey) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
                padding: const EdgeInsets.all(Spacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: isDark ? 0.25 : 0.1),
                  borderRadius: BorderRadius.circular(Spacing.sm),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        l10n.noRecoveryKeyWarning,
                        style: textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.key, color: AppColors.primary),
                title: Text(l10n.createRecoveryKey),
                subtitle: Text(l10n.createRecoveryKeySubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await context.push('/vault/recovery-key', extra: false);
                  ref.read(vaultProvider).loadVaultState();
                },
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: Text(l10n.generateNewRecoveryKey),
                subtitle: Text(l10n.generateNewRecoveryKeySubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await context.push('/vault/recovery-key', extra: true);
                  ref.read(vaultProvider).loadVaultState();
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.lock_clock_outlined),
              title: Text(l10n.autoLockTimeout),
              subtitle: Text(autoLockLabel),
              onTap: () => _showAutoLockDialog(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: Text(l10n.changeSecret),
              subtitle: Text(l10n.changeSecretSubtitle(vaultState.credentialType.name.toUpperCase())),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _handleChangeSecret(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_outlined),
              title: Text(l10n.switchCredentialType),
              subtitle: Text(
                l10n.currentCredential(vaultState.credentialType == CredentialType.pin ? 'PIN' : 'Pattern'),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _handleSwitchCredential(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: AppColors.error),
              title: Text(
                l10n.resetLockedNotes,
                style: textTheme.bodyLarge?.copyWith(color: AppColors.error),
              ),
              subtitle: Text(l10n.permanentlyDeleteVaultSubtitle),
              onTap: () => _showResetConfirmationDialog(context, ref),
            ),
          ],
          const Divider(),
          SectionHeader(title: l10n.fileHandlingSection),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: Text(l10n.openTextMarkdownFiles),
            subtitle: Text(l10n.fileHandlingExplanation),
            isThreeLine: true,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.xs),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.settings_outlined),
                label: Text(l10n.openDefaultAppsSettings),
                onPressed: () async {
                  try {
                    const channel = MethodChannel('com.privacynotes.app/security');
                    await channel.invokeMethod('openDefaultAppsSettings');
                  } catch (_) {}
                },
              ),
            ),
          ),
          const Divider(),
          SectionHeader(title: l10n.informationSection),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.aboutPrivacyNotes),
            subtitle: Text(l10n.aboutSubtitle('1.0.0')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/about'),
          ),
          if (kDebugMode) ...[
            const Divider(),
            SectionHeader(title: l10n.debugPerformanceSeeder),
            ListTile(
              leading: const Icon(Icons.speed, color: AppColors.primary),
              title: Text(l10n.seed5000Notes),
              subtitle: Text(l10n.insert5000BenchmarkNotes),
              trailing: const Icon(Icons.play_arrow_outlined),
              onTap: () => _handleSeedNotes(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined, color: AppColors.error),
              title: Text(
                l10n.purgeSeededNotes,
                style: textTheme.bodyMedium?.copyWith(color: AppColors.error),
              ),
              subtitle: Text(l10n.remove5000BenchmarkNotes),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _handlePurgeNotes(context, ref),
            ),
          ],
          AppSpacing.vGapLg,
        ],
      ),
    );
  }
}
