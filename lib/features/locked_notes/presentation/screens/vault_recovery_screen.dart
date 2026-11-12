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
import 'package:privacy_notes/l10n/l10n_extension.dart';
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
    final l10n = contextL10n(context);
    final vaultService = ref.read(vaultServiceProvider);
    final lockoutSeconds = await vaultService.getRemainingRecoveryLockoutSeconds();
    if (lockoutSeconds > 0) {
      setState(() {
        _errorMessage = l10n.lockedOutTryAgainIn(lockoutSeconds);
      });
      return;
    }

    final input = _recoveryKeyController.text.trim();
    if (input.isEmpty) {
      setState(() {
        _errorMessage = l10n.pleaseEnterYourRecoveryKey;
      });
      return;
    }

    // 1. Validation & Checksum (R6: does not count as attempt if checksum fails)
    final Uint8List recoveryBytes;
    try {
      recoveryBytes = RecoveryKeyService.decodeKey(input);
    } on RecoveryKeyChecksumException {
      setState(() {
        _errorMessage = l10n.checkForTypingMistakes;
      });
      return;
    } on RecoveryKeyFormatException {
      setState(() {
        _errorMessage = l10n.checkForTypingMistakes;
      });
      return;
    }

    // 2. Test decryption against stored recovery wrap (R6: wrong key counts as attempt)
    final meta = await vaultService.getVaultMetadata();
    if (meta == null || !meta.hasRecoveryKey) {
      setState(() {
        _errorMessage = l10n.noRecoveryKeyWrapExists;
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
          _errorMessage = l10n.lockedOutTryAgainIn(newLockout);
        } else {
          _errorMessage = l10n.incorrectRecoveryKeyCheckPaper;
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = l10n.recoveryError;
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
    final l10n = contextL10n(context);
    if (_selectedType == CredentialType.pin) {
      if (_newSecret.length < 6) {
        setState(() {
          _errorMessage = l10n.pinMustBeAtLeastSixDigits;
        });
        return;
      }
    } else {
      if (_newSecret.split('-').length < 5) {
        setState(() {
          _errorMessage = l10n.patternMustConnectAtLeastFiveDots;
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
    final l10n = contextL10n(context);
    if (_newSecret != _confirmSecret) {
      if (_selectedType == CredentialType.pattern) {
        setState(() {
          _errorMessage = l10n.patternsDoNotMatch;
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
          _errorMessage = l10n.pinsDoNotMatch;
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
        final noticeDate = ref.read(vaultProvider).state.pendingResetNoticeDate;
        if (noticeDate != null) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.security, color: AppColors.error),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: Text(
                      l10n.securityNotice,
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: Text(
                l10n.vaultResetCancelledNotice(noticeDate.toLocal().toString().split('.')[0]),
                style: Theme.of(ctx).textTheme.bodyMedium,
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

        AppSnackBar.show(context, message: l10n.newSecretSetVaultUnlocked);
        if (Navigator.of(context).canPop()) {
          context.pop(true);
        } else {
          context.go('/locked');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
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
    final isLockedOut = vaultState.remainingRecoveryLockoutSeconds > 0;
    final isDark = theme.brightness == Brightness.dark;

    if (vaultState.isDeriving) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.recoveringVault)),
        body: Center(
          child: LoadingState(message: l10n.securingNewSecret),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.recoverVaultTitle),
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: l10n.back,
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
          padding: AppSpacing.screenPadding,
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_step == 0) ...[
                  const Icon(Icons.vpn_key_rounded, size: 56, color: AppColors.primary),
                  AppSpacing.vGapSm,
                  Text(
                    l10n.enterRecoveryKeyHeading,
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    l10n.enter28CharRecoveryKeyDesc,
                    style: textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.vGapMd,

                  // Recovery Lockout Warning
                  if (isLockedOut) ...[
                    Container(
                      padding: AppSpacing.paddingSm,
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: isDark ? 0.25 : 0.1),
                        borderRadius: AppSpacing.borderRadiusSm,
                        border: Border.all(color: AppColors.error),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_clock, color: AppColors.error, size: 20),
                          AppSpacing.hGapSm,
                          Expanded(
                            child: Text(
                              l10n.lockedOutTryAgainIn(vaultState.remainingRecoveryLockoutSeconds),
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppSpacing.vGapMd,
                  ],

                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.vGapSm,
                  ],

                  TextField(
                    controller: _recoveryKeyController,
                    enabled: !isLockedOut,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: l10n.enterRecoveryKeyLabel,
                      hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.password_rounded),
                    ),
                    onSubmitted: (_) {
                      if (!isLockedOut) _verifyRecoveryKey();
                    },
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    l10n.recoveryKeyDashesHint,
                    style: textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  AppSpacing.vGapLg,
                  ElevatedButton(
                    onPressed: isLockedOut ? null : _verifyRecoveryKey,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      minimumSize: const Size(220, 48),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppSpacing.borderRadiusSm,
                      ),
                    ),
                    child: Text(l10n.verifyRecoveryKeyButton),
                  ),
                ] else if (_step == 1) ...[
                  // Step 1: Set NEW PIN or Pattern (R6)
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
                  AppSpacing.vGapSm,
                  if (_selectedType == CredentialType.pattern)
                    Container(
                      padding: AppSpacing.paddingSm,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: AppSpacing.borderRadiusSm,
                      ),
                      child: Column(
                        children: [
                          Text(
                            l10n.patternAccessibilityNotice,
                            style: textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          AppSpacing.vGapXs,
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedType = CredentialType.pin;
                                _newSecret = '';
                                _confirmSecret = '';
                                _errorMessage = null;
                                _isPatternError = false;
                                _patternResetKey++;
                              });
                            },
                            icon: const Icon(Icons.pin_outlined, size: 16),
                            label: Text(l10n.usePinInstead),
                          ),
                        ],
                      ),
                    ),
                  AppSpacing.vGapMd,
                  Text(
                    _selectedType == CredentialType.pin
                        ? l10n.enterNewPinPrompt
                        : l10n.drawYourPatternPrompt,
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    _selectedType == CredentialType.pin
                        ? l10n.minSixDigits
                        : l10n.connectAtLeastFiveDots,
                    style: textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  AppSpacing.vGapMd,

                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.vGapSm,
                  ],

                  if (_selectedType == CredentialType.pin) ...[
                    PinPadWidget(
                      pin: _newSecret,
                      minDigits: 6,
                      onPinChanged: _onSecretInput,
                    ),
                    AppSpacing.vGapMd,
                    ElevatedButton(
                      onPressed: _newSecret.length >= 6 ? _proceedStep1 : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        minimumSize: const Size(200, 48),
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppSpacing.borderRadiusSm,
                        ),
                      ),
                      child: Text(l10n.continueAction),
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
                        ? l10n.confirmYourPin
                        : l10n.confirmYourPattern,
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    l10n.enterSameSecretAgain(
                      _selectedType == CredentialType.pin ? l10n.pinCredential : l10n.patternCredential,
                    ),
                    style: textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  AppSpacing.vGapMd,

                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    AppSpacing.vGapSm,
                  ],

                  if (_selectedType == CredentialType.pin) ...[
                    PinPadWidget(
                      pin: _confirmSecret,
                      minDigits: 6,
                      onPinChanged: _onSecretInput,
                    ),
                    AppSpacing.vGapMd,
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
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(120, 48),
                            shape: const RoundedRectangleBorder(
                              borderRadius: AppSpacing.borderRadiusSm,
                            ),
                          ),
                          child: Text(l10n.back),
                        ),
                        AppSpacing.hGapMd,
                        ElevatedButton(
                          onPressed: _confirmSecret.length >= 6 ? _proceedStep2 : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.white,
                            minimumSize: const Size(140, 48),
                            shape: const RoundedRectangleBorder(
                              borderRadius: AppSpacing.borderRadiusSm,
                            ),
                          ),
                          child: Text(l10n.confirm),
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
