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

class VaultSetupScreen extends ConsumerStatefulWidget {
  final bool isChangingSecret;

  const VaultSetupScreen({
    super.key,
    this.isChangingSecret = false,
  });

  @override
  ConsumerState<VaultSetupScreen> createState() => _VaultSetupScreenState();
}

class _VaultSetupScreenState extends ConsumerState<VaultSetupScreen> {
  CredentialType _currentCredentialType = CredentialType.pin;
  CredentialType _selectedType = CredentialType.pin;
  int _step = 1; // 0 = current secret (if changing), 1 = new secret, 2 = confirm secret, 3 = show recovery key, 4 = retype recovery key
  String _currentSecret = '';
  String _firstSecret = '';
  String _confirmSecret = '';
  String? _generatedRecoveryKey;
  final TextEditingController _retypeController = TextEditingController();
  String? _errorMessage;
  bool _isPatternError = false;
  int _patternResetKey = 0;
  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();
    SecurityWindowService.enableSecure();
    if (widget.isChangingSecret) {
      _currentCredentialType = ref.read(vaultProvider).credentialType;
      _selectedType = _currentCredentialType;
      _step = 0; // Require current secret first (B1)
    } else {
      _step = 1;
    }
  }

  @override
  void dispose() {
    _retypeController.dispose();
    SecurityWindowService.disableSecure();
    super.dispose();
  }

  void _onTypeChanged(CredentialType type) {
    setState(() {
      _selectedType = type;
      _step = 1;
      _firstSecret = '';
      _confirmSecret = '';
      _errorMessage = null;
      _isPatternError = false;
      _isTransitioning = false;
      _patternResetKey++;
    });
  }

  void _onSecretInput(String secret) {
    setState(() {
      _errorMessage = null;
      _isPatternError = false;
      if (_step == 0) {
        _currentSecret = secret;
      } else if (_step == 1) {
        _firstSecret = secret;
      } else if (_step == 2) {
        _confirmSecret = secret;
      }
    });
  }

  Future<void> _proceedStep0() async {
    if (_currentCredentialType == CredentialType.pin) {
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
        _firstSecret = '';
        _confirmSecret = '';
        _errorMessage = null;
        _isPatternError = false;
        _patternResetKey++;
      });
    } on SecretBoxAuthenticationError {
      setState(() {
        _errorMessage = 'Current secret is incorrect.';
        _isPatternError = true;
        _currentSecret = '';
        _patternResetKey++;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Current secret is incorrect.';
        _isPatternError = true;
        _currentSecret = '';
        _patternResetKey++;
      });
    }
  }

  Future<void> _proceedStep1() async {
    if (_selectedType == CredentialType.pin) {
      if (_firstSecret.length < 6) {
        setState(() {
          _errorMessage = 'PIN must be at least 6 digits';
        });
        return;
      }
    } else {
      if (_firstSecret.split('-').length < 5) {
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
      _isTransitioning = false;
      _patternResetKey++;
    });
  }

  Future<void> _proceedStep2() async {
    if (_firstSecret != _confirmSecret) {
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
            _firstSecret = '';
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

    if (widget.isChangingSecret) {
      try {
        final vaultNotifier = ref.read(vaultProvider);
        await vaultNotifier.changeSecret(
          currentSecret: _currentSecret,
          newSecret: _firstSecret,
          newCredentialType: _selectedType,
        );
        if (mounted) {
          AppSnackBar.show(context, message: 'Vault secret updated');
          context.pop(true);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Setup failed: $e';
          });
        }
      }
    } else {
      // Mandatory Step 3: Show recovery key (R4)
      setState(() {
        _step = 3;
        _generatedRecoveryKey ??= RecoveryKeyService.generateKey();
        _retypeController.clear();
        _errorMessage = null;
        _isPatternError = false;
      });
    }
  }

  void _proceedStep3() {
    setState(() {
      _step = 4;
      _errorMessage = null;
    });
  }

  Future<void> _proceedStep4() async {
    final typed = RecoveryKeyService.normalize(_retypeController.text);
    final expected = RecoveryKeyService.normalize(_generatedRecoveryKey ?? '');

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
      await vaultNotifier.setupVault(
        secret: _firstSecret,
        credentialType: _selectedType,
        recoveryKeyString: _generatedRecoveryKey!,
      );
      if (mounted) {
        AppSnackBar.show(context, message: 'Locked notes vault ready');
        if (Navigator.of(context).canPop()) {
          context.pop(true);
        } else {
          context.go('/locked');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Setup failed: $e';
        });
      }
    }
  }

  CredentialType get _activeCredentialType => (_step == 0) ? _currentCredentialType : _selectedType;

  String get _stepTitle {
    if (_step == 0) {
      return _currentCredentialType == CredentialType.pin ? 'Enter your current PIN' : 'Draw your current pattern';
    } else if (_step == 1) {
      return _selectedType == CredentialType.pin ? 'Enter your new PIN' : 'Draw your pattern';
    } else if (_step == 2) {
      return _selectedType == CredentialType.pin ? 'Confirm your PIN' : 'Confirm your pattern';
    } else if (_step == 3) {
      return 'Write down your recovery key';
    } else {
      return 'Confirm recovery key';
    }
  }

  String get _stepSubtitle {
    if (_step == 0) {
      return 'Confirm current secret before setting a new credential';
    } else if (_step == 1) {
      return _selectedType == CredentialType.pin
          ? 'Minimum 6 digits'
          : 'Connect at least 5 dots without repeats';
    } else if (_step == 2) {
      return 'Enter the same ${_selectedType == CredentialType.pin ? "PIN" : "pattern"} again';
    } else if (_step == 3) {
      return 'Keep this key safe. You will need to confirm it in the next step.';
    } else {
      return 'Type the whole key correctly to finalize vault creation';
    }
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultProvider).state;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseStep = widget.isChangingSecret ? 0 : 1;

    if (vaultState.isDeriving) {
      return Scaffold(
        appBar: AppBar(title: const Text('Securing vault')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LoadingState(message: 'Securing vault key...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isChangingSecret ? 'Change secret' : 'Set up locked notes'),
        leading: _step > baseStep
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (_isTransitioning) return;
                  setState(() {
                    _step = _step - 1;
                    _errorMessage = null;
                    _isPatternError = false;
                    _patternResetKey++;
                  });
                },
              )
            : null,
      ),
      body: PopScope(
        canPop: _step == baseStep && !_isTransitioning,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _step > baseStep && !_isTransitioning) {
            setState(() {
              _step = _step - 1;
              _errorMessage = null;
              _isPatternError = false;
              _patternResetKey++;
            });
          }
        },
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Plain warning banner (D2, R4)
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
                            _step >= 3
                                ? 'Write it on paper; whoever has this key can open all your notes; it cannot be shown again.'
                                : 'If you forget your secret, your written paper recovery key is the only way to recover your notes.',
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

                  // Credential type selector (PIN vs Pattern) (D1)
                  if (_step == 1) ...[
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
                        _onTypeChanged(selected.first);
                      },
                    ),
                    const SizedBox(height: Spacing.sm),
                    if (_selectedType == CredentialType.pattern)
                      Container(
                        padding: const EdgeInsets.all(Spacing.sm),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.charcoal : AppColors.greyLight,
                          borderRadius: BorderRadius.circular(Spacing.xs),
                        ),
                        child: const Text(
                          'Notice: Pattern lock is not screen-reader friendly. We strongly recommend choosing PIN for TalkBack users.',
                          style: TextStyle(fontSize: 12, color: AppColors.greyDark),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: Spacing.md),
                  ],

                  // Step Title
                  Text(
                    _stepTitle,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    _stepSubtitle,
                    style: const TextStyle(fontSize: 13, color: AppColors.greyDark),
                    textAlign: TextAlign.center,
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

                  // Step 0, 1, 2: Secret input (PIN or Pattern)
                  if (_step <= 2) ...[
                    if (_activeCredentialType == CredentialType.pin)
                      PinPadWidget(
                        pin: _step == 0 ? _currentSecret : (_step == 1 ? _firstSecret : _confirmSecret),
                        minDigits: 6,
                        onPinChanged: _onSecretInput,
                      )
                    else
                      PatternLockWidget(
                        key: ValueKey('pattern_setup_${_step}_$_patternResetKey'),
                        minDots: 5,
                        isEnabled: !_isTransitioning,
                        isError: _isPatternError,
                        onPatternComplete: (dots) {
                          if (_isTransitioning) return;
                          final patternString = dots.join('-');
                          _onSecretInput(patternString);
                          if (_step == 0) {
                            _proceedStep0();
                          } else if (_step == 1) {
                            _proceedStep1();
                          } else {
                            _proceedStep2();
                          }
                        },
                      ),

                    const SizedBox(height: Spacing.md),

                    // PIN Proceed Buttons
                    if (_activeCredentialType == CredentialType.pin) ...[
                      if (_step == 0)
                        ElevatedButton(
                          onPressed: _currentSecret.length >= 6 ? _proceedStep0 : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.white,
                            minimumSize: const Size(200, 48),
                          ),
                          child: const Text('Continue'),
                        )
                      else if (_step == 1)
                        ElevatedButton(
                          onPressed: _firstSecret.length >= 6 ? _proceedStep1 : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.white,
                            minimumSize: const Size(200, 48),
                          ),
                          child: const Text('Continue'),
                        )
                      else
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  _step = 1;
                                  _confirmSecret = '';
                                  _errorMessage = null;
                                  _patternResetKey++;
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
                    ],
                  ] else if (_step == 3) ...[
                    // Step 3: Show recovery key (R1, R2, R4)
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
                            _generatedRecoveryKey ?? '',
                            key: const ValueKey('recovery_key_display_text'),
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
                      'This recovery key can decrypt all your notes if you forget your secret. Keep it secret and write it down now.',
                      style: TextStyle(fontSize: 12, color: AppColors.greyDark),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Spacing.lg),
                    ElevatedButton(
                      onPressed: _proceedStep3,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        minimumSize: const Size(220, 48),
                      ),
                      child: const Text('I have written it down'),
                    ),
                  ] else if (_step == 4) ...[
                    // Step 4: Mandatory re-type confirmation (R4)
                    TextField(
                      controller: _retypeController,
                      autofocus: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Enter recovery key',
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
                              _step = 3;
                              _errorMessage = null;
                            });
                          },
                          child: const Text('View key again'),
                        ),
                        const SizedBox(width: Spacing.md),
                        ElevatedButton(
                          onPressed: _proceedStep4,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.white,
                            minimumSize: const Size(160, 48),
                          ),
                          child: const Text('Confirm & Create Vault'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
