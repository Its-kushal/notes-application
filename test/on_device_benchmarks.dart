import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:privacy_notes/core/crypto/kdf_service.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('================================================================');
  print('=== STARTING ON-DEVICE BENCHMARK (Device: M2101K6P / Android 13) ===');
  print('================================================================');

  runApp(const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Text('Running on-device benchmarks...'),
      ),
    ),
  ));

  // Allow Flutter engine and window to settle
  await Future.delayed(const Duration(seconds: 1));

  try {
    // -------------------------------------------------------------
    // PART 1: KDF TIMING AT 200,000 & 400,000 ITERATIONS
    // -------------------------------------------------------------
    print('\n>>> [KDF BENCHMARK] Measuring Native PBKDF2 at 200,000 iterations...');
    final kdfService = NativeKdfService();
    final random = Random.secure();
    final testSalt = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      testSalt[i] = random.nextInt(256);
    }
    const testSecret = 'benchmark_secret_1234';

    final kdfTimings200k = <int>[];
    for (int run = 1; run <= 5; run++) {
      final sw = Stopwatch()..start();
      final key = await kdfService.deriveKey(
        secret: testSecret,
        salt: testSalt,
        iterations: 200000,
        keyLength: 32,
      );
      sw.stop();
      final ms = sw.elapsedMilliseconds;
      kdfTimings200k.add(ms);
      print('  Run $run (200k): $ms ms (derived ${key.length} bytes)');
    }
    kdfTimings200k.sort();
    final kdfAvg200k = kdfTimings200k.reduce((a, b) => a + b) / kdfTimings200k.length;
    print('=== KDF 200,000 ITERATIONS SUMMARY ===');
    print('  Average: ${kdfAvg200k.toStringAsFixed(1)} ms');
    print('  Median:  ${kdfTimings200k[kdfTimings200k.length ~/ 2]} ms');
    print('  Min:     ${kdfTimings200k.first} ms');
    print('  Max:     ${kdfTimings200k.last} ms');

    print('\n>>> [KDF BENCHMARK] Measuring Native PBKDF2 at 400,000 iterations...');
    final kdfTimings400k = <int>[];
    for (int run = 1; run <= 5; run++) {
      final sw = Stopwatch()..start();
      final key = await kdfService.deriveKey(
        secret: testSecret,
        salt: testSalt,
        iterations: 400000,
        keyLength: 32,
      );
      sw.stop();
      final ms = sw.elapsedMilliseconds;
      kdfTimings400k.add(ms);
      print('  Run $run (400k): $ms ms (derived ${key.length} bytes)');
    }
    kdfTimings400k.sort();
    final kdfAvg400k = kdfTimings400k.reduce((a, b) => a + b) / kdfTimings400k.length;
    print('=== KDF 400,000 ITERATIONS SUMMARY ===');
    print('  Average: ${kdfAvg400k.toStringAsFixed(1)} ms');
    print('  Median:  ${kdfTimings400k[kdfTimings400k.length ~/ 2]} ms');
    print('  Min:     ${kdfTimings400k.first} ms');
    print('  Max:     ${kdfTimings400k.last} ms');

    // -------------------------------------------------------------
    // PART 2: PRAGMA journal_mode & synchronous BENCHMARK (Requirement B)
    // -------------------------------------------------------------
    print('\n>>> [DATABASE BENCHMARK] Measuring PRAGMA synchronous and write latency...');
    final dbDir = await getDatabasesPath();
    final dbPath = '$dbDir/benchmark_on_device.db';
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      await dbFile.delete();
    }

    // Open database with SQLCipher encryption to mirror production
    final db = await openDatabase(
      dbPath,
      password: 'benchmark_password_sqlcipher_32b',
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON;');
      },
    );

    // Read initial PRAGMA values
    final initialJournalRows = await db.rawQuery('PRAGMA journal_mode;');
    final initialJournal = initialJournalRows.first.values.first;

    final initialSyncRows = await db.rawQuery('PRAGMA synchronous;');
    final initialSync = initialSyncRows.first.values.first;

    print('Initial PRAGMA journal_mode: $initialJournal');
    print('Initial PRAGMA synchronous: $initialSync');

    // Create notes table matching production schema
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        checklist_json TEXT,
        is_checklist_mode INTEGER NOT NULL DEFAULT 0,
        folder_id TEXT,
        color_label INTEGER NOT NULL DEFAULT 0,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        is_locked INTEGER NOT NULL DEFAULT 0,
        trashed_at INTEGER,
        encrypted_payload BLOB,
        payload_iv BLOB,
        payload_tag BLOB,
        payload_format_version INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        word_count INTEGER NOT NULL DEFAULT 0
      );
    ''');

    const int writeCount = 100;

    // 1. Measure 100 writes BEFORE setting synchronous = FULL (default setting)
    print('\nMeasuring $writeCount writes with DEFAULT PRAGMA synchronous ($initialSync)...');
    final defaultDurations = <double>[];
    for (int i = 0; i < writeCount; i++) {
      final sw = Stopwatch()..start();
      await db.insert('notes', {
        'id': 'note_default_$i',
        'title': 'Test Note Default $i',
        'body': 'This is the note content payload measuring on-device flash storage latency.',
        'color_label': 0,
        'is_pinned': 0,
        'is_archived': 0,
        'is_locked': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'word_count': 11,
      });
      sw.stop();
      defaultDurations.add(sw.elapsedMicroseconds / 1000.0);
    }

    defaultDurations.sort();
    final avgDefault = defaultDurations.reduce((a, b) => a + b) / writeCount;
    final medianDefault = defaultDurations[writeCount ~/ 2];
    final p95Default = defaultDurations[(writeCount * 0.95).toInt()];
    final minDefault = defaultDurations.first;
    final maxDefault = defaultDurations.last;

    // 2. Apply PRAGMA synchronous = FULL
    await db.execute('PRAGMA synchronous = FULL;');
    final updatedJournalRows = await db.rawQuery('PRAGMA journal_mode;');
    final updatedJournal = updatedJournalRows.first.values.first;

    final updatedSyncRows = await db.rawQuery('PRAGMA synchronous;');
    final updatedSync = updatedSyncRows.first.values.first;

    print('\nUpdated PRAGMA journal_mode: $updatedJournal');
    print('Updated PRAGMA synchronous: $updatedSync');

    // 3. Measure 100 writes AFTER setting synchronous = FULL
    print('Measuring $writeCount writes with PRAGMA synchronous = FULL ($updatedSync)...');
    final fullDurations = <double>[];
    for (int i = 0; i < writeCount; i++) {
      final sw = Stopwatch()..start();
      await db.insert('notes', {
        'id': 'note_full_$i',
        'title': 'Test Note FULL $i',
        'body': 'This is the note content payload measuring on-device flash storage latency.',
        'color_label': 0,
        'is_pinned': 0,
        'is_archived': 0,
        'is_locked': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'word_count': 11,
      });
      sw.stop();
      fullDurations.add(sw.elapsedMicroseconds / 1000.0);
    }

    fullDurations.sort();
    final avgFull = fullDurations.reduce((a, b) => a + b) / writeCount;
    final medianFull = fullDurations[writeCount ~/ 2];
    final p95Full = fullDurations[(writeCount * 0.95).toInt()];
    final minFull = fullDurations.first;
    final maxFull = fullDurations.last;

    final costDelta = avgFull - avgDefault;

    print('\n================================================================');
    print('=== ON-DEVICE BENCHMARK RESULTS (M2101K6P, $writeCount writes each) ===');
    print('================================================================');
    print('PRAGMA journal_mode: $updatedJournal');
    print('DEFAULT PRAGMA synchronous: $initialSync');
    print('  Avg:    ${avgDefault.toStringAsFixed(3)} ms');
    print('  Median: ${medianDefault.toStringAsFixed(3)} ms');
    print('  p95:    ${p95Default.toStringAsFixed(3)} ms');
    print('  Min:    ${minDefault.toStringAsFixed(3)} ms');
    print('  Max:    ${maxDefault.toStringAsFixed(3)} ms');
    print('FULL PRAGMA synchronous: $updatedSync');
    print('  Avg:    ${avgFull.toStringAsFixed(3)} ms');
    print('  Median: ${medianFull.toStringAsFixed(3)} ms');
    print('  p95:    ${p95Full.toStringAsFixed(3)} ms');
    print('  Min:    ${minFull.toStringAsFixed(3)} ms');
    print('  Max:    ${maxFull.toStringAsFixed(3)} ms');
    print('Added Cost Per Write: ${costDelta.toStringAsFixed(3)} ms');
    print('Meets < 5 ms threshold? ${costDelta < 5.0 ? "YES (APPLY)" : "NO (REVERT)"}');
    print('================================================================\n');

    await db.close();
    if (await dbFile.exists()) {
      await dbFile.delete();
    }
  } catch (e, st) {
    print('BENCHMARK ERROR: $e\n$st');
  }

  // Done
  print('=== BENCHMARK COMPLETED SUCCESSFULLY ===');
  exit(0);
}
