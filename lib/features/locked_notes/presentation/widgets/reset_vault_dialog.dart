import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/crypto/recovery_key_service.dart';
import '../../../../core/crypto/security_window_service.dart';
import '../../../../core/crypto/vault_service.dart';
import '../../../../core/theme/spacing.dart';
import 'package:leaflock/l10n/l10n_extension.dart';
import '../controllers/vault_providers.dart';

enum ResetAuthMethod {
  secret,
  recoveryKey,
}

class ResetVaultDialog extends ConsumerStatefulWidget {
  const ResetVaultDialog({super.key});

  /// Displays the ResetVaultDialog. Returns true if the vault was reset.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ResetVaultDialog(),
    );
  }

  @override
  ConsumerState<ResetVaultDialog> createState() => _ResetVaultDialogState();
}

class _ResetVaultDialogState extends ConsumerState<ResetVaultDialog> {
  ResetAuthMethod _authMethod = ResetAuthMethod.secret;
  final TextEditingController _secretController = TextEditingController();
  final TextEditingController _recoveryKeyController = TextEditingController();
  final TextEditingController _deleteConfirmController = TextEditingController();

  String? _errorMessage;
  bool _isResetting = false;

  @override
  void initState() {
    super.initState();
    SecurityWindowService.enableSecure();
  }

