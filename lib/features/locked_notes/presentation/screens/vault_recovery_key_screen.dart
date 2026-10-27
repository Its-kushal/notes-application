import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/crypto/recovery_key_service.dart';
import '../../../../core/crypto/security_window_service.dart';
import '../../../../core/crypto/vault_service.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/loading_state.dart';
import '../controllers/vault_providers.dart';
import '../widgets/pattern_lock_widget.dart';
import '../widgets/pin_pad_widget.dart';

class VaultRecoveryKeyScreen extends ConsumerStatefulWidget {
  final bool isRegenerating;

  const VaultRecoveryKeyScreen({
    super.key,
    this.isRegenerating = false,
  });

  @override
  ConsumerState<VaultRecoveryKeyScreen> createState() => _VaultRecoveryKeyScreenState();
}

class _VaultRecoveryKeyScreenState extends ConsumerState<VaultRecoveryKeyScreen> {
  int _step = 0; // 0 = enter current secret, 1 = show key, 2 = confirm key
  String _currentSecret = '';
  String? _generatedKey;
  final TextEditingController _retypeController = TextEditingController();
  String? _errorMessage;
  bool _isPatternError = false;
  int _patternResetKey = 0;

  @override
  void initState() {
    super.initState();
    SecurityWindowService.enableSecure();
  }

  @override
  void dispose() {
    _retypeController.dispose();
    SecurityWindowService.disableSecure();
    super.dispose();
  }

  Future<void> _proceedStep0() async {
    final vaultNotifier = ref.read(vaultProvider);
    final credType = vaultNotifier.credentialType;

    if (credType == CredentialType.pin) {
      if (_currentSecret.length < 6) {
        setState(() {
          _errorMessage = 'PIN must be at least 6 digits';
        });
        return;
      }
    } else {
      if (_currentSecret.split('-').length < 5) {
        setState(() {
          _errorMessage = 'Pattern must connect at least 5 dots';
          _isPatternError = true;
        });
        return;
      }
    }

    try {
      final vaultService = ref.read(vaultServiceProvider);
      final meta = await vaultService.getVaultMetadata();
      if (meta != null) {
        final kdf = ref.read(kdfServiceProvider);
        final wrappingKeyBytes = await kdf.deriveKey(
          secret: _currentSecret,
          salt: meta.salt,
          iterations: meta.kdfIterations,
          keyLength: 32,
        );
        final aesGcm = AesGcm.with256bits();
        await aesGcm.decrypt(
          SecretBox(
            meta.wrappedVaultKey,
            nonce: meta.wrappedVaultKeyIv,
            mac: Mac(meta.wrappedVaultKeyTag),
          ),
          secretKey: SecretKey(wrappingKeyBytes),
          aad: VaultService.vaultWrappingAad,
        );
      }

      setState(() {
        _step = 1;
        _generatedKey = RecoveryKeyService.generateKey();
        _retypeController.clear();
        _errorMessage = null;
        _isPatternError = false;
      });
    } on SecretBoxAuthenticationError {
      setState(() {
        _errorMessage = 'Current secret is incorrect.';
        _isPatternError = true;
        _currentSecret = '';
        _patternResetKey++;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Current secret is incorrect.';
        _isPatternError = true;
        _currentSecret = '';
        _patternResetKey++;
      });
    }
  }

  void _proceedStep1() {
    setState(() {
      _step = 2;
      _errorMessage = null;
    });
  }

