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
import 'package:privacy_notes/l10n/l10n_extension.dart';
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
    final l10n = contextL10n(context);
    final vaultNotifier = ref.read(vaultProvider);
    final credType = vaultNotifier.credentialType;

    if (credType == CredentialType.pin) {
      if (_currentSecret.length < 6) {
        setState(() {
          _errorMessage = l10n.pinMustBeAtLeastSixDigits;
        });
        return;
      }
    } else {
      if (_currentSecret.split('-').length < 5) {
        setState(() {
          _errorMessage = l10n.patternMustConnectAtLeastFiveDots;
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
        _errorMessage = l10n.currentSecretIncorrect;
        _isPatternError = true;
        _currentSecret = '';
        _patternResetKey++;
      });
    } catch (_) {
      setState(() {
        _errorMessage = l10n.currentSecretIncorrect;
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
    final l10n = contextL10n(context);
    final typed = RecoveryKeyService.normalize(_retypeController.text);
    final expected = RecoveryKeyService.normalize(_generatedKey ?? '');

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
      await vaultNotifier.createOrUpdateRecoveryKey(
        currentSecret: _currentSecret,
        recoveryKeyString: _generatedKey!,
      );
      if (mounted) {
        AppSnackBar.show(
          context,
          message: widget.isRegenerating
              ? l10n.generateNewRecoveryKey
              : l10n.createRecoveryKey,
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = l10n.recoveryFailedWithDetails(e.toString());
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
    final isDark = theme.brightness == Brightness.dark;

    if (vaultState.isDeriving) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.securingRecoveryKey)),
        body: Center(
          child: LoadingState(message: l10n.securingVaultKey),
        ),
      );
    }

    final title = widget.isRegenerating
        ? l10n.regenerateRecoveryKeyTitle
        : l10n.createRecoveryKeyTitle;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: l10n.back,
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
          padding: AppSpacing.screenPadding,
          child: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Warning banner
                Container(
                  width: double.infinity,
                  padding: AppSpacing.paddingMd,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: AppSpacing.borderRadiusSm,
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                      AppSpacing.hGapSm,
                      Expanded(
                        child: Text(
                          _step == 0
                              ? l10n.enterSecretToAuthenticate
                              : l10n.paperKeyWarning,
                          style: textTheme.bodySmall?.copyWith(
                            color: isDark ? AppColors.white : AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
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

                if (_step == 0) ...[
                  Text(
                    vaultState.credentialType == CredentialType.pin
                        ? l10n.currentPinPrompt
                        : l10n.currentPatternPrompt,
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    l10n.confirmSecretPrompt,
                    style: textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  AppSpacing.vGapMd,

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
                    AppSpacing.vGapMd,
                    ElevatedButton(
                      onPressed: _currentSecret.length >= 6 ? _proceedStep0 : null,
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
                      key: ValueKey('recovery_pattern_$_patternResetKey'),
                      minDots: 5,
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
                        _currentSecret = dots.join('-');
                        _proceedStep0();
                      },
                    ),
                  ],
                ] else if (_step == 1) ...[
                  Text(
                    l10n.writeDownRecoveryKey,
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    l10n.paperKeyWarning,
                    style: textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.vGapMd,

                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    padding: AppSpacing.paddingMd,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: AppSpacing.borderRadiusSm,
                      border: Border.all(color: AppColors.primary, width: 1.5),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.vpn_key_rounded, size: 36, color: AppColors.primary),
                        AppSpacing.vGapSm,
                        Text(
                          _generatedKey ?? '',
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
                  AppSpacing.vGapSm,
                  Text(
                    l10n.recoveryKeyExplanation,
                    style: textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.vGapLg,
                  ElevatedButton(
                    onPressed: _proceedStep1,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      minimumSize: const Size(220, 48),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppSpacing.borderRadiusSm,
                      ),
                    ),
                    child: Text(l10n.iHaveWrittenItDown),
                  ),
                ] else if (_step == 2) ...[
                  Text(
                    l10n.confirmRecoveryKey,
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    l10n.typeWholeKeySubtitle,
                    style: textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  AppSpacing.vGapMd,

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
                  AppSpacing.vGapXs,
                  Text(
                    l10n.recoveryKeyDashesHint,
                    style: textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  AppSpacing.vGapLg,
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
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(120, 48),
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppSpacing.borderRadiusSm,
                          ),
                        ),
                        child: Text(l10n.viewKeyAgain),
                      ),
                      AppSpacing.hGapMd,
                      ElevatedButton(
                        onPressed: _proceedStep2,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.white,
                          minimumSize: const Size(160, 48),
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppSpacing.borderRadiusSm,
                          ),
                        ),
                        child: Text(l10n.verifyAndFinish),
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
