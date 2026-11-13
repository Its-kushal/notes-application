import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/crypto/recovery_key_service.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../locked_notes/presentation/controllers/vault_providers.dart';
import '../../../notes/presentation/controllers/notes_providers.dart';
import '../../domain/backup_manifest.dart';
import '../../services/backup_service.dart';
import '../widgets/link_paper_key_dialog.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  final appDb = ref.watch(appDatabaseProvider);
  return BackupService(appDatabase: appDb);
});

class BackupState {
  final DateTime? lastBackupDate;
  final bool isReminderEnabled;
  final bool isLoading;
  final String? statusMessage;
  final String? errorMessage;
  final bool shouldShowBanner;

  const BackupState({
    this.lastBackupDate,
    this.isReminderEnabled = true,
    this.isLoading = false,
    this.statusMessage,
    this.errorMessage,
    this.shouldShowBanner = false,
  });

  BackupState copyWith({
    DateTime? lastBackupDate,
    bool? isReminderEnabled,
    bool? isLoading,
    String? statusMessage,
    bool clearStatus = false,
    String? errorMessage,
    bool clearError = false,
    bool? shouldShowBanner,
  }) {
    return BackupState(
      lastBackupDate: lastBackupDate ?? this.lastBackupDate,
      isReminderEnabled: isReminderEnabled ?? this.isReminderEnabled,
      isLoading: isLoading ?? this.isLoading,
      statusMessage: clearStatus ? null : (statusMessage ?? this.statusMessage),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      shouldShowBanner: shouldShowBanner ?? this.shouldShowBanner,
    );
  }
}

class BackupNotifier extends ChangeNotifier {
  final Ref ref;
  final BackupService backupService;
  BackupState _state = const BackupState();

  BackupNotifier(this.ref, this.backupService) {
    loadState();
  }

  BackupState get state => _state;

  Future<void> loadState() async {
    try {
      final lastBackup = await backupService.getLastBackupDate();
      final reminderEnabled = await backupService.isBackupReminderEnabled();
      final showBanner = await backupService.shouldShowReminderBanner();

      _state = _state.copyWith(
        lastBackupDate: lastBackup,
        isReminderEnabled: reminderEnabled,
        shouldShowBanner: showBanner,
      );
      notifyListeners();
    } catch (_) {
      // Keep initial/clean state if database is uninitialized or in unit tests
    }
  }

