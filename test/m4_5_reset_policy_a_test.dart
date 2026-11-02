import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/core/crypto/kdf_service.dart';
import 'package:privacy_notes/core/crypto/recovery_key_service.dart';
import 'package:privacy_notes/core/crypto/vault_service.dart';
import 'package:privacy_notes/core/database/app_database.dart';
import 'package:privacy_notes/features/notes/data/notes_repository.dart';
import 'package:privacy_notes/features/notes/domain/note.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SettableClock {
  DateTime _currentTime;
  SettableClock(this._currentTime);
  DateTime call() => _currentTime;
  void advance(Duration duration) {
    _currentTime = _currentTime.add(duration);
  }
  void setTime(DateTime time) {
    _currentTime = time;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('A1-A5: Reset Policy A Core & Lifecycle Tests', () {
    late AppDatabase appDb;
    late VaultService vaultService;
    late SqlNotesRepository repo;
    late SettableClock fakeClock;
    int simulatedElapsedMs = 100000;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_db_password');

      fakeClock = SettableClock(DateTime(2026, 10, 29, 12, 0, 0));
      simulatedElapsedMs = 100000;

      vaultService = VaultService(
        appDatabase: appDb,
        kdfService: const FakeKdfService(),
        clock: fakeClock.call,
        elapsedRealtimeProvider: () async => simulatedElapsedMs,
      );
      repo = SqlNotesRepository(appDatabase: appDb);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('A1: Immediate reset with current secret and typed DELETE', () async {
      final recoveryKey = RecoveryKeyService.generateKey();
      await vaultService.setupVault(
        secret: '1234',
        credentialType: CredentialType.pin,
        iterations: 1000,
        recoveryKeyString: recoveryKey,
      );

      final unlockedNote = Note.create(title: 'Unlocked Note', body: 'Safe content');
      await repo.insertNote(unlockedNote);

      final lockedNote = Note.create(title: 'Locked Note', body: 'Secret content');
      await repo.insertNote(lockedNote);
      await repo.lockNote(lockedNote.id, vaultService.vaultKey!);

      // Wrong confirmation text rejected
      await expectLater(
        vaultService.immediateResetWithSecret(
          secret: '1234',
          confirmationText: 'delete', // lowercase
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(await vaultService.hasVault(), isTrue);

      // Wrong secret rejected and counted as failed attempt
      await expectLater(
        vaultService.immediateResetWithSecret(
          secret: '9999',
          confirmationText: 'DELETE',
        ),
        throwsA(isA<VaultAuthException>()),
      );
      expect(await vaultService.getFailedAttempts(), equals(1));
      expect(await vaultService.hasVault(), isTrue);

      // Valid secret + DELETE executes immediate reset
      await vaultService.immediateResetWithSecret(
        secret: '1234',
        confirmationText: 'DELETE',
      );

      expect(await vaultService.hasVault(), isFalse);
      expect(await vaultService.getVaultMetadata(), isNull);
      expect(await vaultService.hasRecoveryKey(), isFalse);

      // Only locked notes deleted; unlocked note is preserved (A4)
      final remainingNotes = await repo.getActiveNotes();
      expect(remainingNotes.length, equals(1));
      expect(remainingNotes.first.id, equals(unlockedNote.id));

      // New vault creation allowed after reset (A4)
      await vaultService.setupVault(
        secret: '5678',
        credentialType: CredentialType.pin,
        iterations: 1000,
      );
      expect(await vaultService.hasVault(), isTrue);
    });

    test('A1: Immediate reset with paper recovery key and typed DELETE', () async {
      final recoveryKey = RecoveryKeyService.generateKey();
      await vaultService.setupVault(
        secret: '1234',
        credentialType: CredentialType.pin,
        iterations: 1000,
        recoveryKeyString: recoveryKey,
      );

      final lockedNote = Note.create(title: 'Locked Note', body: 'Confidential');
      await repo.insertNote(lockedNote);
      await repo.lockNote(lockedNote.id, vaultService.vaultKey!);

      final unlockedNote = Note.create(title: 'Regular Note', body: 'Public text');
      await repo.insertNote(unlockedNote);

      // Wrong confirmation text rejected
      await expectLater(
        vaultService.immediateResetWithRecoveryKey(
          recoveryKeyString: recoveryKey,
          confirmationText: 'WRONG',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Wrong recovery key rejected and counted towards recovery failed attempts
      final wrongKey = RecoveryKeyService.generateKey();
      await expectLater(
        vaultService.immediateResetWithRecoveryKey(
          recoveryKeyString: wrongKey,
          confirmationText: 'DELETE',
        ),
        throwsA(isA<RecoveryKeyAuthException>()),
      );
      expect(await vaultService.getRecoveryFailedAttempts(), equals(1));
      expect(await vaultService.hasVault(), isTrue);

      // Valid recovery key + DELETE executes reset
      await vaultService.immediateResetWithRecoveryKey(
        recoveryKeyString: recoveryKey,
        confirmationText: 'DELETE',
      );

      expect(await vaultService.hasVault(), isFalse);
      expect(await vaultService.getVaultMetadata(), isNull);
      final remainingNotes = await repo.getActiveNotes();
      expect(remainingNotes.length, equals(1));
      expect(remainingNotes.first.id, equals(unlockedNote.id));
    });

    test('A2, A3: Delayed reset lifecycle (request, 71h rejected, 72h accepted)', () async {
      await vaultService.setupVault(
        secret: '1234',
        credentialType: CredentialType.pin,
        iterations: 1000,
      );

      final lockedNote = Note.create(title: 'Secret', body: 'Private data');
      await repo.insertNote(lockedNote);
      await repo.lockNote(lockedNote.id, vaultService.vaultKey!);

      // Request delayed reset
      await vaultService.requestDelayedReset();
      var status = await vaultService.getDelayedResetStatus();
      expect(status.isRequested, isTrue);
      expect(status.isReady, isFalse);
      expect(status.remainingSeconds, equals(72 * 3600));

      // Attempt to complete reset immediately -> rejected
      await expectLater(
        vaultService.completeDelayedReset(confirmationText: 'DELETE'),
        throwsA(isA<StateError>()),
      );

      // Forward clock by 71 hours (255,600s) on wall clock and elapsedRealtime
      fakeClock.advance(const Duration(hours: 71));
      simulatedElapsedMs += 71 * 3600 * 1000;

      status = await vaultService.getDelayedResetStatus();
      expect(status.isRequested, isTrue);
      expect(status.isReady, isFalse);
      expect(status.remainingSeconds, equals(3600)); // 1 hour remaining

      // 71h complete attempt -> still rejected
      await expectLater(
        vaultService.completeDelayedReset(confirmationText: 'DELETE'),
        throwsA(isA<StateError>()),
      );

      // Advance by remaining 1 hour -> 72h reached!
      fakeClock.advance(const Duration(hours: 1));
      simulatedElapsedMs += 1 * 3600 * 1000;

      status = await vaultService.getDelayedResetStatus();
      expect(status.isRequested, isTrue);
      expect(status.isReady, isTrue);
      expect(status.remainingSeconds, equals(0));

      // Complete reset with DELETE
      await vaultService.completeDelayedReset(confirmationText: 'DELETE');
      expect(await vaultService.hasVault(), isFalse);
      expect(await vaultService.getDelayedResetStatus().then((s) => s.isRequested), isFalse);

      final remaining = await repo.getActiveNotes();
      expect(remaining, isEmpty);
    });

    test('A3: Wall-clock forward leap cannot bypass 72h when elapsedRealtime has not elapsed', () async {
      await vaultService.setupVault(
        secret: '1234',
        credentialType: CredentialType.pin,
        iterations: 1000,
      );

      await vaultService.requestDelayedReset();

      // User leaps wall-clock 10 days into future, but only 5s passed on elapsedRealtime
      fakeClock.advance(const Duration(days: 10));
      simulatedElapsedMs += 5000;

      final status = await vaultService.getDelayedResetStatus();
      expect(status.isRequested, isTrue);
      expect(status.isReady, isFalse); // Protected by elapsedRealtime check!
      expect(status.remainingSeconds, greaterThan(71 * 3600));

      await expectLater(
        vaultService.completeDelayedReset(confirmationText: 'DELETE'),
        throwsA(isA<StateError>()),
      );
    });

    test('A2: Delayed reset is automatically cancelled on successful unlock and notice is recorded', () async {
      await vaultService.setupVault(
        secret: '1234',
        credentialType: CredentialType.pin,
        iterations: 1000,
      );

      // Request delayed reset
      await vaultService.requestDelayedReset();
      expect((await vaultService.getDelayedResetStatus()).isRequested, isTrue);

      // Owner unlocks with their secret
      await vaultService.unlockVault('1234');

      // Delayed reset must be cancelled automatically (A2)
      final statusAfterUnlock = await vaultService.getDelayedResetStatus();
      expect(statusAfterUnlock.isRequested, isFalse);

      // Notice must be recorded with request date so owner is informed (A2)
      final noticeDate = await vaultService.getPendingResetNoticeDate();
      expect(noticeDate, isNotNull);
      expect(noticeDate, equals(fakeClock()));

      // Acknowledging clears the notice
      await vaultService.clearPendingResetNoticeDate();
      expect(await vaultService.getPendingResetNoticeDate(), isNull);
    });

    test('A2: Delayed reset is automatically cancelled on recovery and notice is recorded', () async {
      final recoveryKey = RecoveryKeyService.generateKey();
      await vaultService.setupVault(
        secret: '1234',
        credentialType: CredentialType.pin,
        iterations: 1000,
        recoveryKeyString: recoveryKey,
      );

      // Request delayed reset
      await vaultService.requestDelayedReset();
      expect((await vaultService.getDelayedResetStatus()).isRequested, isTrue);

      // Owner recovers with paper recovery key
      await vaultService.recoverVault(
        recoveryKeyString: recoveryKey,
        newSecret: '9876',
        newCredentialType: CredentialType.pin,
        iterations: 1000,
      );

      // Delayed reset is cancelled automatically
      final statusAfterRecovery = await vaultService.getDelayedResetStatus();
      expect(statusAfterRecovery.isRequested, isFalse);

      // Notice recorded
      final noticeDate = await vaultService.getPendingResetNoticeDate();
      expect(noticeDate, isNotNull);
    });
  });

  group('Requirement D: Schema v4 Migration & Integrity Check Test', () {
    test('Repairs v3 database lacking recovery columns, runs integrity check, and preserves notes', () async {
      final tempDir = Directory.systemTemp.createTempSync('schema_v4_repair_test_');
      final dbPath = '${tempDir.path}/v3_lacking_columns.db';

      // 1. Create a database file simulating a v3 database that was missing recovery columns
      final v3Db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, version) async {
            // vault_metadata missing recovery columns
            await db.execute('''
              CREATE TABLE vault_metadata (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                salt BLOB NOT NULL,
                kdf_algorithm TEXT NOT NULL,
                kdf_iterations INTEGER NOT NULL,
                wrapped_vault_key BLOB NOT NULL,
                wrapped_vault_key_iv BLOB NOT NULL,
                wrapped_vault_key_tag BLOB NOT NULL,
                version INTEGER NOT NULL DEFAULT 1,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
              );
            ''');
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
            await db.execute('''
              CREATE TABLE app_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
              );
            ''');

            // Insert sample notes and vault metadata
            await db.insert('vault_metadata', {
              'id': 1,
              'salt': Uint8List(16),
              'kdf_algorithm': 'PBKDF2-HMAC-SHA256',
              'kdf_iterations': 1000,
              'wrapped_vault_key': Uint8List(32),
              'wrapped_vault_key_iv': Uint8List(12),
              'wrapped_vault_key_tag': Uint8List(16),
              'version': 1,
              'created_at': 1000000,
              'updated_at': 1000000,
            });
            await db.insert('notes', {
              'id': 'note_1',
              'title': 'Pre-migration note',
              'body': 'Important data that must be preserved',
              'created_at': 1000000,
              'updated_at': 1000000,
            });
          },
        ),
      );
      await v3Db.close();

      // Verify that columns were indeed missing in the v3 DB
      final checkDb = await databaseFactoryFfi.openDatabase(dbPath);
      final rawColsBefore = await checkDb.rawQuery("PRAGMA table_info('vault_metadata');");
      final colNamesBefore = rawColsBefore.map((c) => c['name'] as String).toSet();
      expect(colNamesBefore.contains('recovery_salt'), isFalse);
      expect(colNamesBefore.contains('recovery_wrapped_key'), isFalse);
      expect(colNamesBefore.contains('credential_type'), isFalse);
      await checkDb.close();

      // 2. Open via AppDatabase -> migration v4 runs, performs integrity check, creates safety copy, and repairs columns
      final appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
      final status = await appDb.initialize(overridePassword: 'test_password');
      expect(status, equals(DatabaseStatus.ready));

      // 3. Verify that table has been upgraded to v4 and columns now exist
      final db = appDb.database;
      final versionRows = await db.rawQuery('PRAGMA user_version;');
      final newVersion = versionRows.first.values.first as int;
      expect(newVersion, equals(4));

      final rawColsAfter = await db.rawQuery("PRAGMA table_info('vault_metadata');");
      final colNamesAfter = rawColsAfter.map((c) => c['name'] as String).toSet();
      expect(colNamesAfter.contains('recovery_salt'), isTrue);
      expect(colNamesAfter.contains('recovery_wrapped_key'), isTrue);
      expect(colNamesAfter.contains('recovery_iv'), isTrue);
      expect(colNamesAfter.contains('recovery_tag'), isTrue);
      expect(colNamesAfter.contains('recovery_version'), isTrue);
      expect(colNamesAfter.contains('credential_type'), isTrue);

      // Verify existing data preserved
      final notes = await db.query('notes');
      expect(notes.length, equals(1));
      expect(notes.first['title'], equals('Pre-migration note'));
      expect(notes.first['body'], equals('Important data that must be preserved'));

      final metaRows = await db.query('vault_metadata');
      expect(metaRows.length, equals(1));
      expect(metaRows.first['credential_type'], equals('pin'));

      // Verify backup file was created
      final backupDir = Directory('${tempDir.path}/backups');
      expect(await backupDir.exists(), isTrue);
      final backups = backupDir.listSync();
      expect(backups.length, equals(1));

      await appDb.close();
      tempDir.deleteSync(recursive: true);
    });
  });
}
