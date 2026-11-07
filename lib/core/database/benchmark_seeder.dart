import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../features/notes/domain/checklist_item.dart';
import '../../features/notes/domain/note.dart';
import 'app_database.dart';

/// Debug-only benchmark seeder (P6).
/// Injects 5,000 realistic notes into SQLite in a fast batch transaction.
/// Excluded from release builds via `kDebugMode` checks.
class BenchmarkSeeder {
  static const int seedCount = 5000;
  static const String benchmarkPrefix = '[BENCHMARK]';
  static const String idPrefix = 'bench_';

  /// Seeds 5,000 notes into the database.
  /// Returns the number of seeded notes inserted.
  static Future<int> seed5000Notes(AppDatabase appDb) async {
    if (!kDebugMode) {
      throw UnsupportedError('Benchmark seeder is strictly disabled in release builds.');
    }

    final db = appDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Use sqflite batch transaction for maximum insertion speed.
    final batch = db.batch();

    for (int i = 1; i <= seedCount; i++) {
      final id = '$idPrefix$i';
      final isChecklist = (i % 5 == 0); // 20% checklist notes (1,000 notes)
      final isPinned = (i <= 50); // 50 pinned notes
      final title = '$benchmarkPrefix Note #$i';

      String body = '';
      String? checklistJson;
      int wordCount = 0;

      if (isChecklist) {
        final itemCount = (i % 6) + 3; // 3 to 8 items
        final items = List.generate(
          itemCount,
          (idx) => ChecklistItem(
            id: 'item_${i}_$idx',
            text: 'Milestone task item #$idx for note $i',
            isChecked: (idx % 2 == 0),
          ),
        );
        checklistJson = jsonEncode(items.map((e) => e.toMap()).toList());
        wordCount = items.length * 6;
      } else {
        final paragraphs = (i % 4) + 1;
        final buffer = StringBuffer();
        for (int p = 0; p < paragraphs; p++) {
          buffer.writeln(
            'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
            'Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. '
            'Benchmark entry paragraph $p with unique keyword token_alpha_$i.',
          );
        }
        body = buffer.toString().trim();
        wordCount = body.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      }

      final createdAt = now - (i * 60000); // 1 minute intervals going backwards
      final updatedAt = createdAt;

      final note = Note(
        id: id,
        title: title,
        body: body,
        checklistJson: checklistJson,
        isChecklistMode: isChecklist,
        folderId: null,
        colorLabel: i % 8,
        isPinned: isPinned,
        isArchived: false,
        isLocked: false,
        trashedAt: null,
        encryptedPayload: null,
        payloadIv: null,
        payloadTag: null,
        payloadFormatVersion: 1,
        createdAt: createdAt,
        updatedAt: updatedAt,
        wordCount: wordCount,
      );

      batch.insert('notes', note.toMap());
    }

    await batch.commit(noResult: true);
    return seedCount;
  }

  /// Purges all 5,000 benchmark seeded notes from the database.
  /// Returns the number of notes deleted.
  static Future<int> purgeSeededNotes(AppDatabase appDb) async {
    final db = appDb.database;
    final deleted = await db.delete(
      'notes',
      where: 'id LIKE ? OR title LIKE ?',
      whereArgs: ['$idPrefix%', '$benchmarkPrefix%'],
    );
    return deleted;
  }
}
