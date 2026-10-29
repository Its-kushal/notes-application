import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  test('D1 Synchronous PRAGMA and Write Latency Benchmark', () async {
    final tempDir = Directory.systemTemp.createTempSync('db_sync_bench_');
    final dbPath = '${tempDir.path}/bench.db';

    final db = await databaseFactory.openDatabase(dbPath);

    // 1. Check current PRAGMA synchronous value
    final syncResult = await db.rawQuery('PRAGMA synchronous;');
    final currentSync = syncResult.first.values.first;
    print('Current PRAGMA synchronous value: $currentSync');

    // Create table matching notes table
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        color_index INTEGER NOT NULL DEFAULT 0,
        folder_id TEXT,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        is_trashed INTEGER NOT NULL DEFAULT 0,
        trashed_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_checklist_mode INTEGER NOT NULL DEFAULT 0,
        checklist_json TEXT,
        word_count INTEGER NOT NULL DEFAULT 0,
        is_locked INTEGER NOT NULL DEFAULT 0,
        encrypted_body BLOB,
        iv BLOB,
        tag BLOB
      );
    ''');

    const int iterations = 100;

    // Benchmark with current synchronous mode (default)
    final stopwatchDefault = Stopwatch()..start();
    final defaultLatencies = <double>[];
    for (int i = 0; i < iterations; i++) {
      final s = Stopwatch()..start();
      await db.insert('notes', {
        'id': 'note_def_$i',
        'title': 'Benchmark Note $i',
        'body': 'This is a benchmark note content to measure disk commit latency.',
        'color_index': 0,
        'is_pinned': 0,
        'is_archived': 0,
        'is_trashed': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'is_checklist_mode': 0,
        'word_count': 12,
        'is_locked': 0,
      });
      s.stop();
      defaultLatencies.add(s.elapsedMicroseconds / 1000.0);
    }
    stopwatchDefault.stop();

    defaultLatencies.sort();
    final avgDefault = defaultLatencies.reduce((a, b) => a + b) / iterations;
    final medianDefault = defaultLatencies[iterations ~/ 2];
    final p95Default = defaultLatencies[(iterations * 0.95).toInt()];

    // Change to PRAGMA synchronous = FULL (2)
    await db.execute('PRAGMA synchronous = FULL;');
    final newSyncResult = await db.rawQuery('PRAGMA synchronous;');
    final newSync = newSyncResult.first.values.first;
    print('Updated PRAGMA synchronous value: $newSync');

    final fullLatencies = <double>[];
    for (int i = 0; i < iterations; i++) {
      final s = Stopwatch()..start();
      await db.insert('notes', {
        'id': 'note_full_$i',
        'title': 'Benchmark Note FULL $i',
        'body': 'This is a benchmark note content to measure disk commit latency with synchronous FULL.',
        'color_index': 0,
        'is_pinned': 0,
        'is_archived': 0,
        'is_trashed': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'is_checklist_mode': 0,
        'word_count': 14,
        'is_locked': 0,
      });
      s.stop();
      fullLatencies.add(s.elapsedMicroseconds / 1000.0);
    }

    fullLatencies.sort();
    final avgFull = fullLatencies.reduce((a, b) => a + b) / iterations;
    final medianFull = fullLatencies[iterations ~/ 2];
    final p95Full = fullLatencies[(iterations * 0.95).toInt()];

    print('=== D1 BENCHMARK RESULTS (Host SSD, $iterations writes) ===');
    print('Default Mode ($currentSync):');
    print('  Average: ${avgDefault.toStringAsFixed(3)} ms');
    print('  Median:  ${medianDefault.toStringAsFixed(3)} ms');
    print('  p95:     ${p95Default.toStringAsFixed(3)} ms');
    print('FULL Mode ($newSync):');
    print('  Average: ${avgFull.toStringAsFixed(3)} ms');
    print('  Median:  ${medianFull.toStringAsFixed(3)} ms');
    print('  p95:     ${p95Full.toStringAsFixed(3)} ms');

    await db.close();
    tempDir.deleteSync(recursive: true);
  });
}
