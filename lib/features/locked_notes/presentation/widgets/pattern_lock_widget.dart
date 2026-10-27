import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/spacing.dart';

class PatternLockWidget extends StatefulWidget {
  final int minDots;
  final ValueChanged<List<int>> onPatternComplete;
  final bool isEnabled;
  final bool isError;
  final String? errorMessage;

  const PatternLockWidget({
    super.key,
    this.minDots = 5,
    required this.onPatternComplete,
    this.isEnabled = true,
    this.isError = false,
    this.errorMessage,
  });

  @override
  State<PatternLockWidget> createState() => _PatternLockWidgetState();
}

class _PatternLockWidgetState extends State<PatternLockWidget> {
  final List<int> _selectedDots = [];
  Offset? _currentTouch;

  // 3x3 grid relative dot centers (0..2 for row, 0..2 for col)
  Offset _getDotCenter(int index, Size size) {
    final row = index ~/ 3;
    final col = index % 3;
    final cellWidth = size.width / 3;
    final cellHeight = size.height / 3;
    return Offset(
      col * cellWidth + cellWidth / 2,
      row * cellHeight + cellHeight / 2,
    );
  }

  int? _findHitDot(Offset touch, Size size) {
    const hitRadius = 36.0;
    for (int i = 0; i < 9; i++) {
      final center = _getDotCenter(i, size);
      if ((touch - center).distance <= hitRadius) {
        return i;
      }
    }
    return null;
  }

  void _onPanStart(DragStartDetails details, Size size) {
    if (!widget.isEnabled) return;
    setState(() {
      _selectedDots.clear();
      _currentTouch = details.localPosition;
      final hit = _findHitDot(details.localPosition, size);
      if (hit != null && !_selectedDots.contains(hit)) {
        _selectedDots.add(hit);
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    if (!widget.isEnabled) return;
    setState(() {
      _currentTouch = details.localPosition;
      final hit = _findHitDot(details.localPosition, size);
      if (hit != null && !_selectedDots.contains(hit)) {
        _selectedDots.add(hit);
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (!widget.isEnabled) return;
    setState(() {
      _currentTouch = null;
    });
    if (_selectedDots.isNotEmpty) {
      final pattern = List<int>.from(_selectedDots);
      widget.onPatternComplete(pattern);
    }
  }

  void clearPattern() {
    setState(() {
      _selectedDots.clear();
      _currentTouch = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const double boardDimension = 280.0;

    return Semantics(
      label: 'Pattern lock grid. Touch and drag across dots to enter pattern.',
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: boardDimension,
              height: boardDimension,
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.cardLight,
                borderRadius: BorderRadius.circular(Spacing.md),
                border: Border.all(
                  color: widget.isError
                      ? AppColors.error
                      : (isDark ? AppColors.charcoal : AppColors.greyLight),
                  width: 1.5,
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    onPanStart: (d) => _onPanStart(d, size),
                    onPanUpdate: (d) => _onPanUpdate(d, size),
                    onPanEnd: _onPanEnd,
                    child: CustomPaint(
                      size: size,
                      painter: _PatternPainter(
                        selectedDots: _selectedDots,
                        currentTouch: _currentTouch,
                        isDark: isDark,
                        isError: widget.isError,
                      ),
                    ),
                  );
                },
              ),
            ),
            if (widget.errorMessage != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                widget.errorMessage!,
                style: const TextStyle(
                  color: AppColors.error,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  final List<int> selectedDots;
  final Offset? currentTouch;
  final bool isDark;
  final bool isError;

  _PatternPainter({
    required this.selectedDots,
    required this.currentTouch,
    required this.isDark,
    required this.isError,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dotColor = isDark ? AppColors.greyDark : AppColors.greyMedium;
    final activeColor = isError ? AppColors.error : AppColors.primary;

    final dotPaint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    final activeDotPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    final haloPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // 1. Draw connecting lines
    if (selectedDots.length > 1) {
      final path = Path();
      final first = _getDotCenter(selectedDots.first, size);
      path.moveTo(first.dx, first.dy);

      for (int i = 1; i < selectedDots.length; i++) {
        final pt = _getDotCenter(selectedDots[i], size);
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, linePaint);
    }

    // 2. Draw line to current touch point
    if (selectedDots.isNotEmpty && currentTouch != null) {
      final last = _getDotCenter(selectedDots.last, size);
      canvas.drawLine(last, currentTouch!, linePaint);
    }

    // 3. Draw dots
    for (int i = 0; i < 9; i++) {
      final center = _getDotCenter(i, size);
      final isSelected = selectedDots.contains(i);

      if (isSelected) {
        canvas.drawCircle(center, 18.0, haloPaint);
        canvas.drawCircle(center, 8.0, activeDotPaint);
      } else {
        canvas.drawCircle(center, 6.0, dotPaint);
      }
    }
  }

  Offset _getDotCenter(int index, Size size) {
    final row = index ~/ 3;
    final col = index % 3;
    final cellWidth = size.width / 3;
    final cellHeight = size.height / 3;
    return Offset(
      col * cellWidth + cellWidth / 2,
      row * cellHeight + cellHeight / 2,
    );
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) {
    return oldDelegate.selectedDots.length != selectedDots.length ||
        oldDelegate.currentTouch != currentTouch ||
        oldDelegate.isError != isError ||
        oldDelegate.isDark != isDark;
  }
}