  @override
  void dispose() {
    _secretController.dispose();
    _recoveryKeyController.dispose();
    _deleteConfirmController.dispose();
    SecurityWindowService.disableSecure();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '0s';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  Future<void> _handleImmediateReset() async {
    final l10n = contextL10n(context);
    final deleteText = _deleteConfirmController.text.trim();
    if (deleteText != 'DELETE') {
      setState(() {
        _errorMessage = l10n.typeDeleteToConfirm;
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _isResetting = true;
    });

    try {
      final notifier = ref.read(vaultProvider);
      if (_authMethod == ResetAuthMethod.secret) {
        final secret = _secretController.text;
        if (secret.isEmpty) {
          setState(() {
            _errorMessage = l10n.pleaseEnterCurrentSecret;
            _isResetting = false;
          });
          return;
        }
        await notifier.immediateResetWithSecret(
          secret: secret,
          confirmationText: deleteText,
        );
      } else {
        final recoveryKey = _recoveryKeyController.text.trim();
        if (recoveryKey.isEmpty) {
          setState(() {
            _errorMessage = l10n.pleaseEnterYourRecoveryKey;
            _isResetting = false;
          });
          return;
        }
        await notifier.immediateResetWithRecoveryKey(
          recoveryKeyString: recoveryKey,
          confirmationText: deleteText,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on VaultLockoutException catch (e) {
      setState(() {
        _isResetting = false;
        _errorMessage = l10n.lockedOutTryAgainIn(e.remainingSeconds);
      });
    } on VaultAuthException {
      setState(() {
        _isResetting = false;
        _errorMessage = _authMethod == ResetAuthMethod.secret
            ? l10n.currentSecretIncorrect
            : l10n.incorrectRecoveryKeyCheckPaper;
      });
    } on RecoveryKeyChecksumException {
      setState(() {
        _isResetting = false;
        _errorMessage = l10n.checkForTypingMistakes;
      });
    } on RecoveryKeyFormatException {
      setState(() {
        _isResetting = false;
        _errorMessage = l10n.checkForTypingMistakes;
      });
    } catch (e) {
      setState(() {
        _isResetting = false;
        _errorMessage = l10n.recoveryFailed;
      });
    }
  }

  Future<void> _handleCompleteDelayedReset() async {
    final l10n = contextL10n(context);
    final deleteText = _deleteConfirmController.text.trim();
    if (deleteText != 'DELETE') {
      setState(() {
        _errorMessage = l10n.typeDeleteToConfirm;
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _isResetting = true;
    });

    try {
      await ref.read(vaultProvider).completeDelayedReset(confirmationText: deleteText);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _isResetting = false;
        _errorMessage = l10n.recoveryFailed;
      });
    }
  }

  Future<void> _handleRequestDelayedReset() async {
    final l10n = contextL10n(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.requestDelayedReset,
          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          l10n.vaultResetRequestedOn('72h'),
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() {
        _isResetting = true;
        _errorMessage = null;
      });
      try {
        await ref.read(vaultProvider).requestDelayedReset();
        if (mounted) {
          setState(() {
            _isResetting = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isResetting = false;
            _errorMessage = l10n.recoveryFailed;
          });
        }
      }
    }
  }

  Future<void> _handleCancelDelayedReset() async {
    final l10n = contextL10n(context);
    setState(() {
      _isResetting = true;
    });
    try {
      await ref.read(vaultProvider).cancelDelayedReset();
      if (mounted) {
        setState(() {
          _isResetting = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isResetting = false;
          _errorMessage = l10n.recoveryFailed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final l10n = contextL10n(context);
    final vaultState = ref.watch(vaultProvider).state;
    final hasRecoveryKey = vaultState.hasRecoveryKey;
    final isDelayedRequested = vaultState.isDelayedResetRequested;
    final isDelayedReady = vaultState.isDelayedResetReady;
    final remainingSecs = vaultState.delayedResetRemainingSeconds;

    final isLockedOut = _authMethod == ResetAuthMethod.secret
        ? vaultState.remainingLockoutSeconds > 0
        : vaultState.remainingRecoveryLockoutSeconds > 0;

    final isDeleteTyped = _deleteConfirmController.text.trim() == 'DELETE';
    final hasAuthInput = _authMethod == ResetAuthMethod.secret
        ? _secretController.text.isNotEmpty
        : _recoveryKeyController.text.trim().isNotEmpty;

    final isImmediateButtonEnabled = !_isResetting && !isLockedOut && isDeleteTyped && hasAuthInput;
    final isDelayedCompleteEnabled = !_isResetting && isDelayedReady && isDeleteTyped;

    return AlertDialog(
      shape: const RoundedRectangleBorder(
        borderRadius: AppSpacing.borderRadiusMd,
      ),
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 28),
          AppSpacing.hGapSm,
          Expanded(
            child: Text(
              l10n.resetLockedNotesTitle,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.resetWarningMessage,
              style: textTheme.bodyMedium,
            ),
            AppSpacing.vGapMd,

            // If a delayed reset is currently requested
            if (isDelayedRequested) ...[
              Container(
                width: double.infinity,
                padding: AppSpacing.paddingSm,
                decoration: BoxDecoration(
                  color: isDelayedReady
                      ? AppColors.error.withValues(alpha: 0.1)
                      : AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: AppSpacing.borderRadiusSm,
                  border: Border.all(
                    color: isDelayedReady ? AppColors.error : AppColors.warning,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDelayedReady
                          ? l10n.vaultResetReadyToComplete
                          : l10n.vaultResetRequestedOn(
                              vaultState.delayedResetRequestedAt != null
                                  ? vaultState.delayedResetRequestedAt!.toLocal().toString().split('.')[0]
                                  : '',
                            ),
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDelayedReady ? AppColors.error : AppColors.warning,
                      ),
                    ),
                    if (!isDelayedReady) ...[
                      AppSpacing.vGapXs,
                      Text(
                        l10n.timeRemaining(_formatDuration(remainingSecs)),
                        style: textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    AppSpacing.vGapXs,
                    TextButton(
                      onPressed: _isResetting ? null : _handleCancelDelayedReset,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: Text(l10n.cancelPendingReset),
                    ),
                  ],
                ),
              ),
              AppSpacing.vGapMd,
              if (isDelayedReady) ...[
                Text(
                  l10n.deleteConfirmationPrompt,
                  style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                AppSpacing.vGapXs,
                TextField(
                  controller: _deleteConfirmController,
                  enabled: !_isResetting,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'DELETE',
                    border: const OutlineInputBorder(),
                    errorText: _errorMessage,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],

            // Immediate Reset Section (available when delayed reset is not ready)
            if (!isDelayedReady) ...[
              Text(
                l10n.proveCurrentSecretOrRecoveryKey,
                style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              AppSpacing.vGapXs,

              // Method Selector
              if (hasRecoveryKey) ...[
                SegmentedButton<ResetAuthMethod>(
                  segments: [
                    ButtonSegment(
                      value: ResetAuthMethod.secret,
                      label: Text(l10n.vaultSecretOption),
                      icon: const Icon(Icons.lock_outline, size: 16),
                    ),
                    ButtonSegment(
                      value: ResetAuthMethod.recoveryKey,
                      label: Text(l10n.recoveryKeyOption),
                      icon: const Icon(Icons.key, size: 16),
                    ),
                  ],
                  selected: {_authMethod},
                  onSelectionChanged: (set) {
                    setState(() {
                      _authMethod = set.first;
                      _errorMessage = null;
                    });
                  },
                ),
                AppSpacing.vGapSm,
              ],

              if (_authMethod == ResetAuthMethod.secret) ...[
                TextField(
                  controller: _secretController,
                  enabled: !isLockedOut && !_isResetting,
                  obscureText: true,
                  enableIMEPersonalizedLearning: false,
                  decoration: InputDecoration(
                    labelText: vaultState.credentialType == CredentialType.pattern
                        ? l10n.currentPatternPrompt
                        : l10n.currentPinPrompt,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ] else ...[
                TextField(
                  controller: _recoveryKeyController,
                  enabled: !isLockedOut && !_isResetting,
                  enableIMEPersonalizedLearning: false,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: l10n.enterRecoveryKeyLabel,
                    hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.key, color: AppColors.primary),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],

              AppSpacing.vGapSm,
              Text(
                l10n.deleteConfirmationPrompt,
                style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              AppSpacing.vGapXs,
              TextField(
                controller: _deleteConfirmController,
                enabled: !isLockedOut && !_isResetting,
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  border: const OutlineInputBorder(),
                  errorText: _errorMessage,
                  errorMaxLines: 3,
                ),
                onChanged: (_) => setState(() {}),
              ),

              if (!isDelayedRequested) ...[
                AppSpacing.vGapMd,
                const Divider(),
                Center(
                  child: TextButton.icon(
                    onPressed: _isResetting ? null : _handleRequestDelayedReset,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(l10n.requestDelayedReset),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isResetting ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        if (isDelayedReady)
          ElevatedButton(
            onPressed: isDelayedCompleteEnabled ? _handleCompleteDelayedReset : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: _isResetting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                    ),
                  )
                : Text(l10n.completeResetNow),
          )
        else
          ElevatedButton(
            onPressed: isImmediateButtonEnabled ? _handleImmediateReset : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: _isResetting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
                    ),
                  )
                : Text(l10n.deleteEverything),
          ),
      ],
    );
  }
}
