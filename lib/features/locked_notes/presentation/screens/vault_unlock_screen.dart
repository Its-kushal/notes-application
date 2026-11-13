import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/crypto/security_window_service.dart';
import '../../../../core/crypto/vault_service.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/loading_state.dart';
import '../../../../l10n/l10n_extension.dart';
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
          final l10n = contextL10n(context);
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.security, color: AppColors.error),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      l10n.securityNotice,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
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
                  child: Text(l10n.dismiss),
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
        final l10n = contextL10n(context);
        setState(() {
          _errorMessage = ref.read(vaultProvider).state.errorMessage ??
              l10n.incorrectSecret;
          _isPatternError = true;
          _enteredPin = '';
        });
      }
    }
  }

  Future<void> _showResetConfirmationDialog(BuildContext context) async {
    final l10n = contextL10n(context);
    final reset = await ResetVaultDialog.show(context);
    if (reset == true && context.mounted) {
      AppSnackBar.show(context, message: l10n.lockedNotesVaultReset);
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
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final l10n = contextL10n(context);

    if (vaultState.isDeriving) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.unlockingVault)),
        body: Center(
          child: LoadingState(message: l10n.verifyingSecret),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.unlockNotes),
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
                          : AppColors.warning.withValues(alpha: isDark ? 0.25 : 0.1),
                      borderRadius: BorderRadius.circular(Spacing.sm),
                      border: Border.all(
                        color: vaultState.isDelayedResetReady ? AppColors.error : AppColors.warning,
                      ),
                    ),
                    child: Column(
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
                            l10n.timeRemaining(_formatDuration(vaultState.delayedResetRemainingSeconds)),
                            style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                        const SizedBox(height: Spacing.xs),
                        TextButton(
                          onPressed: () => _showResetConfirmationDialog(context),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          child: Text(
                            vaultState.isDelayedResetReady
                                ? l10n.completeResetNow
                                : l10n.manageCancelResetRequest,
                            style: textTheme.bodySmall,
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
                      ? l10n.enterYourPin
                      : l10n.drawYourPattern,
                  style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
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
                          l10n.lockedOutTryAgainIn(vaultState.remainingLockoutSeconds),
                          style: textTheme.bodyMedium?.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
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
                    child: Text(
                      l10n.forgotPinOrPattern,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                // Reset Vault Button (D3, R8)
                TextButton(
                  onPressed: () => _showResetConfirmationDialog(context),
                  child: Text(
                    l10n.forgotSecretResetVault,
                    style: textTheme.bodySmall?.copyWith(color: AppColors.error),
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
