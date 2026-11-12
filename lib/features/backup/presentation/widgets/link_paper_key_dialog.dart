import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/crypto/recovery_key_service.dart';
import '../../../../core/crypto/vault_service.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../locked_notes/presentation/controllers/vault_providers.dart';

enum LinkPaperKeyMode {
  /// Case 1: No vault and no backup subkey. Create and confirm root key.
  createAndConfirm,

  /// Case 2: Vault with recovery wrap exists, but no backup subkey.
  /// User enters existing paper key to verify against vault and derive subkey.
  linkExistingVaultKey,
}

class LinkPaperKeyDialog extends ConsumerStatefulWidget {
  final LinkPaperKeyMode mode;

  const LinkPaperKeyDialog({
    super.key,
    required this.mode,
  });

  static Future<bool?> show(BuildContext context, {required LinkPaperKeyMode mode}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => LinkPaperKeyDialog(mode: mode),
    );
  }

  @override
  ConsumerState<LinkPaperKeyDialog> createState() => _LinkPaperKeyDialogState();
}

class _LinkPaperKeyDialogState extends ConsumerState<LinkPaperKeyDialog> {
  int _step = 0; // For createAndConfirm: 0 = show, 1 = retype. For linkExisting: 0 = enter
  String? _generatedKey;
  final TextEditingController _textController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.mode == LinkPaperKeyMode.createAndConfirm) {
      _generatedKey = RecoveryKeyService.generateKey();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    final l10n = contextL10n(context);
    final typed = RecoveryKeyService.normalize(_textController.text);

    if (typed.isEmpty) {
      setState(() {
        _errorMessage = l10n.pleaseEnterYourRecoveryKey;
      });
      return;
    }

    if (!RecoveryKeyService.isValidFormat(typed)) {
      setState(() {
        _errorMessage = l10n.invalidRecoveryKey;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final vaultService = ref.read(vaultServiceProvider);

      if (widget.mode == LinkPaperKeyMode.createAndConfirm) {
        final expected = RecoveryKeyService.normalize(_generatedKey ?? '');
        if (typed != expected) {
          setState(() {
            _errorMessage = l10n.recoveryKeyMismatchError;
            _isLoading = false;
          });
          return;
        }

        final recoveryBytes = RecoveryKeyService.decodeKey(typed);
        final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(recoveryBytes);
        await vaultService.storeBackupSubkey(backupSubkey);
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        // Case 2: Verify against existing vault recovery wrap
        final isMatch = await vaultService.verifyRecoveryKeyAgainstVault(typed);
        if (!isMatch) {
          setState(() {
            _errorMessage = l10n.invalidRecoveryKey;
            _isLoading = false;
          });
          return;
        }

        final recoveryBytes = RecoveryKeyService.decodeKey(typed);
        final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(recoveryBytes);
        await vaultService.storeBackupSubkey(backupSubkey);
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } on VaultLockoutException catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    } catch (_) {
      setState(() {
        _errorMessage = l10n.invalidRecoveryKey;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = contextL10n(context);
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    if (widget.mode == LinkPaperKeyMode.createAndConfirm && _step == 0) {
      return AlertDialog(
        title: Text(l10n.setupPaperKeyForBackupTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.setupPaperKeyForBackupPrompt,
                style: textTheme.bodyMedium,
              ),
              AppSpacing.vGapMd,
              Container(
                width: double.infinity,
                padding: AppSpacing.paddingMd,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: AppSpacing.borderRadiusSm,
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.vpn_key_rounded, size: 36, color: AppColors.primary),
                    AppSpacing.vGapSm,
                    Text(
                      _generatedKey ?? '',
                      key: const ValueKey('backup_generated_key_text'),
                      textAlign: TextAlign.center,
                      style: textTheme.titleMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              AppSpacing.vGapSm,
              Text(
                l10n.recoveryKeyExplanation,
                style: textTheme.bodySmall?.copyWith(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _step = 1;
              });
            },
            child: Text(l10n.iHaveWrittenItDown),
          ),
        ],
      );
    }

    // Step 1 for createAndConfirm, or Step 0 for linkExistingVaultKey
    final title = widget.mode == LinkPaperKeyMode.createAndConfirm
        ? l10n.confirmRecoveryKey
        : l10n.enterPaperKeyToBackupTitle;

    final prompt = widget.mode == LinkPaperKeyMode.createAndConfirm
        ? l10n.verifyRecoveryKeyPrompt
        : l10n.enterPaperKeyToBackupPrompt;

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(prompt, style: textTheme.bodyMedium),
            AppSpacing.vGapMd,
            TextField(
              controller: _textController,
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
                if (_errorMessage != null) {
                  setState(() {
                    _errorMessage = null;
                  });
                }
              },
            ),
            AppSpacing.vGapXs,
            Text(
              l10n.recoveryKeyDashesHint,
              style: textTheme.bodySmall?.copyWith(
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
            if (_errorMessage != null) ...[
              AppSpacing.vGapSm,
              Text(
                _errorMessage!,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _handleConfirm,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                )
              : Text(l10n.confirm),
        ),
      ],
    );
  }
}
