import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/features/export/export_service.dart';
import 'package:privacy_notes/features/notes/domain/checklist_item.dart';
import 'package:privacy_notes/features/notes/domain/note.dart';

void main() {
  group('ExportService Formatting & P3 Guard Tests', () {
    test('P3: Refuses locked notes with hard guard in service layer', () {
      final lockedNote = Note(
        id: 'locked-1',
        title: '',
        body: '',
        checklistJson: null,
        isLocked: true,
        encryptedPayload: Uint8List.fromList([1, 2, 3]),
        payloadIv: Uint8List.fromList([1, 2]),
        payloadTag: Uint8List.fromList([3, 4]),
        createdAt: 1000,
        updatedAt: 1000,
        wordCount: 0,
      );

      // formatNoteText must throw ExportSecurityException
      expect(
        () => ExportService.formatNoteText(lockedNote),
        throwsA(isA<ExportSecurityException>()),
      );

      // shareNote must throw ExportSecurityException
      expect(
        () => ExportService.shareNote(lockedNote),
        throwsA(isA<ExportSecurityException>()),
      );

      // saveToDevice must throw ExportSecurityException
      expect(
        () => ExportService.saveToDevice(lockedNote),
        throwsA(isA<ExportSecurityException>()),
      );
    });

    test('Formatting: Title and timestamps toggle (on vs off)', () {
      final note = Note.create(
        title: 'Meeting Notes',
        body: 'Action items discussed.',
      ).copyWith(
        createdAt: DateTime(2026, 10, 21, 14, 30, 0).millisecondsSinceEpoch,
        updatedAt: DateTime(2026, 10, 21, 15, 45, 0).millisecondsSinceEpoch,
      );

      // With timestamps ON
      final textWithTime = ExportService.formatNoteText(note, showTimestamps: true);
      expect(textWithTime.contains('Meeting Notes'), isTrue);
      expect(textWithTime.contains('Created: 2026-10-21 14:30:00'), isTrue);
      expect(textWithTime.contains('Updated: 2026-10-21 15:45:00'), isTrue);
      expect(textWithTime.contains('Action items discussed.'), isTrue);

      // With timestamps OFF
      final textNoTime = ExportService.formatNoteText(note, showTimestamps: false);
      expect(textNoTime.contains('Meeting Notes'), isTrue);
      expect(textNoTime.contains('Created:'), isFalse);
      expect(textNoTime.contains('Updated:'), isFalse);
      expect(textNoTime.contains('Action items discussed.'), isTrue);
    });

    test('Formatting: Checklist items as [ ] and [x]', () {
      final items = [
        const ChecklistItem(id: '1', text: 'Buy organic milk', isChecked: false),
        const ChecklistItem(id: '2', text: 'Renew passport', isChecked: true),
        const ChecklistItem(id: '3', text: 'Call electrician', isChecked: false),
      ];

      final note = Note.create(
        title: 'Todo List',
        isChecklistMode: true,
        checklistJson: ChecklistItem.encodeList(items),
      );

      final exported = ExportService.formatNoteText(note, showTimestamps: false);
      expect(exported.contains('Todo List'), isTrue);
      expect(exported.contains('[ ] Buy organic milk'), isTrue);
      expect(exported.contains('[x] Renew passport'), isTrue);
      expect(exported.contains('[ ] Call electrician'), isTrue);
    });

    test('Formatting: Bullets and numbering readable', () {
      const bodyWithBulletsAndNumbers = '''
Key Points:
- First bullet item
* Second bullet item
• Third bullet item
1. First numbered step
2. Second numbered step
''';

      final note = Note.create(
        title: 'Structured Note',
        body: bodyWithBulletsAndNumbers,
      );

      final exported = ExportService.formatNoteText(note, showTimestamps: false);
      expect(exported.contains('- First bullet item'), isTrue);
      expect(exported.contains('* Second bullet item'), isTrue);
      expect(exported.contains('• Third bullet item'), isTrue);
      expect(exported.contains('1. First numbered step'), isTrue);
      expect(exported.contains('2. Second numbered step'), isTrue);
    });
  });

  group('ExportService Filename Sanitization & Collisions Tests', () {
    test('Illegal characters: / \\ : * ? " < > | and control characters sanitized', () {
      const dirty = 'Notes: / \\ * ? " < > | test\x00\x1F';
      final cleaned = ExportService.sanitizeFileName(dirty);
      expect(cleaned, 'Notes_test.txt');
      expect(RegExp(r'[\\/:*?"<>|\x00-\x1F]').hasMatch(cleaned), isFalse);
    });

    test('Windows reserved names prefixed with underscore', () {
      final reserved = [
        'CON', 'con', 'PRN', 'prn', 'AUX', 'aux', 'NUL', 'nul',
        'COM1', 'com1', 'COM9', 'com9', 'LPT1', 'lpt1', 'LPT9', 'lpt9',
      ];

      for (final name in reserved) {
        final sanitized = ExportService.sanitizeFileName(name);
        expect(sanitized.startsWith('_'), isTrue, reason: 'Reserved name $name should be prefixed');
        expect(sanitized.toLowerCase(), '_${name.toLowerCase()}.txt');
      }
    });

    test('Length limit: Truncated to max 100 characters before extension', () {
      final veryLong = 'a' * 150;
      final sanitized = ExportService.sanitizeFileName(veryLong);
      expect(sanitized.endsWith('.txt'), isTrue);
      final base = sanitized.substring(0, sanitized.length - 4);
      expect(base.length, 100);
      expect(base, 'a' * 100);
    });

    test('Empty title fallback with timestamp', () {
      final fallbackDate = DateTime(2026, 10, 21, 21, 30, 45);
      final emptyResult = ExportService.sanitizeFileName('', fallbackDate: fallbackDate);
      expect(emptyResult, 'Note_20261021_213045.txt');

      final whitespaceResult = ExportService.sanitizeFileName('   \t  \n  ', fallbackDate: fallbackDate);
      expect(whitespaceResult, 'Note_20261021_213045.txt');

      final onlyIllegalResult = ExportService.sanitizeFileName('???***:::', fallbackDate: fallbackDate);
      expect(onlyIllegalResult, 'Note_20261021_213045.txt');
    });

    test('Collision resolution in directory: appends (1), (2), etc.', () {
      final tempDir = Directory.systemTemp.createTempSync('collision_test_');
      try {
        final file1 = File('${tempDir.path}/Document.txt');
        file1.writeAsStringSync('First');

        // Collision 1
        final resolved1 = ExportService.resolveCollision(tempDir.path, 'Document.txt');
        expect(resolved1, 'Document (1).txt');

        // Create Document (1).txt
        final file2 = File('${tempDir.path}/Document (1).txt');
        file2.writeAsStringSync('Second');

        // Collision 2
        final resolved2 = ExportService.resolveCollision(tempDir.path, 'Document.txt');
        expect(resolved2, 'Document (2).txt');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
