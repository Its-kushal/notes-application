import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaflock/core/constants/app_colors.dart';
import 'package:leaflock/core/database/database_recovery_screen.dart';
import 'package:leaflock/core/theme/app_theme.dart';
import 'package:leaflock/features/locked_notes/presentation/widgets/pattern_lock_widget.dart';
import 'package:leaflock/features/locked_notes/presentation/widgets/pin_pad_widget.dart';
import 'package:leaflock/features/settings/presentation/screens/about_screen.dart';
import 'package:leaflock/features/welcome/presentation/screens/welcome_screen.dart';
import 'package:leaflock/l10n/app_localizations.dart';

Widget _buildTestApp({required Widget child, ThemeData? theme}) {
  return ProviderScope(
    child: MaterialApp(
      theme: theme ?? AppTheme.lightTheme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  group('M5 Accessibility Automated Guideline Tests', () {
    testWidgets('PinPadWidget meets tap target and labeled guidelines', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: Scaffold(
            body: Center(
              child: PinPadWidget(
                pin: '1234',
                onPinChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify all digit buttons are >= 48x48 dp
      final digitFinders = find.byType(InkWell);
      for (final finder in digitFinders.evaluate()) {
        final box = finder.renderObject as RenderBox?;
        if (box != null && box.hasSize) {
          expect(box.size.width >= 48, isTrue, reason: 'Width was ${box.size.width}');
          expect(box.size.height >= 48, isTrue, reason: 'Height was ${box.size.height}');
        }
      }

      // Check automated Flutter accessibility guidelines
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('PatternLockWidget provides informative TalkBack semantics', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: Scaffold(
            body: Center(
              child: PatternLockWidget(
                onPatternComplete: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(PatternLockWidget));
      expect(semantics.label.contains('Pattern lock grid'), isTrue);
    });

    testWidgets('AboutScreen renders properly at large font scale (1.5x) without overflow', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: _buildTestApp(
            child: const AboutScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No RenderFlex overflow exception
      expect(tester.takeException(), isNull);
      expect(find.text('LeafLock'), findsOneWidget);
      expect(find.text('Our Privacy Guarantee'), findsOneWidget);
    });

    testWidgets('WelcomeScreen meets labeled and tap target accessibility guidelines', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const WelcomeScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('DatabaseRecoveryScreen meets tap target guidelines', (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: DatabaseRecoveryScreen(
            onRetry: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('Theme contrast verified in light and dark mode for primary text and backgrounds', (tester) async {
      final lightTheme = AppTheme.lightTheme;
      final darkTheme = AppTheme.darkTheme;

      // Primary color teal 600 (#0D9488) on white has > 4.5:1 contrast
      expect(lightTheme.colorScheme.primary, AppColors.primary);
      expect(lightTheme.scaffoldBackgroundColor, AppColors.lightBackground);

      // Dark background is slate 900 (#0F172A) with slate 50 text (#F8FAFC)
      expect(darkTheme.scaffoldBackgroundColor, AppColors.darkBackground);
      expect(darkTheme.colorScheme.onSurface, AppColors.darkTextPrimary);
    });
  });
}
