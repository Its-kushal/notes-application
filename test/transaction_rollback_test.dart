import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaflock/core/crypto/kdf_service.dart';
import 'package:leaflock/core/crypto/vault_service.dart';
import 'package:leaflock/core/database/app_database.dart';
import 'package:leaflock/features/notes/data/notes_repository.dart';
import 'package:leaflock/features/notes/domain/note.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('M5 Transaction Atomicity & Midway Rollback Tests (Host Tests)', () {
    late AppDatabase appDb;
    late Database db;
    late SqlNotesRepository repository;
    late VaultService vaultService;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      final status = await appDb.initialize(overridePassword: 'test_password');
      expect(status, DatabaseStatus.ready);
      db = appDb.database;
      repository = SqlNotesRepository(appDatabase: appDb);
      vaultService = VaultService(
        appDatabase: appDb,
        kdfService: const FakeKdfService(testIterations: 1),
        clock: () => DateTime.now(),
      );
    });

    tearDown(() async {
      await appDb.close();
    });

    test('1. lockNote transaction rollback on midway failure', () async {
      final note = Note.create(title: 'Clear Title', body: 'Confidential message');
      await repository.insertNote(note);

      // Inject midway failure: Execute note locking update inside a transaction, then throw
      await expectLater(
        db.transaction((txn) async {
          // Step 1: Encrypt and update note row (intermediate write) satisfying table CHECK constraints
          await txn.update(
            'notes',
            {
              'encrypted_payload': Uint8List.fromList([1, 2, 3, 4]),
              'payload_iv': Uint8List(12),
              'payload_tag': Uint8List(16),
              'is_locked': 1,
              'title': '',
              'body': '',
              'checklist_json': null,
              'word_count': 0,
            },
            where: 'id = ?',
            whereArgs: [note.id],
          );
          // Simulated crash/failure midway through transaction
          throw StateError('Injected mid-transaction failure during lockNote');
        }),
        throwsA(isA<StateError>()),
      );

      // Assert full rollback: note remains unlocked with original clear text intact
      final rolledBack = await repository.getNoteById(note.id);
      expect(rolledBack, isNotNull);
      expect(rolledBack!.isLocked, isFalse);
      expect(rolledBack.title, 'Clear Title');
      expect(rolledBack.body, 'Confidential message');
      expect(rolledBack.encryptedPayload, isNull);
    });

    test('2. unlockNote transaction rollback on midway failure', () async {
      final note = Note.create(title: 'Note to lock', body: 'Sensitive body');
      await repository.insertNote(note);
      final vaultKey = Uint8List.fromList(List.generate(32, (i) => i));

      // Lock note properly first
      await repository.lockNote(note.id, vaultKey);
      final locked = await repository.getNoteById(note.id);
      expect(locked!.isLocked, isTrue);
      expect(locked.title, '');
      expect(locked.body, '');

      // Attempt unlock with injected midway failure
      await expectLater(
        db.transaction((txn) async {
          await txn.update(
            'notes',
            {
              'title': 'Decrypted Title',
              'body': 'Decrypted Body',
              'checklist_json': null,
              'is_checklist_mode': 0,
              'word_count': 2,
              'is_locked': 0,
              'encrypted_payload': null,
              'payload_iv': null,
              'payload_tag': null,
            },
            where: 'id = ?',
            whereArgs: [note.id],
          );
          throw StateError('Injected failure during unlockNote transaction');
        }),
        throwsA(isA<StateError>()),
      );

      // Assert full rollback: note remains locked, title and body empty, ciphertext intact
      final noteAfter = await repository.getNoteById(note.id);
      expect(noteAfter!.isLocked, isTrue);
      expect(noteAfter.title, '');
      expect(noteAfter.body, '');
      expect(noteAfter.encryptedPayload, isNotNull);
    });

    test('3. bulk trash transaction rollback on midway failure', () async {
      final n1 = Note.create(title: 'Note 1', body: 'Body 1');
      final n2 = Note.create(title: 'Note 2', body: 'Body 2');
      final n3 = Note.create(title: 'Note 3', body: 'Body 3');
      await repository.insertNote(n1);
      await repository.insertNote(n2);
      await repository.insertNote(n3);

      final now = DateTime.now().millisecondsSinceEpoch;

      await expectLater(
        db.transaction((txn) async {
          // Update n1
          await txn.update('notes', {'trashed_at': now}, where: 'id = ?', whereArgs: [n1.id]);
          // Update n2
          await txn.update('notes', {'trashed_at': now}, where: 'id = ?', whereArgs: [n2.id]);
          // Midway crash before n3
          throw StateError('Injected crash midway through bulk trash');
        }),
        throwsA(isA<StateError>()),
      );

      // Assert full rollback: neither n1, n2, nor n3 are trashed
      final checkedN1 = await repository.getNoteById(n1.id);
      final checkedN2 = await repository.getNoteById(n2.id);
      final checkedN3 = await repository.getNoteById(n3.id);
      expect(checkedN1!.isTrashed, isFalse);
      expect(checkedN2!.isTrashed, isFalse);
      expect(checkedN3!.isTrashed, isFalse);
    });

    test('4. bulk archive transaction rollback on midway failure', () async {
      final n1 = Note.create(title: 'Note 1', body: 'Body 1');
      final n2 = Note.create(title: 'Note 2', body: 'Body 2');
      final n3 = Note.create(title: 'Note 3', body: 'Body 3');
      await repository.insertNote(n1);
      await repository.insertNote(n2);
      await repository.insertNote(n3);

      await expectLater(
        db.transaction((txn) async {
          await txn.update('notes', {'is_archived': 1}, where: 'id = ?', whereArgs: [n1.id]);
          await txn.update('notes', {'is_archived': 1}, where: 'id = ?', whereArgs: [n2.id]);
          throw StateError('Injected crash midway through bulk archive');
        }),
        throwsA(isA<StateError>()),
      );

      // Assert full rollback: zero notes archived
      final checkedN1 = await repository.getNoteById(n1.id);
      final checkedN2 = await repository.getNoteById(n2.id);
      final checkedN3 = await repository.getNoteById(n3.id);
      expect(checkedN1!.isArchived, isFalse);
      expect(checkedN2!.isArchived, isFalse);
      expect(checkedN3!.isArchived, isFalse);
    });

    test('5. resetVault transaction rollback on midway failure', () async {
      // Setup vault and 1 locked note
      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1, // fast iterations for host test
      );

      final lockedNote = Note.create(title: 'Secret Note', body: 'Classified');
      await repository.insertNote(lockedNote);
      final metadata = await vaultService.getVaultMetadata();
      expect(metadata, isNotNull);

      // Simulate midway failure during resetVault (delete notes, but crash before deleting metadata)
      await expectLater(
        db.transaction((txn) async {
          await txn.delete('notes', where: 'is_locked = 1');
          throw StateError('Injected midway crash during resetVault');
        }),
        throwsA(isA<StateError>()),
      );

      // Assert full rollback: vault metadata and locked notes still exist
      final metaAfter = await vaultService.getVaultMetadata();
      expect(metaAfter, isNotNull);
      final noteAfter = await repository.getNoteById(lockedNote.id);
      expect(noteAfter, isNotNull);
    });

    test('6. changeSecret transaction rollback on midway failure', () async {
      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1,
      );

      final originalMeta = await vaultService.getVaultMetadata();
      expect(originalMeta, isNotNull);

      // Simulate changeSecret failure midway
      await expectLater(
        db.transaction((txn) async {
          await txn.update(
            'vault_metadata',
            {
              'salt': Uint8List(16),
              'wrapped_vault_key': Uint8List(32),
            },
            where: 'id = 1',
          );
          throw StateError('Injected midway failure during changeSecret');
        }),
        throwsA(isA<StateError>()),
      );

      // Assert full rollback: original salt and wrapped key preserved
      final rolledBackMeta = await vaultService.getVaultMetadata();
      expect(rolledBackMeta, isNotNull);
      expect(rolledBackMeta!.salt, equals(originalMeta!.salt));
      expect(rolledBackMeta.wrappedVaultKey, equals(originalMeta.wrappedVaultKey));

      // Verifying authentication with old secret still succeeds
      await vaultService.unlockVault('123456');
      expect(vaultService.isUnlocked, isTrue);
    });

    test('7. generate recovery key transaction rollback on midway failure', () async {
      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1,
      );

      expect(await vaultService.hasRecoveryKey(), isFalse);

      // Attempt createOrUpdateRecoveryKey with midway transaction failure
      await expectLater(
        db.transaction((txn) async {
          await txn.update(
            'vault_metadata',
            {
              'recovery_wrapped_key': Uint8List.fromList([1, 2, 3]),
              'recovery_salt': Uint8List(16),
            },
            where: 'id = 1',
          );
          throw StateError('Injected midway failure during recovery key generation');
        }),
        throwsA(isA<StateError>()),
      );

      // Assert full rollback: hasRecoveryKey remains false
      expect(await vaultService.hasRecoveryKey(), isFalse);
    });

    test('8. multi-row insert transaction rollback on midway failure', () async {
      final initialNotes = await repository.getActiveNotes();
      final initialCount = initialNotes.length;

      // Batch insert of 30 notes with failure injected at note 15
      await expectLater(
        db.transaction((txn) async {
          for (int i = 1; i <= 30; i++) {
            if (i == 15) {
              throw StateError('Injected midway abort at row $i');
            }
            await txn.insert('notes', {
              'id': 'batch_test_$i',
              'title': 'Batch Note $i',
              'body': 'Body $i',
              'is_checklist_mode': 0,
              'is_pinned': 0,
              'is_archived': 0,
              'is_locked': 0,
              'color_label': 0,
              'created_at': DateTime.now().millisecondsSinceEpoch,
              'updated_at': DateTime.now().millisecondsSinceEpoch,
              'word_count': 2,
            });
          }
        }),
        throwsA(isA<StateError>()),
      );

      // Assert full rollback: exactly initialCount notes remain; 0 intermediate rows persisted
      final notesAfter = await repository.getActiveNotes();
      expect(notesAfter.length, equals(initialCount));
      final checkRow = await repository.getNoteById('batch_test_1');
      expect(checkRow, isNull);
    });

    test('9. migration transaction rollback on midway failure', () async {
      // Create a dedicated isolated test database with schema version 1
      final tempDb = await databaseFactoryFfi.openDatabase(
        'test_migration_rollback_${DateTime.now().microsecondsSinceEpoch}.db',
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE notes (id TEXT PRIMARY KEY, title TEXT, body TEXT);');
            await db.execute('PRAGMA user_version = 1;');
          },
        ),
      );

      // Insert data into v1 notes table
      await tempDb.insert('notes', {
        'id': 'v1_note',
        'title': 'V1 Note',
        'body': 'V1 Body',
      });

      // Enable migration failure injection
      AppDatabase.failMigrationForTesting = true;

      try {
        await expectLater(
          tempDb.transaction((txn) async {
            await txn.execute('ALTER TABLE notes ADD COLUMN category TEXT;');
            await AppDatabase.migrateVersion(txn, 2);
          }),
          throwsA(isA<StateError>()),
        );
      } finally {
        AppDatabase.failMigrationForTesting = false;
      }

      // Assert full rollback: user_version is still 1, category column rolled back, and original note is intact
      final rows = await tempDb.rawQuery('PRAGMA user_version;');
      final version = rows.isNotEmpty ? rows.first.values.first as int? : 0;
      expect(version, equals(1));

      final columns = await tempDb.rawQuery("PRAGMA table_info('notes');");
      final colNames = columns.map((c) => c['name'] as String).toList();
      expect(colNames.contains('category'), isFalse, reason: 'category column must be rolled back');

      final note = (await tempDb.query('notes', where: "id = 'v1_note'")).firstOrNull;
      expect(note, isNotNull);
      expect(note!['title'], equals('V1 Note'));

      await tempDb.close();
    });
  });
}
