import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('M5 Localization & ARB Completeness Lint Tests', () {
    test('ARB file exists, is valid JSON, and defines plural forms', () {
      final arbFile = File('lib/l10n/app_en.arb');
      expect(arbFile.existsSync(), isTrue, reason: 'app_en.arb must exist in lib/l10n/');

      final content = arbFile.readAsStringSync();
      final Map<String, dynamic> arb = json.decode(content);

      // Verify plural forms exist
      expect(arb.containsKey('notesCount'), isTrue);
      expect(arb.containsKey('wordsCount'), isTrue);
      expect(arb.containsKey('daysRetentionCount'), isTrue);
      expect(arb.containsKey('trashRetentionSubtitle'), isTrue);

      // Verify plurals contain ICU syntax
      expect(arb['notesCount'].toString().contains('plural'), isTrue);
      expect(arb['wordsCount'].toString().contains('plural'), isTrue);
    });

    test('Screens do not contain hardcoded user-visible Text strings', () {
      final screensDir = Directory('lib/features');
      expect(screensDir.existsSync(), isTrue);

      final screenFiles = screensDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.contains('${Platform.pathSeparator}screens${Platform.pathSeparator}') && f.path.endsWith('.dart'));

      final violations = <String>[];
      // Regex detects Text('...'), Text("..."), const Text('...')
      final textRegex = RegExp(r'''Text\s*\(\s*(['"])(.*?)\1''');

      // Whitelisted non-translatable text strings (symbols, whitespace, technical identifiers)
      const allowedLiterals = {
        '',
        ' ',
        '  ',
        '•',
        '-',
        ':',
        '/',
        '1.0.0',
        '72h',
        'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
        'monospace',
      };

      for (final file in screenFiles) {
        final lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trim();
          if (trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*')) {
            continue;
          }

          final matches = textRegex.allMatches(line);
          for (final m in matches) {
            final literal = m.group(2)?.trim() ?? '';
            // If it's not in the whitelist, and contains alphabetical characters (user-visible word)
            if (!allowedLiterals.contains(literal) && RegExp(r'[a-zA-Z]{2,}').hasMatch(literal)) {
              // Ignore debug print or key statements
              violations.add('${file.path}:${i + 1}: Text("$literal") in: $trimmed');
            }
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'All user-visible strings must be retrieved from contextL10n(context) or AppLocalizations.\n'
            'Found hardcoded strings in screens:\n${violations.join('\n')}',
      );
    });

    test('Zero left/right EdgeInsets in presentation screens (enforce RTL-safe start/end)', () {
      final screensDir = Directory('lib/features');
      final screenFiles = screensDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.contains('${Platform.pathSeparator}screens${Platform.pathSeparator}') && f.path.endsWith('.dart'));

      final violations = <String>[];
      final ltrRegex = RegExp(r'EdgeInsets\.only\s*\([^)]*\b(left|right)\s*:');

      for (final file in screenFiles) {
        final lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trim();
          if (trimmed.startsWith('//')) continue;

          if (ltrRegex.hasMatch(line)) {
            violations.add('${file.path}:${i + 1}: $trimmed');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'RTL layout safety requires EdgeInsetsDirectional.only(start:/end:) instead of left/right.\n'
            'Found violations:\n${violations.join('\n')}',
      );
    });
  });
}
