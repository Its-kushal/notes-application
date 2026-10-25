import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/crypto/vault_service.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/shared_widgets.dart';
import '../../../locked_notes/presentation/controllers/vault_providers.dart';
import '../../../notes/domain/note_sort.dart';
import '../controllers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    final currentTheme = ref.read(settingsProvider).settings.themeMode;
    SelectionDialog.show<ThemeMode>(
      context: context,
      title: 'Theme',
      selectedValue: currentTheme,
      items: const [
        SelectionItem(title: 'System default', value: ThemeMode.system),
        SelectionItem(title: 'Light', value: ThemeMode.light),
        SelectionItem(title: 'Dark', value: ThemeMode.dark),
      ],
      onSelected: (mode) => ref.read(settingsProvider.notifier).setThemeMode(mode),
    );
  }

  void _showFontScaleDialog(BuildContext context, WidgetRef ref) {
    final currentScale = ref.read(settingsProvider).settings.fontSizeMultiplier;
    SelectionDialog.show<double>(
      context: context,
      title: 'Font size multiplier',
      selectedValue: currentScale,
      items: const [
        SelectionItem(title: 'Small (85%)', value: 0.85),
        SelectionItem(title: 'Default (100%)', value: 1.0),
        SelectionItem(title: 'Large (115%)', value: 1.15),
        SelectionItem(title: 'Extra Large (130%)', value: 1.3),
      ],
      onSelected: (val) => ref.read(settingsProvider.notifier).setFontSizeMultiplier(val),
    );
  }

  void _showSortDialog(BuildContext context, WidgetRef ref) {
    final settings = ref.read(settingsProvider).settings;
    SelectionDialog.showSectioned(
      context: context,
      title: 'Default sorting',
      sections: [
        SelectionSection<NoteSortField>(
          title: 'Sort field',
          selectedValue: settings.defaultSortField,
          items: const [
            SelectionItem(title: 'Last edited', value: NoteSortField.modified),
            SelectionItem(title: 'Date created', value: NoteSortField.created),
            SelectionItem(title: 'Title', value: NoteSortField.title),
          ],
          onSelected: (f) => ref.read(settingsProvider.notifier).setDefaultSortField(f),
        ),
        SelectionSection<NoteSortOrder>(
          title: 'Order',
          selectedValue: settings.defaultSortOrder,
          items: const [
            SelectionItem(title: 'Ascending', value: NoteSortOrder.ascending),
            SelectionItem(title: 'Descending', value: NoteSortOrder.descending),
          ],
          onSelected: (o) => ref.read(settingsProvider.notifier).setDefaultSortOrder(o),
        ),
      ],
    );
  }

  void _showRetentionDialog(BuildContext context, WidgetRef ref) {
    final currentDays = ref.read(settingsProvider).settings.trashRetentionDays;
    SelectionDialog.show<int>(
      context: context,
      title: 'Trash retention period',
      selectedValue: currentDays,
      items: const [
        SelectionItem(title: '7 days', value: 7),
        SelectionItem(title: '14 days', value: 14),
        SelectionItem(title: '30 days (Default)', value: 30),
        SelectionItem(title: '60 days', value: 60),
        SelectionItem(title: '90 days', value: 90),
      ],
      onSelected: (days) => ref.read(settingsProvider.notifier).setTrashRetentionDays(days),
    );
  }

  void _showAutoLockDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(vaultProvider).state.autoLockTimeout;
    SelectionDialog.show<String>(
      context: context,
      title: 'Auto-lock timeout',
      selectedValue: current,
      items: const [
        SelectionItem(title: 'When backgrounded (Default)', value: 'background'),
        SelectionItem(title: 'Immediately', value: 'immediately'),
        SelectionItem(title: 'After 1 minute', value: '1_min'),
        SelectionItem(title: 'After 5 minutes', value: '5_min'),
        SelectionItem(title: 'After 15 minutes', value: '15_min'),
      ],
      onSelected: (val) {
        ref.read(vaultProvider).setAutoLockTimeout(val);
      },
    );
  }

  void _showResetConfirmationDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isMatch = controller.text.trim() == 'DELETE';
            return AlertDialog(
              title: const Text('Reset locked notes?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This will PERMANENTLY DELETE all locked notes and the vault. Unlocked notes will not be affected.\n\nType DELETE to confirm:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: Spacing.sm),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'DELETE',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isMatch
                      ? () async {
                          Navigator.of(dialogCtx).pop(true);
                          await ref.read(vaultProvider).resetVault();
                          if (context.mounted) {
                            AppSnackBar.show(context, message: 'Locked notes and vault reset');
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: AppColors.white,
                  ),
                  child: const Text('Delete Everything'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleChangeSecret(BuildContext context, WidgetRef ref) async {
    final vaultNotifier = ref.read(vaultProvider);
    if (!vaultNotifier.isUnlocked) {
      await context.push('/unlock');
      if (!ref.read(vaultProvider).isUnlocked) return;
    }

    if (context.mounted) {
      final changed = await context.push<bool>('/setup', extra: true);
      if (changed == true && context.mounted) {
        AppSnackBar.show(context, message: 'Secret changed successfully');
      }
    }
  }

  Future<void> _handleSwitchCredential(BuildContext context, WidgetRef ref) async {
    final vaultNotifier = ref.read(vaultProvider);
    if (!vaultNotifier.isUnlocked) {
      await context.push('/unlock');
      if (!ref.read(vaultProvider).isUnlocked) return;
    }

    if (context.mounted) {
      final changed = await context.push<bool>('/setup', extra: true);
      if (changed == true && context.mounted) {
        AppSnackBar.show(context, message: 'Credential type updated successfully');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(vaultProvider).loadVaultState();
    });
    final settingsNotifier = ref.watch(settingsProvider);
    final settings = settingsNotifier.settings;

    String themeLabel = 'System default';
    switch (settings.themeMode) {
      case ThemeMode.light:
        themeLabel = 'Light';
        break;
      case ThemeMode.dark:
        themeLabel = 'Dark';
        break;
      case ThemeMode.system:
        themeLabel = 'System default';
        break;
    }

    String sortLabel = settings.defaultSortField == NoteSortField.modified
        ? 'Last edited'
        : (settings.defaultSortField == NoteSortField.created
            ? 'Date created'
            : 'Title');
    sortLabel += ' (${settings.defaultSortOrder == NoteSortOrder.ascending ? "Ascending" : "Descending"})';

    String fontScaleLabel = 'Default (100%)';
    if (settings.fontSizeMultiplier == 0.85) fontScaleLabel = 'Small (85%)';
    if (settings.fontSizeMultiplier == 1.15) fontScaleLabel = 'Large (115%)';
    if (settings.fontSizeMultiplier == 1.3) fontScaleLabel = 'Extra Large (130%)';

    final vaultState = ref.watch(vaultProvider).state;
    String autoLockLabel = 'When backgrounded (Default)';
    switch (vaultState.autoLockTimeout) {
      case 'immediately':
        autoLockLabel = 'Immediately';
        break;
      case '1_min':
        autoLockLabel = 'After 1 minute';
        break;
      case '5_min':
        autoLockLabel = 'After 5 minutes';
        break;
      case '15_min':
        autoLockLabel = 'After 15 minutes';
        break;
      default:
        autoLockLabel = 'When backgrounded (Default)';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const SectionHeader(title: 'Appearance'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Theme'),
            subtitle: Text(themeLabel),
            onTap: () => _showThemeDialog(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.format_size_outlined),
            title: const Text('Font size multiplier'),
            subtitle: Text(fontScaleLabel),
            onTap: () => _showFontScaleDialog(context, ref),
          ),
          const Divider(),
          const SectionHeader(title: 'Notes & Display'),
          ListTile(
            leading: const Icon(Icons.sort_outlined),
            title: const Text('Default sort'),
            subtitle: Text(sortLabel),
            onTap: () => _showSortDialog(context, ref),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.schedule_outlined),
            title: const Text('Show timestamps'),
            subtitle: const Text('Display note creation and update times on cards and editor'),
            value: settings.showTimestamps,
            onChanged: (val) {
              ref.read(settingsProvider.notifier).setShowTimestamps(val);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notes_outlined),
            title: const Text('Show word count'),
            subtitle: const Text('Display word and checklist text counts'),
            value: settings.showWordCount,
            onChanged: (val) {
              ref.read(settingsProvider.notifier).setShowWordCount(val);
            },
          ),
          const Divider(),
          const SectionHeader(title: 'Trash & Storage'),
          ListTile(
            leading: const Icon(Icons.auto_delete_outlined),
            title: const Text('Trash retention'),
            subtitle: Text('${settings.trashRetentionDays} days (auto-purge expired notes)'),
            onTap: () => _showRetentionDialog(context, ref),
          ),
          const Divider(),
          const SectionHeader(title: 'Security'),
          if (!vaultState.hasVault)
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Set up locked notes'),
              subtitle: const Text('Protect sensitive notes with a PIN or pattern'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/setup'),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.lock_clock_outlined),
              title: const Text('Auto-lock timeout'),
              subtitle: Text(autoLockLabel),
              onTap: () => _showAutoLockDialog(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: const Text('Change secret'),
              subtitle: Text('Change your current ${vaultState.credentialType.name.toUpperCase()}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _handleChangeSecret(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_outlined),
              title: const Text('Switch credential type'),
              subtitle: Text('Current: ${vaultState.credentialType == CredentialType.pin ? "PIN" : "Pattern"}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _handleSwitchCredential(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: AppColors.error),
              title: const Text(
                'Reset locked notes',
                style: TextStyle(color: AppColors.error),
              ),
              subtitle: const Text('Permanently delete all locked notes and vault'),
              onTap: () => _showResetConfirmationDialog(context, ref),
            ),
          ],
          const Divider(),
          const SectionHeader(title: 'Information'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About Privacy Notes'),
            subtitle: const Text('Version 1.0.0 • Local-first & offline privacy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/about'),
          ),
          AppSpacing.vGapLg,
        ],
      ),
    );
  }
}
