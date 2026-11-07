import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('M5 Design System & Consistency Lint Tests', () {
    test('Zero inline TextStyle definitions outside lib/core/theme/', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.contains('app_theme.dart') && !f.path.contains('app_localizations'));

      final violations = <String>[];
      final regex = RegExp(r'\bTextStyle\s*\(');

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          // Skip comments
          final trimmed = line.trim();
          if (trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*')) {
            continue;
          }
          if (regex.hasMatch(line)) {
            violations.add('${file.path}:${i + 1}: $trimmed');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'All typography must come from Theme.of(context).textTheme or AppTheme. Found inline TextStyle violations:\n${violations.join('\n')}',
      );
    });

    test('Zero raw Colors.* references outside lib/core/constants/app_colors.dart and lib/core/theme/', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) =>
              !f.path.contains('app_colors.dart') &&
              !f.path.contains('app_theme.dart') &&
              !f.path.contains('app_localizations'));

      final violations = <String>[];
      final regex = RegExp(r'\bColors\.[a-zA-Z0-9_]+');

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trim();
          if (trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*')) {
            continue;
          }
          if (regex.hasMatch(line)) {
            violations.add('${file.path}:${i + 1}: $trimmed');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'All colors must come from AppColors or Theme.of(context).colorScheme. Found raw Colors.* references:\n${violations.join('\n')}',
      );
    });

    test('AppColors palette definitions adhere to named tokens', () {
      final appColorsFile = File('lib/core/constants/app_colors.dart');
      expect(appColorsFile.existsSync(), isTrue);

      final content = appColorsFile.readAsStringSync();
      expect(content.contains('static const Color primary ='), isTrue);
      expect(content.contains('static const Color lightBackground ='), isTrue);
      expect(content.contains('static const Color darkBackground ='), isTrue);
      expect(content.contains('static const Color error ='), isTrue);
    });
  });
}
