import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../notes/domain/checklist_item.dart';
import '../notes/domain/note.dart';

/// Exception thrown when an unauthorized or unsafe export is attempted.
class ExportSecurityException implements Exception {
  final String message;
  const ExportSecurityException(this.message);

  @override
  String toString() => 'ExportSecurityException: $message';
}

/// Exception thrown when an export operation fails.
class ExportException implements Exception {
  final String message;
  const ExportException(this.message);

  @override
  String toString() => message;
}

/// Service handling UTF-8 text formatting, filename sanitization,
/// share sheet staging/cleanup, and SAF saving.
class ExportService {
  static const int maxBaseFileNameLength = 100;

  static const Set<String> _windowsReservedNames = {
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };

  /// Cleans up any staged export files in the cache directory.
  /// Called on app startup and before staging the next export.
  static Future<void> cleanExportCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final exportDir = Directory('${cacheDir.path}/exports');
      if (await exportDir.exists()) {
        final entities = await exportDir.list().toList();
        for (final entity in entities) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Sanitizes a title string into a safe file name with .txt extension.
  /// Handles illegal characters, reserved names, length limits, and empty titles.
  static String sanitizeFileName(String title, {DateTime? fallbackDate}) {
    String clean = title.trim();

    // Replace illegal characters (\ / : * ? " < > | and control characters) with '_'
    clean = clean.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]+'), '_');

    // Clean whitespace around underscores and collapse consecutive underscores
    clean = clean.replaceAll(RegExp(r'\s*_\s*'), '_');
    clean = clean.replaceAll(RegExp(r'_+'), '_');

    // Remove leading/trailing dots, underscores, and spaces
    clean = clean.replaceAll(RegExp(r'^[._\s]+|[._\s]+$'), '');

    // Check if empty after sanitization
    if (clean.isEmpty) {
      final now = fallbackDate ?? DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmmss').format(now);
      return 'Note_$dateStr.txt';
    }

    // Truncate to maximum length limit
    if (clean.length > maxBaseFileNameLength) {
      clean = clean.substring(0, maxBaseFileNameLength).trim();
      clean = clean.replaceAll(RegExp(r'^[._\s]+|[._\s]+$'), '');
    }

    // Check Windows reserved names (case-insensitive)
    final upper = clean.toUpperCase();
    if (_windowsReservedNames.contains(upper)) {
      clean = '_$clean';
    }

    return '$clean.txt';
  }

  /// Resolves filename collisions in a directory by appending (1), (2), etc.
  static String resolveCollision(String directoryPath, String baseFileName) {
    var candidate = baseFileName;
    var counter = 1;
    final dotIndex = baseFileName.lastIndexOf('.');
    final name = dotIndex != -1 ? baseFileName.substring(0, dotIndex) : baseFileName;
    final ext = dotIndex != -1 ? baseFileName.substring(dotIndex) : '';

    while (File('$directoryPath/$candidate').existsSync()) {
      candidate = '$name ($counter)$ext';
      counter++;
    }
    return candidate;
  }

  /// Formats note content into a clean UTF-8 string with optional timestamps
  /// and formatted checklist items.
  static String formatNoteText(Note note, {bool showTimestamps = true}) {
    // P3 Guard: Hard security check in service layer
    if (note.isLocked) {
      throw const ExportSecurityException('Locked notes cannot be exported.');
    }

    final buffer = StringBuffer();

    // 1. Title
    if (note.title.trim().isNotEmpty) {
      buffer.writeln(note.title.trim());
      buffer.writeln();
    }

    // 2. Timestamps
    if (showTimestamps) {
      final createdDate = DateTime.fromMillisecondsSinceEpoch(note.createdAt);
      final updatedDate = DateTime.fromMillisecondsSinceEpoch(note.updatedAt);
      final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
      buffer.writeln('Created: ${fmt.format(createdDate)}');
      buffer.writeln('Updated: ${fmt.format(updatedDate)}');
      buffer.writeln();
    }

    // 3. Body / Checklist
    if (note.isChecklistMode && note.checklistJson != null) {
      final items = ChecklistItem.parseList(note.checklistJson);
      for (final item in items) {
        final mark = item.isChecked ? '[x]' : '[ ]';
        buffer.writeln('$mark ${item.text}');
      }
    } else {
      buffer.write(note.body);
    }

    return buffer.toString();
  }

  /// Exports via Android Share sheet using share_plus.
  /// Staged in the application cache directory.
  /// Cache is cleaned before the next export and on app launch (F4).
  static Future<void> shareNote(Note note, {bool showTimestamps = true}) async {
    if (note.isLocked) {
      throw const ExportSecurityException('Locked notes cannot be exported.');
    }

    // Clean export cache before staging the next export
    await cleanExportCache();

    final text = formatNoteText(note, showTimestamps: showTimestamps);
    final fileName = sanitizeFileName(
      note.title,
      fallbackDate: DateTime.fromMillisecondsSinceEpoch(note.updatedAt),
    );

    final cacheDir = await getTemporaryDirectory();
    final exportDir = Directory('${cacheDir.path}/exports');
    if (!exportDir.existsSync()) {
      exportDir.createSync(recursive: true);
    }

    final filePath = '${exportDir.path}/$fileName';
    final stagedFile = File(filePath);
    await stagedFile.writeAsBytes(utf8.encode(text), flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(stagedFile.path, mimeType: 'text/plain')],
        subject: note.title.isNotEmpty ? note.title : 'Exported Note',
      ),
    );
  }

  /// Saves the note to device via Storage Access Framework (SAF) using FilePicker.saveFile.
  /// Returns the saved file URI/path as string or null if cancelled.
  static Future<String?> saveToDevice(Note note, {bool showTimestamps = true}) async {
    if (note.isLocked) {
      throw const ExportSecurityException('Locked notes cannot be exported.');
    }

    final text = formatNoteText(note, showTimestamps: showTimestamps);
    final fileName = sanitizeFileName(
      note.title,
      fallbackDate: DateTime.fromMillisecondsSinceEpoch(note.updatedAt),
    );
    final bytes = Uint8List.fromList(utf8.encode(text));

    try {
      final result = await FilePicker.saveFile(
        dialogTitle: 'Save Note to Device',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['txt'],
        bytes: bytes,
      );

      return result?.toString();
    } catch (e) {
      throw ExportException('Failed to save file to device: $e');
    }
  }
}
