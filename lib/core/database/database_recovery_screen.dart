import 'package:flutter/material.dart';
import '../../l10n/l10n_extension.dart';
import '../constants/app_colors.dart';
import '../theme/spacing.dart';

/// Screen displayed when the database file exists on disk but the Android Keystore
/// encryption key cannot be retrieved or read.
/// Strictly presents an explanatory error message and a retry button.
/// Never alters, deletes, or recreates the database file.
class DatabaseRecoveryScreen extends StatelessWidget {
  final VoidCallback onRetry;

  const DatabaseRecoveryScreen({
    super.key,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l10n = contextL10n(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xxl,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Semantics(
                label: 'Vault access error icon',
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: AppColors.errorContainer,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_clock_outlined,
                    size: 40,
                    color: AppColors.error,
                  ),
                ),
              ),
              AppSpacing.vGapXl,
              Text(
                l10n.vaultAccessError,
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              AppSpacing.vGapMd,
              Text(
                l10n.databaseRecoveryMessage,
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppSpacing.borderRadiusMd,
                    ),
                  ),
                  icon: const Icon(Icons.refresh, size: 20),
                  label: Text(
                    l10n.retryAccess,
                    style: textTheme.labelLarge?.copyWith(color: AppColors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
