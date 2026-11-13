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
import '../../../../l10n/l10n_extension.dart';
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
  bool _isLinkingExistingKey = false;

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
          final l10n = contextL10n(context);
          AppSnackBar.show(context, message: l10n.secretChangedSuccessfully);
          context.pop(true);
        }
      } catch (e, st) {
        debugPrint('Vault changeSecret error: $e\n$st');
        if (mounted) {
          final l10n = contextL10n(context);
          setState(() {
            _errorMessage = '${l10n.vaultSetupFailed} ($e)';
          });
        }
      }
    } else {
      // Check if a backup subkey already exists (Case 4: single root key architecture)
      final vaultService = ref.read(vaultServiceProvider);
      final hasSubkey = await vaultService.hasBackupSubkey();
      if (hasSubkey) {
        setState(() {
          _isLinkingExistingKey = true;
          _step = 3;
          _retypeController.clear();
          _errorMessage = null;
          _isPatternError = false;
        });
      } else {
        setState(() {
          _isLinkingExistingKey = false;
          _step = 3;
          _generatedRecoveryKey ??= RecoveryKeyService.generateKey();
          _retypeController.clear();
          _errorMessage = null;
          _isPatternError = false;
        });
      }
    }
  }

  Future<void> _proceedStep3Linking() async {
    final l10n = contextL10n(context);
    final typed = RecoveryKeyService.normalize(_retypeController.text);
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

    final vaultService = ref.read(vaultServiceProvider);
    final isMatch = await vaultService.verifyRecoveryKeyAgainstBackupSubkey(typed);
    if (!isMatch) {
      setState(() {
        _errorMessage = l10n.invalidRecoveryKey;
      });
      return;
    }

    try {
      final vaultNotifier = ref.read(vaultProvider);
      await vaultNotifier.setupVault(
        secret: _firstSecret,
        credentialType: _selectedType,
        recoveryKeyString: typed,
      );
      if (mounted) {
        final l10n = contextL10n(context);
        AppSnackBar.show(context, message: l10n.lockedNotesVaultReady);
        if (Navigator.of(context).canPop()) {
          context.pop(true);
        } else {
          context.go('/locked');
        }
      }
    } catch (e, st) {
      debugPrint('Vault setup linking error: $e\n$st');
      if (mounted) {
        final l10n = contextL10n(context);
        setState(() {
          _errorMessage = '${l10n.vaultSetupFailed} ($e)';
        });
      }
    }
  }

  void _proceedStep3() {
    setState(() {
      _step = 4;
      _errorMessage = null;
    });
  }

  Future<void> _proceedStep4() async {
    final l10n = contextL10n(context);
    final typed = RecoveryKeyService.normalize(_retypeController.text);
    final expected = RecoveryKeyService.normalize(_generatedRecoveryKey ?? '');

    if (typed.isEmpty) {
      setState(() {
        _errorMessage = l10n.pleaseEnterYourRecoveryKey;
      });
      return;
    }

    if (typed != expected) {
      setState(() {
        _errorMessage = l10n.recoveryKeyMismatchError;
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
        AppSnackBar.show(context, message: l10n.lockedNotesVaultReady);
        if (Navigator.of(context).canPop()) {
          context.pop(true);
        } else {
          context.go('/locked');
        }
      }
    } catch (e, st) {
      debugPrint('Vault setup error: $e\n$st');
      if (mounted) {
        setState(() {
          _errorMessage = '${l10n.vaultSetupFailed} ($e)';
        });
      }
    }
  }

  CredentialType get _activeCredentialType => (_step == 0) ? _currentCredentialType : _selectedType;

  String _getStepTitle(AppLocalizations l10n) {
    if (_step == 0) {
      return _currentCredentialType == CredentialType.pin ? l10n.currentPinPrompt : l10n.currentPatternPrompt;
    } else if (_step == 1) {
      return _selectedType == CredentialType.pin ? l10n.enterNewPinPrompt : l10n.drawYourPatternPrompt;
    } else if (_step == 2) {
      return _selectedType == CredentialType.pin ? l10n.confirmYourPin : l10n.confirmYourPattern;
    } else if (_step == 3) {
      return _isLinkingExistingKey ? l10n.enterExistingPaperKeyForVaultTitle : l10n.writeDownRecoveryKey;
    } else {
      return l10n.confirmRecoveryKey;
    }
  }

  String _getStepSubtitle(AppLocalizations l10n) {
    if (_step == 0) {
      return l10n.confirmCurrentSecretSubtitle;
    } else if (_step == 1) {
      return _selectedType == CredentialType.pin
          ? l10n.minSixDigits
          : l10n.connectAtLeastFiveDots;
    } else if (_step == 2) {
      return l10n.enterSameSecretAgain(_selectedType == CredentialType.pin ? l10n.pinCredential : l10n.patternCredential);
    } else if (_step == 3) {
      return _isLinkingExistingKey ? l10n.enterExistingPaperKeyForVaultPrompt : l10n.keepKeySafeSubtitle;
    } else {
      return l10n.typeWholeKeySubtitle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultProvider).state;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final l10n = contextL10n(context);
    final baseStep = widget.isChangingSecret ? 0 : 1;

    if (vaultState.isDeriving) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.securingVault)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LoadingState(message: l10n.securingVaultKey),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isChangingSecret ? l10n.changeSecretTitle : l10n.setUpLockedNotesTitle),
        leading: _step > baseStep
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: l10n.back,
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
                                ? l10n.paperKeyWarning
                                : l10n.forgotSecretNotice,
                            style: textTheme.bodySmall?.copyWith(
                              color: isDark ? AppColors.white : AppColors.error,
                              fontWeight: FontWeight.w600,
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
                      segments: [
                        ButtonSegment(
                          value: CredentialType.pin,
                          label: Text(l10n.pinMinLength),
                          icon: const Icon(Icons.pin_outlined),
                        ),
                        ButtonSegment(
                          value: CredentialType.pattern,
                          label: Text(l10n.patternMinLength),
                          icon: const Icon(Icons.pattern_outlined),
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
                        child: Column(
                          children: [
                            Text(
                              l10n.patternAccessibilityNotice,
                              style: textTheme.bodySmall?.copyWith(
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: Spacing.xs),
                            TextButton.icon(
                              onPressed: () => _onTypeChanged(CredentialType.pin),
                              icon: const Icon(Icons.pin_outlined, size: 16),
                              label: Text(l10n.usePinInstead),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: Spacing.md),
                  ],

                  // Step Title
                  Text(
                    _getStepTitle(l10n),
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    _getStepSubtitle(l10n),
                    style: textTheme.bodySmall?.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Spacing.md),

                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
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
                        onPatternStart: () {
                          if (_isPatternError || _errorMessage != null) {
                            setState(() {
                              _isPatternError = false;
                              _errorMessage = null;
                            });
                          }
                        },
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
                          child: Text(l10n.continueAction),
                        )
                      else if (_step == 1)
                        ElevatedButton(
                          onPressed: _firstSecret.length >= 6 ? _proceedStep1 : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.white,
                            minimumSize: const Size(200, 48),
                          ),
                          child: Text(l10n.continueAction),
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
                              child: Text(l10n.back),
                            ),
                            const SizedBox(width: Spacing.md),
                            ElevatedButton(
                              onPressed: _confirmSecret.length >= 6 ? _proceedStep2 : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.white,
                                minimumSize: const Size(140, 48),
                              ),
                              child: Text(l10n.confirm),
                            ),
                          ],
                        ),
                    ],
                  ] else if (_step == 3) ...[
                    if (_isLinkingExistingKey) ...[
                      TextField(
                        controller: _retypeController,
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
                      const SizedBox(height: Spacing.xs),
                      Text(
                        l10n.recoveryKeyDashesHint,
                        style: textTheme.bodySmall?.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                      const SizedBox(height: Spacing.lg),
                      ElevatedButton(
                        onPressed: _proceedStep3Linking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.white,
                          minimumSize: const Size(220, 48),
                        ),
                        child: Text(l10n.linkAndCompleteSetup),
                      ),
                    ] else ...[
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
                              style: textTheme.titleMedium?.copyWith(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Spacing.sm),
                      Text(
                        l10n.recoveryKeyExplanation,
                        style: textTheme.bodySmall?.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
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
                        child: Text(l10n.iHaveWrittenItDown),
                      ),
                    ],
                  ] else if (_step == 4) ...[
                    // Step 4: Mandatory re-type confirmation (R4)
                    TextField(
                      controller: _retypeController,
                      autofocus: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      enableIMEPersonalizedLearning: false,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: l10n.enterRecoveryKeyLabel,
                        hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.edit_note_outlined),
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
                    Text(
                      l10n.recoveryKeyDashesHint,
                      style: textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
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
                          child: Text(l10n.viewKeyAgain),
                        ),
                        const SizedBox(width: Spacing.md),
                        ElevatedButton(
                          onPressed: _proceedStep4,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.white,
                            minimumSize: const Size(160, 48),
                          ),
                          child: Text(l10n.confirmAndCreateVault),
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
