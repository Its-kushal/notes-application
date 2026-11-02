import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/crypto/security_window_service.dart';
import '../../../../core/crypto/vault_service.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/loading_state.dart';
import '../controllers/vault_providers.dart';
import '../widgets/pattern_lock_widget.dart';
import '../widgets/pin_pad_widget.dart';
import '../widgets/reset_vault_dialog.dart';

class VaultUnlockScreen extends ConsumerStatefulWidget {
  final VoidCallback? onUnlocked;

  const VaultUnlockScreen({
    super.key,
    this.onUnlocked,
  });

  @override
  ConsumerState<VaultUnlockScreen> createState() => _VaultUnlockScreenState();
}

class _VaultUnlockScreenState extends ConsumerState<VaultUnlockScreen> {
  String _enteredPin = '';
  String? _errorMessage;
  bool _isPatternError = false;

  @override
  void initState() {
    super.initState();
    SecurityWindowService.enableSecure();
  }

  @override
  void dispose() {
    SecurityWindowService.disableSecure();
    super.dispose();
  }

  Future<void> _attemptUnlock(String secret) async {
    final vaultNotifier = ref.read(vaultProvider);
    if (vaultNotifier.state.remainingLockoutSeconds > 0) return;

    setState(() {
      _errorMessage = null;
      _isPatternError = false;
    });

    try {
      await vaultNotifier.unlockVault(secret);
      if (mounted) {
        final noticeDate = ref.read(vaultProvider).state.pendingResetNoticeDate;
        if (noticeDate != null) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.security, color: AppColors.error),
                  SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text('Security Notice', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: Text(
                'A vault reset was requested on ${noticeDate.toLocal().toString().split('.')[0]}.\n\n'
                'Because you have successfully unlocked the vault, this reset request has been automatically cancelled.',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    ref.read(vaultProvider).acknowledgeResetNotice();
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          );
          if (!mounted) return;
        }

        if (widget.onUnlocked != null) {
          widget.onUnlocked!();
        } else if (Navigator.of(context).canPop()) {
          context.pop(true);
        } else {
          context.go('/locked');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = ref.read(vaultProvider).state.errorMessage ??
              'Incorrect secret. Please try again.';
          _isPatternError = true;
          _enteredPin = '';
        });
      }
    }
  }

  Future<void> _showResetConfirmationDialog(BuildContext context) async {
    final reset = await ResetVaultDialog.show(context);
    if (reset == true && context.mounted) {
      AppSnackBar.show(context, message: 'Locked notes and vault reset');
      context.go('/');
    }
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

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultProvider).state;
    final isLockedOut = vaultState.remainingLockoutSeconds > 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (vaultState.isDeriving) {
      return Scaffold(
        appBar: AppBar(title: const Text('Unlocking vault')),
        body: const Center(
          child: LoadingState(message: 'Verifying secret...'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unlock notes'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (vaultState.isDelayedResetRequested) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: Spacing.md),
                    padding: const EdgeInsets.all(Spacing.sm),
                    decoration: BoxDecoration(
                      color: vaultState.isDelayedResetReady
                          ? AppColors.error.withValues(alpha: isDark ? 0.25 : 0.1)
                          : Colors.orange.withValues(alpha: isDark ? 0.25 : 0.1),
                      borderRadius: BorderRadius.circular(Spacing.sm),
                      border: Border.all(
                        color: vaultState.isDelayedResetReady ? AppColors.error : Colors.orange,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: vaultState.isDelayedResetReady ? AppColors.error : Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: Spacing.xs),
                            Expanded(
                              child: Text(
                                vaultState.isDelayedResetReady
                                    ? 'Vault reset ready to complete (72h passed)'
                                    : 'A vault reset was requested on ${vaultState.delayedResetRequestedAt?.toLocal().toString().split('.')[0] ?? ''}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: vaultState.isDelayedResetReady ? AppColors.error : Colors.orange.shade800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!vaultState.isDelayedResetReady) ...[
                          const SizedBox(height: Spacing.xs),
                          Text(
                            'Time remaining: ${_formatDuration(vaultState.delayedResetRemainingSeconds)}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                        const SizedBox(height: Spacing.xs),
                        TextButton(
                          onPressed: () => _showResetConfirmationDialog(context),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          child: Text(
                            vaultState.isDelayedResetReady ? 'Complete Reset Now' : 'Manage / Cancel Reset Request',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.sm),
                Icon(
                  Icons.lock_rounded,
                  size: 56,
                  color: isLockedOut ? AppColors.error : AppColors.primary,
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  vaultState.credentialType == CredentialType.pin
                      ? 'Enter your PIN'
                      : 'Draw your pattern',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: Spacing.xs),

                // Lockout Warning / Status
                if (isLockedOut) ...[
                  Container(
                    padding: const EdgeInsets.all(Spacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: isDark ? 0.25 : 0.1),
                      borderRadius: BorderRadius.circular(Spacing.sm),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.timer_outlined, color: AppColors.error, size: 20),
                        const SizedBox(width: Spacing.xs),
                        Text(
                          'Locked out. Try again in ${vaultState.remainingLockoutSeconds}s',
                          style: const TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: Spacing.md),

                if (vaultState.credentialType == CredentialType.pin)
                  PinPadWidget(
                    pin: _enteredPin,
                    minDigits: 6,
                    isEnabled: !isLockedOut,
                    onPinChanged: (val) {
                      setState(() {
                        _enteredPin = val;
                        _errorMessage = null;
                      });
                      if (val.length >= 6) {
                        _attemptUnlock(val);
                      }
                    },
                  )
                else
                  PatternLockWidget(
                    minDots: 5,
                    isEnabled: !isLockedOut,
                    isError: _isPatternError,
                    onPatternStart: () {
                      if (_isPatternError || _errorMessage != null) {
                        setState(() {
                          _isPatternError = false;
                          _errorMessage = null;
                        });
                      }
                    },
                    onPatternComplete: (dots) {
                      final patternString = dots.join('-');
                      _attemptUnlock(patternString);
                    },
                  ),

                const SizedBox(height: Spacing.lg),

                // Forgot PIN/pattern? Button (R6)
                if (vaultState.hasRecoveryKey)
                  TextButton(
                    onPressed: () async {
                      final recovered = await context.push<bool>('/vault/recover');
                      if (!context.mounted) return;
                      if (recovered == true && ref.read(vaultProvider).isUnlocked) {
                        if (widget.onUnlocked != null) {
                          widget.onUnlocked!();
                        } else if (Navigator.of(context).canPop()) {
                          context.pop(true);
                        } else {
                          context.go('/locked');
                        }
                      }
                    },
                    child: const Text(
                      'Forgot PIN/pattern?',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ),

                // Reset Vault Button (D3, R8)
                TextButton(
                  onPressed: () => _showResetConfirmationDialog(context),
                  child: const Text(
                    'Forgot secret? Reset locked notes',
                    style: TextStyle(color: AppColors.error, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
