import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/features/file_viewer/domain/file_decoder.dart';
import 'package:privacy_notes/features/notes/domain/note.dart';

void main() {
  group('FileDecoder - Encoding & Decoding', () {
    test('decodes standard UTF-8 text without BOM', () {
      final bytes = Uint8List.fromList(utf8.encode('Hello, world!\nLine 2'));
      final result = FileDecoder.decodeBytes(bytes);

      expect(result.isSuccess, isTrue);
      expect(result.text, equals('Hello, world!\nLine 2'));
      expect(result.hasInvalidBytes, isFalse);
      expect(result.error, isNull);
    });

    test('decodes UTF-8 with BOM and strips BOM', () {
      final bom = [0xEF, 0xBB, 0xBF];
      final textBytes = utf8.encode('# Markdown Header\nSome text');
      final bytes = Uint8List.fromList([...bom, ...textBytes]);

      final result = FileDecoder.decodeBytes(bytes);

      expect(result.isSuccess, isTrue);
      expect(result.text, equals('# Markdown Header\nSome text'));
      expect(result.hasInvalidBytes, isFalse);
    });

    test('decodes UTF-16 LE with BOM', () {
      final bom = [0xFF, 0xFE];
      // "Hi" in UTF-16 LE: 'H' = 0x48 0x00, 'i' = 0x69 0x00
      final utf16le = [0x48, 0x00, 0x69, 0x00];
      final bytes = Uint8List.fromList([...bom, ...utf16le]);

      final result = FileDecoder.decodeBytes(bytes);

      expect(result.isSuccess, isTrue);
      expect(result.text, equals('Hi'));
      expect(result.hasInvalidBytes, isFalse);
    });

    test('decodes UTF-16 BE with BOM', () {
      final bom = [0xFE, 0xFF];
      // "Hi" in UTF-16 BE: 'H' = 0x00 0x48, 'i' = 0x00 0x69
      final utf16be = [0x00, 0x48, 0x00, 0x69];
      final bytes = Uint8List.fromList([...bom, ...utf16be]);

      final result = FileDecoder.decodeBytes(bytes);

      expect(result.isSuccess, isTrue);
      expect(result.text, equals('Hi'));
      expect(result.hasInvalidBytes, isFalse);
    });

    test('replaces invalid UTF-8 bytes with replacement char and sets warning flag', () {
      // 0xFF and 0xC0 are invalid UTF-8 sequences without BOM
      final bytes = Uint8List.fromList([0x48, 0x65, 0xFF, 0x6C, 0x6F]); // "He<FF>lo"
      final result = FileDecoder.decodeBytes(bytes);

      expect(result.isSuccess, isTrue);
      expect(result.hasInvalidBytes, isTrue);
      expect(result.text, contains('\uFFFD'));
      expect(result.text, equals('He\uFFFDlo'));
    });

    test('rejects binary file containing NUL bytes', () {
      final bytes = Uint8List.fromList([0x48, 0x65, 0x00, 0x6C, 0x6C, 0x6F]); // Contains 0x00
      final result = FileDecoder.decodeBytes(bytes);

      expect(result.isSuccess, isFalse);
      expect(result.error, equals(FileDecoder.errorBinary));
      expect(result.text, isNull);
    });

    test('rejects UTF-16 stream containing NUL characters', () {
      final bom = [0xFF, 0xFE];
      // 'H' (0x48 0x00) followed by '\0' (0x00 0x00)
      final bytes = Uint8List.fromList([...bom, 0x48, 0x00, 0x00, 0x00]);
      final result = FileDecoder.decodeBytes(bytes);

      expect(result.isSuccess, isFalse);
      expect(result.error, equals(FileDecoder.errorBinary));
    });
  });

  group('FileDecoder - Size Cap Boundaries & Empty Files', () {
    test('accepts exactly 2 MB file (2,097,152 bytes)', () {
      const size = 2 * 1024 * 1024;
      final bytes = Uint8List(size);
      // Fill with ASCII 'a' (0x61)
      bytes.fillRange(0, size, 0x61);

      final result = FileDecoder.decodeBytes(bytes);

      expect(result.isSuccess, isTrue);
      expect(result.text?.length, equals(size));
      expect(result.error, isNull);
    });

    test('rejects 2 MB + 1 byte file (2,097,153 bytes)', () {
      const size = 2 * 1024 * 1024 + 1;
      final bytes = Uint8List(size);
      bytes.fillRange(0, size, 0x61);

      final result = FileDecoder.decodeBytes(bytes);

      expect(result.isSuccess, isFalse);
      expect(result.error, equals(FileDecoder.errorTooLarge));
      expect(result.text, isNull);
    });

    test('detects empty file as EMPTY state', () {
      final bytes = Uint8List(0);
      final result = FileDecoder.decodeBytes(bytes);

      expect(result.isSuccess, isFalse);
      expect(result.error, equals(FileDecoder.errorEmpty));
      expect(result.text, equals(''));
    });
  });

  group('FileDecoder - Line Ending Normalization', () {
    test('normalizes CRLF to LF', () {
      final bytes = Uint8List.fromList(utf8.encode('line 1\r\nline 2\r\nline 3'));
      final result = FileDecoder.decodeBytes(bytes);

      expect(result.text, equals('line 1\nline 2\nline 3'));
      expect(result.text, isNot(contains('\r')));
    });

    test('normalizes standalone CR to LF', () {
      final bytes = Uint8List.fromList(utf8.encode('line 1\rline 2\rline 3'));
      final result = FileDecoder.decodeBytes(bytes);

      expect(result.text, equals('line 1\nline 2\nline 3'));
      expect(result.text, isNot(contains('\r')));
    });

    test('normalizes mixed CRLF, CR, and LF to LF', () {
      final bytes = Uint8List.fromList(utf8.encode('line 1\r\nline 2\rline 3\nline 4'));
      final result = FileDecoder.decodeBytes(bytes);

      expect(result.text, equals('line 1\nline 2\nline 3\nline 4'));
    });
  });

  group('FileDecoder - Note Title & Body Rules', () {
    test('extractTitle strips only known text extensions (.txt, .md, .markdown, .text)', () {
      expect(FileDecoder.extractTitle('todo.txt'), equals('todo'));
      expect(FileDecoder.extractTitle('README.md'), equals('README'));
      expect(FileDecoder.extractTitle('guide.markdown'), equals('guide'));
      expect(FileDecoder.extractTitle('notes.text'), equals('notes'));
      expect(FileDecoder.extractTitle('Meeting 3.5 summary.txt'), equals('Meeting 3.5 summary'));
      expect(FileDecoder.extractTitle('Meeting 3.5 summary'), equals('Meeting 3.5 summary'));
      expect(FileDecoder.extractTitle('archive.3.5.zip'), equals('archive.3.5.zip'));
    });

    test('extractTitle preserves filename when there is no extension or non-text extension', () {
      expect(FileDecoder.extractTitle('LICENSE'), equals('LICENSE'));
      expect(FileDecoder.extractTitle('notes'), equals('notes'));
      expect(FileDecoder.extractTitle('Meeting 3.5 summary'), equals('Meeting 3.5 summary'));
      expect(FileDecoder.extractTitle('photo.png'), equals('photo.png'));
    });

    test('extractTitle falls back to Untitled Note when filename is blank or extension only', () {
      expect(FileDecoder.extractTitle(null), equals('Untitled Note'));
      expect(FileDecoder.extractTitle(''), equals('Untitled Note'));
      expect(FileDecoder.extractTitle('   '), equals('Untitled Note'));
      expect(FileDecoder.extractTitle('.txt'), equals('Untitled Note'));
      expect(FileDecoder.extractTitle('.md'), equals('Untitled Note'));
      expect(FileDecoder.extractTitle('.markdown'), equals('Untitled Note'));
    });

    test('capBody caps body string to 2 MB limit', () {
      const max = 2 * 1024 * 1024;
      final shortBody = 'Short note text';
      expect(FileDecoder.capBody(shortBody), equals(shortBody));

      final longBody = 'x' * (max + 500);
      final capped = FileDecoder.capBody(longBody);
      expect(capped.length, equals(max));
    });

    test('note creation from file has locked=false and isChecklistMode=false', () {
      final title = FileDecoder.extractTitle('meeting_minutes.txt');
      final body = FileDecoder.capBody('Discuss roadmap and deliverables');

      final note = Note.create(
        title: title,
        body: body,
        isChecklistMode: false,
      );

      expect(note.title, equals('meeting_minutes'));
      expect(note.body, equals('Discuss roadmap and deliverables'));
      expect(note.isLocked, isFalse);
      expect(note.isChecklistMode, isFalse);
      expect(note.isArchived, isFalse);
      expect(note.isPinned, isFalse);
    });
  });
}
