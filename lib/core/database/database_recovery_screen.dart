import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

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

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_clock_outlined,
                  size: 40,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Vault Access Error',
                style: textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'The encrypted database file is present on your device, but the hardware Keystore encryption key could not be accessed.',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Your encrypted notes remain safe and untouched on disk. Please unlock your device or retry to re-establish secure access.',
                style: textTheme.bodySmall,
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.refresh, size: 20),
                  label: Text('Retry Access', style: textTheme.labelLarge?.copyWith(color: AppColors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
