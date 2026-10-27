import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/spacing.dart';

class PinPadWidget extends StatelessWidget {
  final String pin;
  final int minDigits;
  final ValueChanged<String> onPinChanged;
  final VoidCallback? onSubmit;
  final bool isEnabled;

  const PinPadWidget({
    super.key,
    required this.pin,
    this.minDigits = 6,
    required this.onPinChanged,
    this.onSubmit,
    this.isEnabled = true,
  });

  void _onDigitTap(String digit) {
    if (!isEnabled) return;
    if (pin.length < 12) {
      final newPin = pin + digit;
      onPinChanged(newPin);
    }
  }

  void _onDeleteTap() {
    if (!isEnabled || pin.isEmpty) return;
    final newPin = pin.substring(0, pin.length - 1);
    onPinChanged(newPin);
  }

  void _onClearTap() {
    if (!isEnabled || pin.isEmpty) return;
    onPinChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Masked PIN dots indicator
        Semantics(
          label: 'PIN entered: ${pin.length} digits',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                max(pin.length, minDigits),
                (index) {
                  final isFilled = index < pin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: Spacing.xs),
                    width: isFilled ? 16 : 12,
                    height: isFilled ? 16 : 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled
                          ? AppColors.primary
                          : (isDark ? AppColors.charcoal : AppColors.greyLight),
                      border: Border.all(
                        color: isFilled ? AppColors.primary : AppColors.greyDark,
                        width: 1.5,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        // Numpad Grid
        Container(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            children: [
              _buildRow(context, ['1', '2', '3']),
              const SizedBox(height: Spacing.sm),
              _buildRow(context, ['4', '5', '6']),
              const SizedBox(height: Spacing.sm),
              _buildRow(context, ['7', '8', '9']),
              const SizedBox(height: Spacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    context,
                    icon: Icons.clear,
                    semanticLabel: 'Clear PIN',
                    onTap: _onClearTap,
                  ),
                  _buildDigitButton(context, '0'),
                  _buildActionButton(
                    context,
                    icon: Icons.backspace_outlined,
                    semanticLabel: 'Backspace',
                    onTap: _onDeleteTap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  int max(int a, int b) => a > b ? a : b;

  Widget _buildRow(BuildContext context, List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: digits.map((d) => _buildDigitButton(context, d)).toList(),
    );
  }

  Widget _buildDigitButton(BuildContext context, String digit) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: 'Digit $digit',
      child: Material(
        color: isDark ? AppColors.surfaceDark : AppColors.cardLight,
        shape: const CircleBorder(),
        elevation: 1,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: isEnabled ? () => _onDigitTap(digit) : null,
          child: Container(
            width: 68,
            height: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? AppColors.charcoal : AppColors.greyLight,
              ),
            ),
            child: Text(
              digit,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: isEnabled
                    ? (isDark ? AppColors.white : AppColors.textPrimary)
                    : AppColors.greyDark,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: isEnabled ? onTap : null,
          child: Container(
            width: 68,
            height: 68,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 24,
              color: isEnabled
                  ? (isDark ? AppColors.white : AppColors.textPrimary)
                  : AppColors.greyDark,
            ),
          ),
        ),
      ),
    );
  }
}