  /// Ensures a backup subkey is available, walking the user through Case 1, 2, or 3 if missing.
  Future<bool> ensureBackupSubkey(BuildContext context) async {
    final hasSubkey = await backupService.hasStoredBackupSubkey();
    if (hasSubkey) return true;

    final vaultState = ref.read(vaultProvider).state;

    if (!vaultState.hasVault) {
      // Case 1: No vault and no backup subkey. Create root recovery key.
      if (!context.mounted) return false;
      final created = await LinkPaperKeyDialog.show(
        context,
        mode: LinkPaperKeyMode.createAndConfirm,
      );
      return created == true;
    } else if (vaultState.hasRecoveryKey) {
      // Case 2: Vault with recovery wrap exists, but no backup subkey (user's phone state).
      if (!context.mounted) return false;
      final linked = await LinkPaperKeyDialog.show(
        context,
        mode: LinkPaperKeyMode.linkExistingVaultKey,
      );
      return linked == true;
    } else {
      // Case 3: Vault exists without recovery wrap. Prompt to create one.
      if (!context.mounted) return false;
      final l10n = contextL10n(context);
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.createRecoveryKeyTitle),
          content: Text(l10n.noRecoveryKeyWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.continueAction),
            ),
          ],
        ),
      );
      if (proceed != true || !context.mounted) return false;

      // Navigate to recovery key screen (Requirement 2)
      final created = await context.push<bool>('/vault/recovery-key', extra: false);
      if (created == true) {
        return await backupService.hasStoredBackupSubkey();
      }
      return false;
    }
  }

  /// Creates and saves a backup via Android Storage Access Framework (SAF).
  Future<bool> performSafBackup(BuildContext context) async {
    final hasKey = await ensureBackupSubkey(context);
    if (!hasKey || !context.mounted) return false;

    final l10n = contextL10n(context);
    _state = _state.copyWith(isLoading: true, statusMessage: l10n.backupCreating);
    notifyListeners();

    try {
      final bytes = await backupService.createBackupBytes();
      final uri = await backupService.saveBackupViaSaf(bytes);

      _state = _state.copyWith(isLoading: false, clearStatus: true);
      notifyListeners();

      if (!context.mounted) return uri != null;

      if (uri != null) {
        await loadState();
        if (context.mounted) {
          AppSnackBar.show(context, message: l10n.backupSuccess);
        }
        return true;
      }
      return false;
    } catch (_) {
      _state = _state.copyWith(
        isLoading: false,
        clearStatus: true,
        errorMessage: l10n.backupFailed,
      );
      notifyListeners();
      if (context.mounted) {
        AppSnackBar.show(context, message: l10n.backupFailed);
      }
      return false;
    }
  }

  /// Stages backup file in cache and opens the system share sheet.
  /// Follows up with a confirmation dialog: "Did you save the file somewhere safe?" (B).
  Future<void> shareBackup(BuildContext context) async {
    final hasKey = await ensureBackupSubkey(context);
    if (!hasKey) return;

    if (!context.mounted) return;
    final l10n = contextL10n(context);
    _state = _state.copyWith(isLoading: true, statusMessage: l10n.backupCreating);
    notifyListeners();

    try {
      final bytes = await backupService.createBackupBytes();
      await backupService.stageAndShareBackup(bytes);

      _state = _state.copyWith(isLoading: false, clearStatus: true);
      notifyListeners();

      if (!context.mounted) return;

      // Ask confirmation after share sheet closes
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.backupSharePromptTitle),
          content: Text(l10n.backupSharePromptMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.saveNotConfirmed),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.saveConfirmed),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await backupService.recordLastBackupDate();
        await loadState();
        if (context.mounted) {
          AppSnackBar.show(context, message: l10n.backupSuccess);
        }
      }
    } catch (_) {
      _state = _state.copyWith(
        isLoading: false,
        clearStatus: true,
        errorMessage: l10n.backupFailed,
      );
      notifyListeners();
      if (context.mounted) {
        AppSnackBar.show(context, message: l10n.backupFailed);
      }
    }
  }

  /// Restores from a user-picked backup file.
  Future<void> performRestore(BuildContext context) async {
    final l10n = contextL10n(context);

    // Pick file with FileType.any (D)
    final pickResult = await FilePicker.pickFiles(
      type: FileType.any,
      dialogTitle: l10n.restorePickFileTitle,
    );

    if (pickResult.isEmpty || pickResult.first.path == null) {
      return;
    }

    final filePath = pickResult.first.path!;
    final file = File(filePath);

    try {
      if (!await file.exists()) {
        if (context.mounted) {
          AppSnackBar.show(context, message: l10n.wrongRecoveryKeyOrDamagedFile);
        }
        return;
      }

      // Size check before reading everything into memory (D)
      final fileSize = await file.length();
      if (fileSize > BackupService.maxFileSizeBytes) {
        if (context.mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l10n.backupFileOversizeTitle),
              content: Text(l10n.backupFileExceedsLimit),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.closeAction),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Magic bytes check (D)
      final headerBytes = await file.openRead(0, BackupService.magicBytes.length).first;
      for (int i = 0; i < BackupService.magicBytes.length; i++) {
        if (headerBytes[i] != BackupService.magicBytes[i]) {
          if (context.mounted) {
            AppSnackBar.show(context, message: l10n.wrongRecoveryKeyOrDamagedFile);
          }
          return;
        }
      }

      // Prompt for paper recovery key with hardened input (E)
      if (!context.mounted) return;
      final paperKey = await _promptForRestoreRecoveryKey(context);
      if (paperKey == null || paperKey.isEmpty) return;

      _state = _state.copyWith(isLoading: true, statusMessage: l10n.restoreRestoring);
      notifyListeners();

      try {
        final fileBytes = await file.readAsBytes();
        final summary = await backupService.validateAndRestoreBackup(
          fileBytes: fileBytes,
          recoveryKeyString: paperKey,
        );

        _state = _state.copyWith(isLoading: false, clearStatus: true);
        notifyListeners();

        // Refresh database and notes providers
        ref.read(notesListProvider).loadNotes();
        ref.read(vaultProvider).loadVaultState();
        await loadState();

        if (context.mounted) {
          await _showRestoreSummaryDialog(context, summary);
        }
      } on BackupUnsupportedVersionException {
        _state = _state.copyWith(isLoading: false, clearStatus: true);
        notifyListeners();
        if (context.mounted) {
          AppSnackBar.show(context, message: l10n.backupNewerVersionError);
        }
      } on BackupOversizeException {
        _state = _state.copyWith(isLoading: false, clearStatus: true);
        notifyListeners();
        if (context.mounted) {
          AppSnackBar.show(context, message: l10n.backupFileExceedsLimit);
        }
      } on BackupDecompressionBombException {
        _state = _state.copyWith(isLoading: false, clearStatus: true);
        notifyListeners();
        if (context.mounted) {
          AppSnackBar.show(context, message: l10n.decompressionBombError);
        }
      } on BackupSafetyCopyException {
        _state = _state.copyWith(isLoading: false, clearStatus: true);
        notifyListeners();
        if (context.mounted) {
          AppSnackBar.show(context, message: l10n.restoreSafetyCopyFailed);
        }
      } on BackupInvalidDataException {
        _state = _state.copyWith(isLoading: false, clearStatus: true);
        notifyListeners();
        if (context.mounted) {
          AppSnackBar.show(context, message: l10n.restoreInvalidData);
        }
      } on BackupSecurityException {
        _state = _state.copyWith(isLoading: false, clearStatus: true);
        notifyListeners();
        if (context.mounted) {
          AppSnackBar.show(context, message: l10n.wrongRecoveryKeyOrDamagedFile);
        }
      } catch (_) {
        _state = _state.copyWith(isLoading: false, clearStatus: true);
        notifyListeners();
        if (context.mounted) {
          AppSnackBar.show(context, message: l10n.wrongRecoveryKeyOrDamagedFile);
        }
      }
    } finally {
      // 7. Clean the picked file from app cache (Requirement 7)
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
      try {
        await FilePicker.clearTemporaryFiles();
      } catch (_) {}
    }
  }

  Future<String?> _promptForRestoreRecoveryKey(BuildContext context) async {
    final l10n = contextL10n(context);
    final controller = TextEditingController();
    String? localError;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text(l10n.enterRecoveryKeyToRestoreTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.enterRecoveryKeyToRestorePrompt),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  keyboardType: TextInputType.visiblePassword,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: l10n.enterRecoveryKeyLabel,
                    hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                  ),
                  onChanged: (_) {
                    if (localError != null) {
                      setLocalState(() => localError = null);
                    }
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.recoveryKeyDashesHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (localError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    localError!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final typed = RecoveryKeyService.normalize(controller.text);
                if (typed.isEmpty) {
                  setLocalState(() => localError = l10n.pleaseEnterYourRecoveryKey);
                  return;
                }
                if (!RecoveryKeyService.isValidFormat(typed)) {
                  setLocalState(() => localError = l10n.invalidRecoveryKey);
                  return;
                }
                Navigator.of(ctx).pop(typed);
              },
              child: Text(l10n.confirm),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRestoreSummaryDialog(BuildContext context, RestoreSummary summary) async {
    final l10n = contextL10n(context);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.restoreSummaryTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (summary.addedNotes == 0)
              Text(l10n.restoreSummaryNoNewNotes)
            else
              Text(l10n.restoreSummaryNotesRestored(summary.addedNotes)),
            const SizedBox(height: 8),
            Text(l10n.restoreSummaryFoldersRestored(summary.addedFolders)),
            if (summary.lockedNotesSkipped > 0) ...[
              const SizedBox(height: 8),
              Text(
                l10n.restoreSummaryLockedNotesSkipped(summary.lockedNotesSkipped),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              l10n.restoreSummarySafetyNotice,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.closeAction),
          ),
        ],
      ),
    );
  }

  Future<void> toggleReminder(bool enabled) async {
    await backupService.setBackupReminderEnabled(enabled);
    await loadState();
  }

  Future<void> snoozeReminder() async {
    await backupService.snoozeBackupReminder();
    await loadState();
  }
}

final backupProvider = ChangeNotifierProvider<BackupNotifier>((ref) {
  final service = ref.watch(backupServiceProvider);
  return BackupNotifier(ref, service);
});
