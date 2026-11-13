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

    test('lib/ source files do not contain hardcoded user-visible strings (Text, SnackBar, AlertDialog)', () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue);

      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.contains('app_localizations'));

      final violations = <String>[];
      // Regexes detecting hardcoded user-visible strings
      final textRegex = RegExp(r'''Text\s*\(\s*(['"])(.*?)\1''');
      final snackBarRegex = RegExp(r'''(?:AppSnackBar\.show|SnackBar)\s*\([^)]*message\s*:\s*(['"])(.*?)\1''');
      final alertDialogRegex = RegExp(r'''AlertDialog\s*\([^)]*(?:title|content)\s*:\s*(?:const\s+)?Text\s*\(\s*(['"])(.*?)\1''');
      final statusMessageRegex = RegExp(r'''statusMessage\s*:\s*(['"])(.*?)\1''');

      // Whitelisted non-translatable text strings (symbols, whitespace, technical identifiers)
      const allowedLiterals = {
        '',
        ' ',
        '  ',
        '•',
        '-',
        ':',
        '/',
        '0.9.0',
        '72h',
        'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
        'monospace',
        'LeafLock',
      };

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trim();
          if (trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*')) {
            continue;
          }

          void checkMatches(RegExp regex, String type) {
            final matches = regex.allMatches(line);
            for (final m in matches) {
              final literal = m.group(2)?.trim() ?? '';
              if (!allowedLiterals.contains(literal) && RegExp(r'[a-zA-Z]{2,}').hasMatch(literal)) {
                violations.add('${file.path}:${i + 1}: $type("$literal") in: $trimmed');
              }
            }
          }

          checkMatches(textRegex, 'Text');
          checkMatches(snackBarRegex, 'SnackBar');
          checkMatches(alertDialogRegex, 'AlertDialog');
          checkMatches(statusMessageRegex, 'statusMessage');
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'All user-visible strings must be retrieved from contextL10n(context) or AppLocalizations.\n'
            'Found hardcoded strings in lib/:\n${violations.join('\n')}',
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

    test('Source code in lib/ and ARB strings do not contain legacy app name "Privacy Notes"', () {
      final arbFile = File('lib/l10n/app_en.arb');
      expect(arbFile.existsSync(), isTrue);

      final content = arbFile.readAsStringSync();
      final Map<String, dynamic> arb = json.decode(content);

      final violations = <String>[];
      arb.forEach((key, value) {
        final str = value.toString();
        if (str.toLowerCase().contains('privacy notes')) {
          violations.add('app_en.arb ($key): $str');
        }
      });

      // Also scan all source files under lib/
      final libDir = Directory('lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      for (final file in dartFiles) {
        final lines = file.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trim();
          // Exclude comments and package name imports (com.leaflock.app)
          if (trimmed.startsWith('//') || trimmed.startsWith('/*') || trimmed.startsWith('*')) {
            continue;
          }
          if (line.contains('com.leaflock.app') || line.contains('package:leaflock')) {
            continue;
          }
          if (line.toLowerCase().contains('privacy notes')) {
            violations.add('${file.path}:${i + 1}: $trimmed');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'No ARB string or lib/ source file may contain user-visible "Privacy Notes". Found:\n${violations.join('\n')}',
      );
    });

    test('ARB strings do not contain obsolete "24-word" or "word order" phrases', () {
      final arbFile = File('lib/l10n/app_en.arb');
      expect(arbFile.existsSync(), isTrue);

      final content = arbFile.readAsStringSync();
      final Map<String, dynamic> arb = json.decode(content);

      final violations = <String>[];
      arb.forEach((key, value) {
        final str = value.toString();
        if (str.toLowerCase().contains('24-word') ||
            str.toLowerCase().contains('24 word') ||
            str.toLowerCase().contains('word order')) {
          violations.add('$key: $str');
        }
      });

      expect(
        violations,
        isEmpty,
        reason: 'No ARB string may refer to "24-word" or "word order" (key is 28 Crockford Base32 characters). Found:\n${violations.join('\n')}',
      );
    });
  });
}
