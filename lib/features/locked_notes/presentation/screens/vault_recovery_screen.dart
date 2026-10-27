import 'dart:typed_data';
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

class VaultRecoveryScreen extends ConsumerStatefulWidget {
  const VaultRecoveryScreen({super.key});

  @override
  ConsumerState<VaultRecoveryScreen> createState() => _VaultRecoveryScreenState();
}

class _VaultRecoveryScreenState extends ConsumerState<VaultRecoveryScreen> {
  int _step = 0; // 0 = enter recovery key, 1 = enter new secret, 2 = confirm new secret
  final TextEditingController _recoveryKeyController = TextEditingController();
  String? _verifiedRecoveryKey;

  CredentialType _selectedType = CredentialType.pin;
  String _newSecret = '';
  String _confirmSecret = '';
  String? _errorMessage;
  bool _isPatternError = false;
  int _patternResetKey = 0;
  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();
    SecurityWindowService.enableSecure();
  }

  @override
  void dispose() {
    _recoveryKeyController.dispose();
    SecurityWindowService.disableSecure();
    super.dispose();
  }

  Future<void> _verifyRecoveryKey() async {
    final vaultService = ref.read(vaultServiceProvider);
    final lockoutSeconds = await vaultService.getRemainingRecoveryLockoutSeconds();
    if (lockoutSeconds > 0) {
      setState(() {
        _errorMessage = 'Locked out. Try again in ${lockoutSeconds}s';
      });
      return;
    }

    final input = _recoveryKeyController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your recovery key.';
      });
      return;
    }

    // 1. Validation & Checksum (R6: does not count as attempt if checksum fails)
    final Uint8List recoveryBytes;
    try {
      recoveryBytes = RecoveryKeyService.decodeKey(input);
    } on RecoveryKeyChecksumException {
      setState(() {
        _errorMessage = 'Check for typing mistakes.';
      });
      return;
    } on RecoveryKeyFormatException {
      setState(() {
        _errorMessage = 'Check for typing mistakes.';
      });
      return;
    }

    // 2. Test decryption against stored recovery wrap (R6: wrong key counts as attempt)
    final meta = await vaultService.getVaultMetadata();
    if (meta == null || !meta.hasRecoveryKey) {
      setState(() {
        _errorMessage = 'No recovery key wrap exists for this vault.';
      });
      return;
    }

    try {
      await RecoveryKeyService.unwrapVaultKey(
        wrappedVaultKey: meta.recoveryWrappedKey!,
        iv: meta.recoveryIv!,
        tag: meta.recoveryTag!,
        recoveryKeyBytes: recoveryBytes,
        salt: meta.recoverySalt!,
      );

      // Key is verified and valid! Proceed to Step 1: Set new secret
      setState(() {
        _verifiedRecoveryKey = input;
        _step = 1;
        _errorMessage = null;
      });
    } on RecoveryKeyAuthException {
      // Well-formed but wrong key -> counts as attempt!
      try {
        await ref.read(vaultProvider).recoverVault(
              recoveryKeyString: input,
              newSecret: 'dummy_secret',
              newCredentialType: CredentialType.pin,
            );
      } catch (_) {}

      final newLockout = await vaultService.getRemainingRecoveryLockoutSeconds();
      setState(() {
        if (newLockout > 0) {
          _errorMessage = 'Locked out. Try again in ${newLockout}s';
        } else {
          _errorMessage = 'Incorrect recovery key. Please check your paper copy.';
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Recovery error: $e';
      });
    }
  }

  void _onSecretInput(String secret) {
    setState(() {
      _errorMessage = null;
      _isPatternError = false;
      if (_step == 1) {
        _newSecret = secret;
      } else if (_step == 2) {
        _confirmSecret = secret;
      }
    });
  }

  void _proceedStep1() {
    if (_selectedType == CredentialType.pin) {
      if (_newSecret.length < 6) {
        setState(() {
          _errorMessage = 'PIN must be at least 6 digits';
        });
        return;
      }
    } else {
      if (_newSecret.split('-').length < 5) {
        setState(() {
          _errorMessage = 'Pattern must connect at least 5 dots';
          _isPatternError = true;
        });
        return;
      }
    }

    setState(() {
      _step = 2;
      _confirmSecret = '';
      _errorMessage = null;
      _isPatternError = false;
      _patternResetKey++;
    });
  }

  Future<void> _proceedStep2() async {
    if (_newSecret != _confirmSecret) {
      if (_selectedType == CredentialType.pattern) {
        setState(() {
          _errorMessage = 'Patterns do not match. Please try again.';
          _isPatternError = true;
          _isTransitioning = true;
          _confirmSecret = '';
        });
        await Future.delayed(const Duration(milliseconds: 700));
        if (mounted) {
          setState(() {
            _step = 1;
            _newSecret = '';
            _confirmSecret = '';
            _patternResetKey++;
            _isPatternError = false;
            _isTransitioning = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'PINs do not match. Please try again.';
          _isPatternError = true;
          _confirmSecret = '';
        });
      }
      return;
    }

    try {
      final vaultNotifier = ref.read(vaultProvider);
      await vaultNotifier.recoverVault(
        recoveryKeyString: _verifiedRecoveryKey!,
        newSecret: _newSecret,
        newCredentialType: _selectedType,
      );

      if (mounted) {
        AppSnackBar.show(context, message: 'New secret set. Vault unlocked.');
        if (Navigator.of(context).canPop()) {
          context.pop(true);
        } else {
          context.go('/locked');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Recovery failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultProvider).state;
    final isLockedOut = vaultState.remainingRecoveryLockoutSeconds > 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (vaultState.isDeriving) {
      return Scaffold(
        appBar: AppBar(title: const Text('Recovering vault')),
        body: const Center(
          child: LoadingState(message: 'Securing new secret...'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recover vault'),
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (_isTransitioning) return;
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
                if (_step == 0) ...[
                  const Icon(Icons.vpn_key_rounded, size: 56, color: AppColors.primary),
                  const SizedBox(height: Spacing.sm),
                  const Text(
                    'Enter your recovery key',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: Spacing.xs),
                  const Text(
                    'Enter the 28-character recovery key written on paper to reset your secret without losing notes.',
                    style: TextStyle(fontSize: 13, color: AppColors.greyDark),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.md),

                  // Recovery Lockout Warning
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
                            'Locked out. Try again in ${vaultState.remainingRecoveryLockoutSeconds}s',
                            style: const TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                  ],

                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Spacing.sm),
                  ],

                  TextField(
                    controller: _recoveryKeyController,
                    enabled: !isLockedOut,
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
                  ElevatedButton(
                    onPressed: isLockedOut ? null : _verifyRecoveryKey,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      minimumSize: const Size(220, 48),
                    ),
                    child: const Text('Verify Recovery Key'),
                  ),
                ] else if (_step == 1) ...[
                  // Step 1: Set NEW PIN or Pattern (R6)
                  SegmentedButton<CredentialType>(
                    segments: const [
                      ButtonSegment(
                        value: CredentialType.pin,
                        label: Text('PIN (min 6)'),
                        icon: Icon(Icons.pin_outlined),
                      ),
                      ButtonSegment(
                        value: CredentialType.pattern,
                        label: Text('Pattern (min 5)'),
                        icon: Icon(Icons.pattern_outlined),
                      ),
                    ],
                    selected: {_selectedType},
                    onSelectionChanged: (selected) {
                      setState(() {
                        _selectedType = selected.first;
                        _newSecret = '';
                        _confirmSecret = '';
                        _errorMessage = null;
                        _isPatternError = false;
                        _patternResetKey++;
                      });
                    },
                  ),
                  const SizedBox(height: Spacing.md),
                  Text(
                    _selectedType == CredentialType.pin
                        ? 'Enter your new PIN'
                        : 'Draw your new pattern',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    _selectedType == CredentialType.pin
                        ? 'Minimum 6 digits'
                        : 'Connect at least 5 dots without repeats',
                    style: const TextStyle(fontSize: 13, color: AppColors.greyDark),
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

                  if (_selectedType == CredentialType.pin) ...[
                    PinPadWidget(
                      pin: _newSecret,
                      minDigits: 6,
                      onPinChanged: _onSecretInput,
                    ),
                    const SizedBox(height: Spacing.md),
                    ElevatedButton(
                      onPressed: _newSecret.length >= 6 ? _proceedStep1 : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        minimumSize: const Size(200, 48),
                      ),
                      child: const Text('Continue'),
                    ),
                  ] else ...[
                    PatternLockWidget(
                      key: ValueKey('recovery_pattern_step1_$_patternResetKey'),
                      minDots: 5,
                      isError: _isPatternError,
                      onPatternComplete: (dots) {
                        _onSecretInput(dots.join('-'));
                        _proceedStep1();
                      },
                    ),
                  ],
                ] else if (_step == 2) ...[
                  // Step 2: Confirm new secret
                  Text(
                    _selectedType == CredentialType.pin
                        ? 'Confirm your new PIN'
                        : 'Confirm your new pattern',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    'Enter the same ${_selectedType == CredentialType.pin ? "PIN" : "pattern"} again',
                    style: const TextStyle(fontSize: 13, color: AppColors.greyDark),
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

                  if (_selectedType == CredentialType.pin) ...[
                    PinPadWidget(
                      pin: _confirmSecret,
                      minDigits: 6,
                      onPinChanged: _onSecretInput,
                    ),
                    const SizedBox(height: Spacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _step = 1;
                              _confirmSecret = '';
                              _errorMessage = null;
                            });
                          },
                          child: const Text('Back'),
                        ),
                        const SizedBox(width: Spacing.md),
                        ElevatedButton(
                          onPressed: _confirmSecret.length >= 6 ? _proceedStep2 : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.white,
                            minimumSize: const Size(140, 48),
                          ),
                          child: const Text('Confirm'),
                        ),
                      ],
                    ),
                  ] else ...[
                    PatternLockWidget(
                      key: ValueKey('recovery_pattern_step2_$_patternResetKey'),
                      minDots: 5,
                      isEnabled: !_isTransitioning,
                      isError: _isPatternError,
                      onPatternComplete: (dots) {
                        if (_isTransitioning) return;
                        _onSecretInput(dots.join('-'));
                        _proceedStep2();
                      },
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
