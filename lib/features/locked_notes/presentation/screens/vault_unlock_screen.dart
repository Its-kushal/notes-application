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

  void _showResetConfirmationDialog(BuildContext context) {
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
                    'This will PERMANENTLY DELETE all locked notes and reset the vault. Unlocked notes will not be affected.\n\nType DELETE to confirm:',
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
                            context.go('/');
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