  Future<void> _proceedStep2() async {
    final typed = RecoveryKeyService.normalize(_retypeController.text);
    final expected = RecoveryKeyService.normalize(_generatedKey ?? '');

    if (typed.isEmpty) {
      setState(() {
        _errorMessage = 'Please type your recovery key.';
      });
      return;
    }

    if (typed != expected) {
      setState(() {
        _errorMessage = 'Recovery key does not match. Check for typing mistakes.';
      });
      return;
    }

    try {
      final vaultNotifier = ref.read(vaultProvider);
      await vaultNotifier.createOrUpdateRecoveryKey(
        currentSecret: _currentSecret,
        recoveryKeyString: _generatedKey!,
      );
      if (mounted) {
        AppSnackBar.show(
          context,
          message: widget.isRegenerating
              ? 'New recovery key generated'
              : 'Recovery key created',
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to save recovery key: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultProvider).state;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (vaultState.isDeriving) {
      return Scaffold(
        appBar: AppBar(title: const Text('Securing recovery key')),
        body: const Center(
          child: LoadingState(message: 'Encrypting recovery wrap...'),
        ),
      );
    }

    final title = widget.isRegenerating ? 'Generate new recovery key' : 'Create recovery key';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _step = _step - 1;
                    _errorMessage = null;
                  });
                },
              )
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Plain warning banner (R2, R4)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Spacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(Spacing.sm),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(
                          _step == 0
                              ? 'Enter your current secret to authenticate before creating a recovery key.'
                              : 'Write it on paper; whoever has this key can open all your notes; it cannot be shown again.',
                          style: TextStyle(
                            color: isDark ? AppColors.white : AppColors.error,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.md),

                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.sm),
                ],

                if (_step == 0) ...[
                  Text(
                    vaultState.credentialType == CredentialType.pin
                        ? 'Enter your current PIN'
                        : 'Draw your current pattern',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: Spacing.xs),
                  const Text(
                    'Confirm secret before proceeding',
                    style: TextStyle(fontSize: 13, color: AppColors.greyDark),
                  ),
                  const SizedBox(height: Spacing.md),

                  if (vaultState.credentialType == CredentialType.pin) ...[
                    PinPadWidget(
                      pin: _currentSecret,
                      minDigits: 6,
                      onPinChanged: (val) {
                        setState(() {
                          _currentSecret = val;
                          _errorMessage = null;
                        });
                      },
                    ),
                    const SizedBox(height: Spacing.md),
                    ElevatedButton(
                      onPressed: _currentSecret.length >= 6 ? _proceedStep0 : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        minimumSize: const Size(200, 48),
                      ),
                      child: const Text('Continue'),
                    ),
                  ] else ...[
                    PatternLockWidget(
                      key: ValueKey('recovery_pattern_$_patternResetKey'),
                      minDots: 5,
                      isError: _isPatternError,
                      onPatternComplete: (dots) {
                        _currentSecret = dots.join('-');
                        _proceedStep0();
                      },
                    ),
                  ],
                ] else if (_step == 1) ...[
                  const Text(
                    'Write down your recovery key',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: Spacing.xs),
                  const Text(
                    'Write it on paper; whoever has this key can open all your notes; it cannot be shown again.',
                    style: TextStyle(fontSize: 13, color: AppColors.greyDark),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.md),

                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(vertical: Spacing.sm),
                    padding: const EdgeInsets.all(Spacing.md),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.charcoal : AppColors.greyLight,
                      borderRadius: BorderRadius.circular(Spacing.sm),
                      border: Border.all(color: AppColors.primary, width: 1.5),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.vpn_key_rounded, size: 36, color: AppColors.primary),
                        const SizedBox(height: Spacing.sm),
                        Text(
                          _generatedKey ?? '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Spacing.sm),
                  const Text(
                    'This key allows you to recover your vault if you ever forget your secret.',
                    style: TextStyle(fontSize: 12, color: AppColors.greyDark),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.lg),
                  ElevatedButton(
                    onPressed: _proceedStep1,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      minimumSize: const Size(220, 48),
                    ),
                    child: const Text('I have written it down'),
                  ),
                ] else if (_step == 2) ...[
                  const Text(
                    'Confirm recovery key',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: Spacing.xs),
                  const Text(
                    'Type the key exactly as written on paper to confirm.',
                    style: TextStyle(fontSize: 13, color: AppColors.greyDark),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.md),

                  TextField(
                    controller: _retypeController,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Recovery key',
                      hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.edit_note_outlined),
                    ),
                    onChanged: (_) {
                      if (_errorMessage != null) {
                        setState(() {
                          _errorMessage = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: Spacing.xs),
                  const Text(
                    'Dashes and spaces are optional. Case-insensitive.',
                    style: TextStyle(fontSize: 12, color: AppColors.greyDark),
                  ),
                  const SizedBox(height: Spacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _step = 1;
                            _errorMessage = null;
                          });
                        },
                        child: const Text('View key again'),
                      ),
                      const SizedBox(width: Spacing.md),
                      ElevatedButton(
                        onPressed: _proceedStep2,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.white,
                          minimumSize: const Size(160, 48),
                        ),
                        child: const Text('Verify & Finish'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
