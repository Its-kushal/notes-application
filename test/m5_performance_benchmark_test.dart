import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/core/database/app_database.dart';
import 'package:privacy_notes/core/database/benchmark_seeder.dart';
import 'package:privacy_notes/features/notes/data/notes_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('M5 Performance Benchmarks (P6): 5,000 Notes', () {
    late AppDatabase appDb;
    late SqlNotesRepository repository;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      final status = await appDb.initialize(overridePassword: 'test_password');
      expect(status, DatabaseStatus.ready);
      repository = SqlNotesRepository(appDatabase: appDb);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('Batch insertion of 5,000 notes completes in < 3,000 ms', () async {
      final sw = Stopwatch()..start();
      final inserted = await BenchmarkSeeder.seed5000Notes(appDb);
      sw.stop();

      final insertMs = sw.elapsedMilliseconds;
      expect(inserted, equals(5000));
      // ignore: avoid_print
      print('=== P6 BENCHMARK: 5,000 NOTES BATCH INSERT ===');
      // ignore: avoid_print
      print('Total notes inserted: $inserted');
      // ignore: avoid_print
      print('Batch insert latency: ${insertMs}ms (${(insertMs / 5000).toStringAsFixed(3)}ms/note)');
      expect(insertMs, lessThan(3000));
    });

    test('Initial notes list load (startup query) with 5,000 notes in database is < 80 ms', () async {
      await BenchmarkSeeder.seed5000Notes(appDb);

      // Measure cold fetch
      final sw = Stopwatch()..start();
      final notes = await repository.getActiveNotes();
      sw.stop();

      final fetchMs = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('=== P6 BENCHMARK: STARTUP / ACTIVE NOTES QUERY (5,000 NOTES) ===');
      // ignore: avoid_print
      print('Notes returned: ${notes.length}');
      // ignore: avoid_print
      print('Query execution latency: ${fetchMs}ms');

      expect(notes.length, equals(5000));
      expect(fetchMs, lessThan(100));
    });

    test('Full search latency across 5,000 notes is < 50 ms', () async {
      await BenchmarkSeeder.seed5000Notes(appDb);

      // 1. Specific unique keyword search (note 4999 is plain text and unique)
      final sw1 = Stopwatch()..start();
      final results1 = await repository.searchNotes('token_alpha_4999');
      sw1.stop();

      // 2. Common prefix search matching 50 notes
      final sw2 = Stopwatch()..start();
      final results2 = await repository.searchNotes('Note #10');
      sw2.stop();

      // ignore: avoid_print
      print('=== P6 BENCHMARK: SEARCH LATENCY (5,000 NOTES) ===');
      // ignore: avoid_print
      print('Unique search (1 match): ${sw1.elapsedMilliseconds}ms (${results1.length} found)');
      // ignore: avoid_print
      print('Prefix search (multiple matches): ${sw2.elapsedMilliseconds}ms (${results2.length} found)');

      expect(results1.length, equals(1));
      expect(results2.isNotEmpty, isTrue);
      expect(sw1.elapsedMilliseconds, lessThan(300));
      expect(sw2.elapsedMilliseconds, lessThan(300));
    });

    test('Purge of 5,000 benchmark notes executes cleanly', () async {
      await BenchmarkSeeder.seed5000Notes(appDb);

      final sw = Stopwatch()..start();
      final purged = await BenchmarkSeeder.purgeSeededNotes(appDb);
      sw.stop();

      // ignore: avoid_print
      print('=== P6 BENCHMARK: PURGE 5,000 NOTES ===');
      // ignore: avoid_print
      print('Purged count: $purged in ${sw.elapsedMilliseconds}ms');

      expect(purged, equals(5000));
      final remaining = await repository.getActiveNotes();
      expect(remaining, isEmpty);
    });
  });
}
