import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/spacing.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppSpacing.vGapLg,
            // App Shield Icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shield_outlined,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            AppSpacing.vGapMd,
            Text(
              'Privacy Notes',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            AppSpacing.vGapXs,
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(
                'Version 1.0.0',
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            AppSpacing.vGapXl,
            // Core Privacy Statement
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: AppSpacing.borderRadiusMd,
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              color: AppColors.primary.withValues(alpha: 0.05),
              child: Padding(
                padding: AppSpacing.paddingLg,
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          color: AppColors.primary,
                        ),
                        AppSpacing.hGapSm,
                        Text(
                          'Our Privacy Guarantee',
                          style: textTheme.titleMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    AppSpacing.vGapSm,
                    Text(
                      'Nothing leaves your device. All notes, folders, checklists, and cryptographic encryption keys remain strictly on your local hardware. There are no tracking scripts, no third-party telemetry, no cloud sync, and absolutely no internet permissions in this application.',
                      style: textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AppSpacing.vGapLg,
            // Technical Architecture Items
            _buildArchitectureCard(
              context,
              icon: Icons.lock_outline,
              title: 'Hardware-Backed SQLCipher',
              description: 'Database is encrypted at rest using AES-256 with keys secured in Android Keystore.',
            ),
            AppSpacing.vGapSm,
            _buildArchitectureCard(
              context,
              icon: Icons.public_off_outlined,
              title: 'No Internet Permission',
              description: 'The app binary requests zero network permissions (INTERNET is absent from AndroidManifest).',
            ),
            AppSpacing.vGapSm,
            _buildArchitectureCard(
              context,
              icon: Icons.folder_shared_outlined,
              title: 'Storage Access Framework',
              description: 'Text exports use Android SAF, keeping full storage permissions completely off your device.',
            ),
            AppSpacing.vGapSm,
            _buildArchitectureCard(
              context,
              icon: Icons.enhanced_encryption_outlined,
              title: 'Locked Notes Cryptography',
              description: 'Locked notes are encrypted with your secret using AES-256-GCM with PBKDF2 key derivation and cannot be recovered if you forget it.',
            ),
            AppSpacing.vGapSm,
            _buildArchitectureCard(
              context,
              icon: Icons.code_outlined,
              title: 'Open Source & Transparent',
              description: 'Licensed under the Apache 2.0 license. Fully inspectable code with no proprietary lock-in.',
            ),
            AppSpacing.vGapXl,
          ],
        ),
      ),
    );
  }

  Widget _buildArchitectureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderRadiusMd,
        side: BorderSide(
          color: theme.colorScheme.outlineVariant,
          width: 1.0,
        ),
      ),
      child: Padding(
        padding: AppSpacing.paddingLg,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    description,
                    style: textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
