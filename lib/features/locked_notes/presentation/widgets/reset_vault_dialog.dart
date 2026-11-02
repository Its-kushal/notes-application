import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/crypto/recovery_key_service.dart';
import '../../../../core/crypto/security_window_service.dart';
import '../../../../core/crypto/vault_service.dart';
import '../../../../core/theme/spacing.dart';
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
    final deleteText = _deleteConfirmController.text.trim();
    if (deleteText != 'DELETE') {
      setState(() {
        _errorMessage = 'Type DELETE exactly to confirm.';
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
            _errorMessage = 'Please enter your current secret.';
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
            _errorMessage = 'Please enter your recovery key.';
            _isResetting = false;
          });
          return;
        }

        // Format and checksum pre-check to prevent burning failed attempts
        try {
          RecoveryKeyService.decodeKey(recoveryKey);
        } on RecoveryKeyChecksumException {
          setState(() {
            _errorMessage = 'Recovery key checksum mismatch. Check for typing mistakes.';
            _isResetting = false;
          });
          return;
        } on RecoveryKeyFormatException {
          setState(() {
            _errorMessage = 'Invalid recovery key format. Expected 28 characters.';
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
    } on VaultAuthException catch (e) {
      if (mounted) {
        setState(() {
          _isResetting = false;
          _errorMessage = e.message;
        });
      }
    } on RecoveryKeyAuthException {
      if (mounted) {
        setState(() {
          _isResetting = false;
          _errorMessage = 'Incorrect recovery key. Reset rejected.';
        });
      }
    } on VaultLockoutException catch (e) {
      if (mounted) {
        setState(() {
          _isResetting = false;
          _errorMessage = 'Locked out. Try again in ${e.remainingSeconds}s';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isResetting = false;
          _errorMessage = 'Reset failed: $e';
        });
      }
    }
  }

  Future<void> _handleCompleteDelayedReset() async {
    final deleteText = _deleteConfirmController.text.trim();
    if (deleteText != 'DELETE') {
      setState(() {
        _errorMessage = 'Type DELETE exactly to confirm.';
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
      if (mounted) {
        setState(() {
          _isResetting = false;
          _errorMessage = 'Reset failed: $e';
        });
      }
    }
  }

  Future<void> _handleRequestDelayedReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request 72-Hour Reset?'),
        content: const Text(
          'A delayed reset will be scheduled. After 72 hours, anyone with physical access can reset the vault by typing DELETE.\n\n'
          'Unlocking the vault with your secret or recovery key before 72 hours will automatically cancel this request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Request Reset'),
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
            _errorMessage = 'Failed to request delayed reset: $e';
          });
        }
      }
    }
  }

  Future<void> _handleCancelDelayedReset() async {
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
          _errorMessage = 'Failed to cancel request: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 28),
          SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'Reset locked notes?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will PERMANENTLY DELETE all locked notes and reset the vault metadata. Unlocked notes will not be affected.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: Spacing.md),

            // If a delayed reset is currently requested
            if (isDelayedRequested) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Spacing.sm),
                decoration: BoxDecoration(
                  color: isDelayedReady
                      ? AppColors.error.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDelayedReady ? AppColors.error : Colors.orange,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDelayedReady
                          ? 'Delayed Reset Ready (72h Passed)'
                          : 'Delayed Reset Requested',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDelayedReady ? AppColors.error : Colors.orange.shade800,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    if (vaultState.delayedResetRequestedAt != null)
                      Text(
                        'Requested on: ${vaultState.delayedResetRequestedAt!.toLocal().toString().split('.')[0]}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    if (!isDelayedReady)
                      Padding(
                        padding: const EdgeInsets.only(top: Spacing.xs),
                        child: Text(
                          'Time remaining: ${_formatDuration(remainingSecs)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    const SizedBox(height: Spacing.xs),
                    TextButton(
                      onPressed: _isResetting ? null : _handleCancelDelayedReset,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Text('Cancel Delayed Reset Request'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.md),
              if (isDelayedReady) ...[
                const Text(
                  'The 72-hour delay has passed. Type DELETE to complete reset:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: Spacing.xs),
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
              const Text(
                'Prove current secret or recovery key to reset immediately:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Spacing.xs),

              // Method Selector
              if (hasRecoveryKey) ...[
                SegmentedButton<ResetAuthMethod>(
                  segments: const [
                    ButtonSegment(
                      value: ResetAuthMethod.secret,
                      label: Text('Vault Secret'),
                      icon: Icon(Icons.lock_outline, size: 16),
                    ),
                    ButtonSegment(
                      value: ResetAuthMethod.recoveryKey,
                      label: Text('Recovery Key'),
                      icon: Icon(Icons.key, size: 16),
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
                const SizedBox(height: Spacing.sm),
              ],

              if (_authMethod == ResetAuthMethod.secret) ...[
                TextField(
                  controller: _secretController,
                  enabled: !isLockedOut && !_isResetting,
                  obscureText: true,
                  enableIMEPersonalizedLearning: false,
                  decoration: InputDecoration(
                    labelText: vaultState.credentialType == CredentialType.pattern
                        ? 'Current Pattern Secret'
                        : 'Current PIN',
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
                  decoration: const InputDecoration(
                    labelText: 'Paper Recovery Key',
                    hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.key, color: AppColors.primary),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],

              const SizedBox(height: Spacing.sm),
              const Text(
                'Type DELETE to confirm:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: Spacing.xs),
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
                const SizedBox(height: Spacing.md),
                const Divider(),
                Center(
                  child: TextButton.icon(
                    onPressed: _isResetting ? null : _handleRequestDelayedReset,
                    icon: const Icon(Icons.schedule, size: 18),
                    label: const Text('Lost both? Request delayed reset (72h)'),
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
          child: const Text('Cancel'),
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
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Complete Reset'),
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
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Delete Everything'),
          ),
      ],
    );
  }
}
