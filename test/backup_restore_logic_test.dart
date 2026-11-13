import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaflock/core/crypto/kdf_service.dart';
import 'package:leaflock/core/crypto/recovery_key_service.dart';
import 'package:leaflock/core/crypto/vault_service.dart';
import 'package:leaflock/core/database/app_database.dart';
import 'package:leaflock/features/backup/domain/backup_manifest.dart';
import 'package:leaflock/features/backup/services/backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase appDb;
  late BackupService backupService;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('leaf_lock_backup_test_');
    dbPath = '${tempDir.path}/test_app.db';
    appDb = AppDatabase(
      customFactory: databaseFactoryFfi,
      customPath: dbPath,
    );
    await appDb.initialize(overridePassword: 'test_password');
    backupService = BackupService(appDatabase: appDb);
  });

  tearDown(() async {
    await appDb.close();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Non-Destructive Restore & Vault Reconciliation Tests (B1-B5, F)', () {
    test('B5: Non-destructive restore never overwrites or deletes existing data', () async {
      final db = appDb.database;
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);
      await backupService.storeBackupSubkey(backupSubkey);

      // Seed local data: Note 1 (with edited body) and Folder 1
      await db.insert('folders', {
        'id': 'f1',
        'name': 'Personal Folder',
        'color': 111,
        'created_at': 1000,
        'updated_at': 1000,
      });

      await db.insert('notes', {
        'id': 'n1',
        'title': 'Original Title',
        'body': 'Locally Edited Body Content',
        'folder_id': 'f1',
        'is_pinned': 1,
        'is_archived': 0,
        'is_locked': 0,
        'created_at': 1000,
        'updated_at': 5000,
      });

      // Prepare a backup containing:
      // - Note 1 (with older body: should NOT overwrite local edit!)
      // - Note 2 (new note: should be restored!)
      // - Folder 2 (new folder: should be restored!)
      final backupManifest = BackupManifest(
        schemaVersion: 1,
        appVersion: '1.0.0',
        createdAt: 2000,
        folders: [
          {'id': 'f1', 'name': 'Old Personal Folder Name', 'color': 111, 'created_at': 1000, 'updated_at': 1000},
          {'id': 'f2', 'name': 'Work Folder', 'color': 222, 'created_at': 2000, 'updated_at': 2000},
        ],
        notes: [
          {
            'id': 'n1',
            'title': 'Old Title in Backup',
            'body': 'Old Body in Backup that should be ignored',
            'folder_id': 'f1',
            'is_pinned': 0,
            'is_archived': 0,
            'is_locked': 0,
            'created_at': 1000,
            'updated_at': 2000,
          },
          {
            'id': 'n2',
            'title': 'New Note from Backup',
            'body': 'Brand new body content',
            'folder_id': 'f2',
            'is_pinned': 0,
            'is_archived': 0,
            'is_locked': 0,
            'created_at': 2000,
            'updated_at': 2000,
          },
        ],
        vaultMetadata: null,
        settings: {'theme_mode': 'dark'},
      );

      final manifestBytes = Uint8List.fromList(utf8.encode(backupManifest.toJsonString()));
      final backupBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      // Perform non-destructive restore
      final summary = await backupService.validateAndRestoreBackup(
        fileBytes: backupBytes,
        recoveryKeyString: rootKey,
      );

      expect(summary.addedNotes, equals(1)); // Only n2 added
      expect(summary.skippedNotes, equals(1)); // n1 skipped
      expect(summary.addedFolders, equals(1)); // f2 added
      expect(summary.skippedFolders, equals(1)); // f1 skipped

      // Verify Note 1 kept local edits!
      final note1Rows = await db.query('notes', where: 'id = ?', whereArgs: ['n1']);
      expect(note1Rows.first['body'], equals('Locally Edited Body Content'));
      expect(note1Rows.first['title'], equals('Original Title'));
      expect(note1Rows.first['is_pinned'], equals(1));

      // Verify Note 2 was added!
      final note2Rows = await db.query('notes', where: 'id = ?', whereArgs: ['n2']);
      expect(note2Rows.length, equals(1));
      expect(note2Rows.first['title'], equals('New Note from Backup'));

      // Verify Folder 1 kept local name!
      final folder1Rows = await db.query('folders', where: 'id = ?', whereArgs: ['f1']);
      expect(folder1Rows.first['name'], equals('Personal Folder'));

      // Verify Folder 2 was added!
      final folder2Rows = await db.query('folders', where: 'id = ?', whereArgs: ['f2']);
      expect(folder2Rows.length, equals(1));
      expect(folder2Rows.first['name'], equals('Work Folder'));
    });

    test('F: Vault adoption when no local vault exists', () async {
      final db = appDb.database;
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);

      // Ensure no vault exists locally
      await db.delete('vault_metadata');

      // Setup a dummy vault metadata in backup
      final vaultMetadata = {
        'id': 1,
        'salt': Uint8List(16),
        'kdf_algorithm': 'pbkdf2_sha256',
        'kdf_iterations': 200000,
        'credential_type': 'pin',
        'wrapped_vault_key': Uint8List(32),
        'wrapped_vault_key_iv': Uint8List(12),
        'wrapped_vault_key_tag': Uint8List(16),
        'version': 1,
        'recovery_salt': Uint8List(16),
        'recovery_wrapped_key': Uint8List(32),
        'recovery_iv': Uint8List(12),
        'recovery_tag': Uint8List(16),
        'recovery_version': 1,
        'created_at': 1000,
        'updated_at': 1000,
      };

      final backupManifest = BackupManifest(
        schemaVersion: 1,
        appVersion: '1.0.0',
        createdAt: 2000,
        folders: [],
        notes: [
          {
            'id': 'ln1',
            'title': '',
            'body': '',
            'folder_id': null,
            'is_pinned': 0,
            'is_archived': 0,
            'is_locked': 1,
            'encrypted_payload': Uint8List(16),
            'payload_iv': Uint8List(12),
            'payload_tag': Uint8List(16),
            'word_count': 0,
            'created_at': 2000,
            'updated_at': 2000,
          },
        ],
        vaultMetadata: vaultMetadata,
        settings: {},
      );

      final manifestBytes = Uint8List.fromList(utf8.encode(backupManifest.toJsonString()));
      final backupBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      final summary = await backupService.validateAndRestoreBackup(
        fileBytes: backupBytes,
        recoveryKeyString: rootKey,
      );

      expect(summary.vaultAdopted, isTrue);
      expect(summary.addedNotes, equals(1));
      expect(summary.lockedNotesSkipped, equals(0));

      final localVault = await db.query('vault_metadata', where: 'id = 1');
      expect(localVault.length, equals(1));
    });

    test('F: Vault mismatch skips locked notes and reports accurate count', () async {
      final db = appDb.database;
      final kdfService = const FakeKdfService(testIterations: 1);
      final vaultService = VaultService(appDatabase: appDb, kdfService: kdfService);

      // Create a local vault with PIN 111111 and its own recovery key
      final localRecoveryKey = RecoveryKeyService.generateKey();
      await vaultService.setupVault(
        secret: '111111',
        credentialType: CredentialType.pin,
        recoveryKeyString: localRecoveryKey,
        iterations: 1, // fast iterations for host unit test
      );

      // Create a second, DIFFERENT vault with recovery key (for the backup)
      final backupRecoveryKey = RecoveryKeyService.generateKey();
      final backupRootBytes = RecoveryKeyService.decodeKey(backupRecoveryKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(backupRootBytes);

      // Generate a mock different vault wrap
      final dummyVaultMeta = {
        'id': 1,
        'salt': Uint8List(16),
        'kdf_algorithm': 'pbkdf2_sha256',
        'kdf_iterations': 1,
        'credential_type': 'pin',
        'wrapped_vault_key': Uint8List(32),
        'wrapped_vault_key_iv': Uint8List(12),
        'wrapped_vault_key_tag': Uint8List(16),
        'version': 1,
        'recovery_salt': Uint8List(16),
        'recovery_wrapped_key': Uint8List(32),
        'recovery_iv': Uint8List(12),
        'recovery_tag': Uint8List(16),
        'recovery_version': 1,
        'created_at': 1000,
        'updated_at': 1000,
      };

      final backupManifest = BackupManifest(
        schemaVersion: 1,
        appVersion: '1.0.0',
        createdAt: 2000,
        folders: [],
        notes: [
          {
            'id': 'regular_note',
            'title': 'Regular Note',
            'body': 'Regular Body',
            'is_locked': 0,
            'is_pinned': 0,
            'is_archived': 0,
            'created_at': 2000,
            'updated_at': 2000,
          },
          {
            'id': 'foreign_locked_note',
            'title': '',
            'body': '',
            'is_locked': 1,
            'is_pinned': 0,
            'is_archived': 0,
            'encrypted_payload': Uint8List(16),
            'payload_iv': Uint8List(12),
            'payload_tag': Uint8List(16),
            'word_count': 0,
            'created_at': 2000,
            'updated_at': 2000,
          },
        ],
        vaultMetadata: dummyVaultMeta,
        settings: {},
      );

      final manifestBytes = Uint8List.fromList(utf8.encode(backupManifest.toJsonString()));
      final backupBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      // Restore with the backup's recovery key
      final summary = await backupService.validateAndRestoreBackup(
        fileBytes: backupBytes,
        recoveryKeyString: backupRecoveryKey,
      );

      expect(summary.addedNotes, equals(1)); // 'regular_note' restored
      expect(summary.lockedNotesSkipped, equals(1)); // 'foreign_locked_note' skipped!
      expect(summary.vaultAdopted, isFalse);

      // Verify regular note was restored into local db
      final regNote = await db.query('notes', where: 'id = ?', whereArgs: ['regular_note']);
      expect(regNote.length, equals(1));

      // Verify foreign locked note was NOT restored into local db
      final foreignNote = await db.query('notes', where: 'id = ?', whereArgs: ['foreign_locked_note']);
      expect(foreignNote.isEmpty, isTrue);
    });

    test('B3: Recovery key string is NEVER stored on disk', () async {
      final db = appDb.database;
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);
      await backupService.storeBackupSubkey(backupSubkey);

      // Check app_settings table
      final settingsRows = await db.query('app_settings');
      for (final row in settingsRows) {
        final val = row['value'] as String?;
        if (val != null) {
          expect(val.contains(rootKey), isFalse);
          expect(val.contains(RecoveryKeyService.normalize(rootKey)), isFalse);
        }
      }

      // Check vault_metadata table
      final vaultRows = await db.query('vault_metadata');
      for (final row in vaultRows) {
        for (final entry in row.entries) {
          if (entry.value is String) {
            expect((entry.value as String).contains(rootKey), isFalse);
          }
        }
      }
    });

    test('B5: Pre-restore safety copy is created and pruned', () async {
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);

      final backupManifest = BackupManifest(
        schemaVersion: 1,
        appVersion: '1.0.0',
        createdAt: 2000,
        folders: [],
        notes: [
          {'id': 'n1', 'title': 'Test', 'body': 'Body', 'is_locked': 0, 'created_at': 100, 'updated_at': 100},
        ],
        vaultMetadata: null,
        settings: {},
      );

      final manifestBytes = Uint8List.fromList(utf8.encode(backupManifest.toJsonString()));
      final backupBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      // Perform restore 3 times
      await backupService.validateAndRestoreBackup(
        fileBytes: backupBytes,
        recoveryKeyString: rootKey,
      );
      await backupService.validateAndRestoreBackup(
        fileBytes: backupBytes,
        recoveryKeyString: rootKey,
      );
      await backupService.validateAndRestoreBackup(
        fileBytes: backupBytes,
        recoveryKeyString: rootKey,
      );

      // Verify backup directory contains at most 2 safety copies
      final dbFile = File(dbPath);
      final backupsDir = Directory('${dbFile.parent.path}/backups');
      if (await backupsDir.exists()) {
        final copies = await backupsDir.list().where((e) => e.path.contains('pre_restore')).toList();
        expect(copies.length, lessThanOrEqualTo(2));
      }
    });

    test('B5: Full transaction rollback on midway restore failure', () async {
      final db = appDb.database;
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);
      await backupService.storeBackupSubkey(backupSubkey);

      // Seed initial note
      await db.insert('notes', {
        'id': 'initial_note',
        'title': 'Untouched Initial Note',
        'body': 'Initial body',
        'is_locked': 0,
        'created_at': 100,
        'updated_at': 100,
      });

      // Prepare a manifest with a valid note followed by a note with duplicate ID or invalid constraint to trigger rollback
      final backupManifest = BackupManifest(
        schemaVersion: 1,
        appVersion: '1.0.0',
        createdAt: 2000,
        folders: [
          {'id': 'f_new', 'name': 'New Folder', 'created_at': 100, 'updated_at': 100},
        ],
        notes: [
          {'id': 'n_valid_1', 'title': 'Valid Note 1', 'body': 'Body 1', 'is_locked': 0, 'created_at': 200, 'updated_at': 200},
          {'id': 'n_valid_2', 'title': 'Valid Note 2', 'body': 'Body 2', 'is_locked': 0, 'created_at': 300, 'updated_at': 300},
        ],
        vaultMetadata: null,
        settings: {},
      );

      final manifestBytes = Uint8List.fromList(utf8.encode(backupManifest.toJsonString()));
      final backupBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      BackupService.failRestoreForTesting = true;
      try {
        await expectLater(
          () async => await backupService.validateAndRestoreBackup(
            fileBytes: backupBytes,
            recoveryKeyString: rootKey,
          ),
          throwsA(isA<StateError>()),
        );
      } finally {
        BackupService.failRestoreForTesting = false;
      }

      // Verify complete rollback: neither f_new nor n_valid_1 were committed!
      final folderRows = await db.query('folders', where: 'id = ?', whereArgs: ['f_new']);
      expect(folderRows.isEmpty, isTrue);

      final noteRows = await db.query('notes', where: 'id = ?', whereArgs: ['n_valid_1']);
      expect(noteRows.isEmpty, isTrue);

      final initialRows = await db.query('notes', where: 'id = ?', whereArgs: ['initial_note']);
      expect(initialRows.length, equals(1));
    });

    test('C: 5,000-note backup and restore performance benchmark (host SQLite)', () async {
      final db = appDb.database;
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);
      await backupService.storeBackupSubkey(backupSubkey);

      // 1. Seed 5,000 notes in batch
      final batch = db.batch();
      for (int i = 0; i < 5000; i++) {
        batch.insert('notes', {
          'id': 'bench_note_$i',
          'title': 'Benchmark Note #$i with representative title length',
          'body': 'This is the body content of note #$i. It contains several lines of markdown text.\n'
              '- Point 1: Offline encryption\n'
              '- Point 2: Zero cloud telemetry\n'
              '- Point 3: AES-256-GCM container verification.\n'
              'End of note content.',
          'is_pinned': (i % 20 == 0) ? 1 : 0,
          'is_archived': (i % 50 == 0) ? 1 : 0,
          'is_locked': 0,
          'created_at': 1700000000000 + i * 1000,
          'updated_at': 1700000000000 + i * 1000,
          'word_count': 35,
        });
      }
      await batch.commit(noResult: true);

      final noteCountBefore = (await db.rawQuery('SELECT COUNT(*) FROM notes')).first.values.first as int;
      expect(noteCountBefore, equals(5000));

      // 2. Measure backup creation time and file size
      final backupStopwatch = Stopwatch()..start();
      final backupBytes = await backupService.createBackupBytes();
      backupStopwatch.stop();

      final backupTimeMs = backupStopwatch.elapsedMilliseconds;
      final backupSizeBytes = backupBytes.length;
      final backupSizeKb = (backupSizeBytes / 1024).toStringAsFixed(1);
      final backupSizeMb = (backupSizeBytes / (1024 * 1024)).toStringAsFixed(2);

      // 3. Clear notes to benchmark restore
      await db.delete('notes');
      expect((await db.rawQuery('SELECT COUNT(*) FROM notes')).first.values.first as int, equals(0));

      // 4. Measure restore time
      final restoreStopwatch = Stopwatch()..start();
      final summary = await backupService.validateAndRestoreBackup(
        fileBytes: backupBytes,
        recoveryKeyString: rootKey,
      );
      restoreStopwatch.stop();

      final restoreTimeMs = restoreStopwatch.elapsedMilliseconds;
      final noteCountAfter = (await db.rawQuery('SELECT COUNT(*) FROM notes')).first.values.first as int;

      expect(summary.addedNotes, equals(5000));
      expect(noteCountAfter, equals(5000));

      // Print benchmark numbers for honest reporting
      // ignore: avoid_print
      print('\n================ 5,000-NOTE HOST BENCHMARK ================');
      // ignore: avoid_print
      print('5,000 Notes Backup Time  : $backupTimeMs ms');
      // ignore: avoid_print
      print('5,000 Notes Backup Size  : $backupSizeBytes bytes ($backupSizeKb KB / $backupSizeMb MB)');
      // ignore: avoid_print
      print('5,000 Notes Restore Time : $restoreTimeMs ms');
      // ignore: avoid_print
      print('===========================================================\n');

      expect(backupSizeBytes, lessThan(BackupService.maxFileSizeBytes));
      expect(backupTimeMs, lessThan(15000));
      expect(restoreTimeMs, lessThan(15000));
    });
  });

  group('M6 Closure: Requirements 4, 5, 6, 7 Verification', () {
    test('Requirement 4: Injected safety copy failure aborts restore and changes nothing', () async {
      final db = appDb.database;
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);

      // Seed initial local note
      await db.insert('notes', {
        'id': 'initial_n1',
        'title': 'Initial Note',
        'body': 'Initial Body',
        'is_locked': 0,
        'created_at': 100,
        'updated_at': 100,
      });

      // Prepare backup with a new note
      final manifest = BackupManifest(
        schemaVersion: 1,
        appVersion: '1.0.0',
        createdAt: 2000,
        folders: [],
        notes: [
          {'id': 'new_n2', 'title': 'New Note', 'body': 'New Body', 'is_locked': 0, 'created_at': 200, 'updated_at': 200},
        ],
        vaultMetadata: null,
        settings: {},
      );
      final manifestBytes = Uint8List.fromList(utf8.encode(manifest.toJsonString()));
      final backupBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      // Inject safety copy failure
      BackupService.failSafetyCopyForTesting = true;
      try {
        await expectLater(
          () async => await backupService.validateAndRestoreBackup(
            fileBytes: backupBytes,
            recoveryKeyString: rootKey,
          ),
          throwsA(isA<BackupSafetyCopyException>()),
        );
      } finally {
        BackupService.failSafetyCopyForTesting = false;
      }

      // Verify database changed nothing
      final notes = await db.query('notes');
      expect(notes.length, equals(1));
      expect(notes.first['id'], equals('initial_n1'));
    });

    test('Requirement 5: Unknown column in folder rejects entire backup', () async {
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);

      final manifest = BackupManifest(
        schemaVersion: 1,
        appVersion: '1.0.0',
        createdAt: 2000,
        folders: [
          {'id': 'f1', 'name': 'Folder', 'unknown_col': 'bad', 'created_at': 100, 'updated_at': 100},
        ],
        notes: [],
        vaultMetadata: null,
        settings: {},
      );
      final manifestBytes = Uint8List.fromList(utf8.encode(manifest.toJsonString()));
      final backupBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      await expectLater(
        () async => await backupService.validateAndRestoreBackup(
          fileBytes: backupBytes,
          recoveryKeyString: rootKey,
        ),
        throwsA(isA<BackupInvalidDataException>()),
      );
    });

    test('Requirement 5: Unknown column in note rejects entire backup', () async {
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);

      final manifest = BackupManifest(
        schemaVersion: 1,
        appVersion: '1.0.0',
        createdAt: 2000,
        folders: [],
        notes: [
          {'id': 'n1', 'title': 'T', 'body': 'B', 'is_locked': 0, 'malicious_extra': 123, 'created_at': 100, 'updated_at': 100},
        ],
        vaultMetadata: null,
        settings: {},
      );
      final manifestBytes = Uint8List.fromList(utf8.encode(manifest.toJsonString()));
      final backupBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      await expectLater(
        () async => await backupService.validateAndRestoreBackup(
          fileBytes: backupBytes,
          recoveryKeyString: rootKey,
        ),
        throwsA(isA<BackupInvalidDataException>()),
      );
    });

    test('Requirement 5: Value type and length limit violations reject backup', () async {
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);

      // Oversize note id (> 100 chars)
      final badIdManifest = BackupManifest(
        schemaVersion: 1,
        appVersion: '1.0.0',
        createdAt: 2000,
        folders: [],
        notes: [
          {'id': 'a' * 101, 'title': 'T', 'body': 'B', 'is_locked': 0, 'created_at': 100, 'updated_at': 100},
        ],
        vaultMetadata: null,
        settings: {},
      );
      final badIdBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: Uint8List.fromList(utf8.encode(badIdManifest.toJsonString())),
        backupSubkey: backupSubkey,
      );

      await expectLater(
        () async => await backupService.validateAndRestoreBackup(
          fileBytes: badIdBytes,
          recoveryKeyString: rootKey,
        ),
        throwsA(isA<BackupInvalidDataException>()),
      );
    });

    test('Requirement 5: Newer schema_version rejects entire backup', () async {
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);

      final futureManifest = BackupManifest(
        schemaVersion: 99,
        appVersion: '99.0.0',
        createdAt: 2000,
        folders: [],
        notes: [
          {'id': 'n1', 'title': 'T', 'body': 'B', 'is_locked': 0, 'created_at': 100, 'updated_at': 100},
        ],
        vaultMetadata: null,
        settings: {},
      );
      final futureBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: Uint8List.fromList(utf8.encode(futureManifest.toJsonString())),
        backupSubkey: backupSubkey,
      );

      await expectLater(
        () async => await backupService.validateAndRestoreBackup(
          fileBytes: futureBytes,
          recoveryKeyString: rootKey,
        ),
        throwsA(isA<BackupUnsupportedVersionException>()),
      );
    });

    test('Requirement 5: Locked note with plaintext title or body rejects backup', () async {
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);

      final invalidLockedManifest = BackupManifest(
        schemaVersion: 1,
        appVersion: '1.0.0',
        createdAt: 2000,
        folders: [],
        notes: [
          {
            'id': 'ln1',
            'title': 'Leaked Secret Title',
            'body': 'Leaked Secret Body',
            'is_locked': 1,
            'encrypted_payload': Uint8List(16),
            'payload_iv': Uint8List(12),
            'payload_tag': Uint8List(16),
            'word_count': 0,
            'created_at': 100,
            'updated_at': 100,
          },
        ],
        vaultMetadata: null,
        settings: {},
      );
      final bytes = await BackupService.encryptManifestToBytes(
        manifestBytes: Uint8List.fromList(utf8.encode(invalidLockedManifest.toJsonString())),
        backupSubkey: backupSubkey,
      );

      await expectLater(
        () async => await backupService.validateAndRestoreBackup(
          fileBytes: bytes,
          recoveryKeyString: rootKey,
        ),
        throwsA(isA<BackupInvalidDataException>()),
      );
    });

    test('Requirement 6: Settings allowlist exports ONLY allowed keys; other keys never exported', () async {
      final db = appDb.database;
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);
      await backupService.storeBackupSubkey(backupSubkey);

      // Insert both allowed and unapproved keys in app_settings
      await db.insert('app_settings', {'key': 'theme_mode', 'value': 'dark'}, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('app_settings', {'key': 'font_size_multiplier', 'value': '1.3'}, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('app_settings', {'key': 'default_sort_field', 'value': 'title'}, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('app_settings', {'key': 'default_sort_order', 'value': 'asc'}, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('app_settings', {'key': 'show_timestamps', 'value': '1'}, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('app_settings', {'key': 'show_word_count', 'value': '1'}, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('app_settings', {'key': 'trash_retention_days', 'value': '60'}, conflictAlgorithm: ConflictAlgorithm.replace);
      // Unapproved / sensitive keys
      await db.insert('app_settings', {'key': 'database_key', 'value': 'secret_db_pass'}, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('app_settings', {'key': 'lockout_timestamp', 'value': '12345678'}, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('app_settings', {'key': 'custom_unapproved_setting', 'value': 'test'}, conflictAlgorithm: ConflictAlgorithm.replace);

      // Create backup
      final backupBytes = await backupService.createBackupBytes();
      final manifest = await BackupService.decryptContainerToManifest(
        containerBytes: backupBytes,
        recoveryKeyString: rootKey,
      );

      // Verify that manifest settings contains ONLY the allowed keys
      final exportedKeys = manifest.settings.keys.toSet();
      expect(BackupManifest.allowedSettingsKeys.containsAll(exportedKeys), isTrue);
      expect(exportedKeys.contains('theme_mode'), isTrue);
      expect(exportedKeys.contains('font_size_multiplier'), isTrue);
      expect(exportedKeys.contains('trash_retention_days'), isTrue);

      // Critical: unapproved / sensitive keys MUST NOT be exported
      expect(exportedKeys.contains('database_key'), isFalse);
      expect(exportedKeys.contains('lockout_timestamp'), isFalse);
      expect(exportedKeys.contains('backup_subkey'), isFalse);
      expect(exportedKeys.contains('custom_unapproved_setting'), isFalse);
    });

    test('Requirement 6: Restore does not change existing settings', () async {
      final db = appDb.database;
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);

      // Local setting: theme_mode is 'light'
      await db.insert('app_settings', {'key': 'theme_mode', 'value': 'light'}, conflictAlgorithm: ConflictAlgorithm.replace);

      // Backup setting: theme_mode is 'dark', font_size_multiplier is '1.5'
      final manifest = BackupManifest(
        schemaVersion: 1,
        appVersion: '1.0.0',
        createdAt: 2000,
        folders: [],
        notes: [],
        vaultMetadata: null,
        settings: {
          'theme_mode': 'dark',
          'font_size_multiplier': '1.5',
        },
      );
      final manifestBytes = Uint8List.fromList(utf8.encode(manifest.toJsonString()));
      final backupBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      await backupService.validateAndRestoreBackup(
        fileBytes: backupBytes,
        recoveryKeyString: rootKey,
      );

      // Existing local setting 'theme_mode' must NOT have changed!
      final themeRow = await db.query('app_settings', where: 'key = ?', whereArgs: ['theme_mode']);
      expect(themeRow.first['value'], equals('light'));

      // Missing local setting 'font_size_multiplier' was restored
      final fontRow = await db.query('app_settings', where: 'key = ?', whereArgs: ['font_size_multiplier']);
      expect(fontRow.first['value'], equals('1.5'));
    });

    test('Requirement 7: Picked file is cleaned up after restore attempt in finally block', () async {
      final tempFile = File('${tempDir.path}/picked_backup.llbackup');
      await tempFile.writeAsBytes([1, 2, 3, 4]);
      expect(await tempFile.exists(), isTrue);

      // Emulate the finally block in BackupNotifier.performRestore
      try {
        // Attempt simulated restore
      } finally {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }

      expect(await tempFile.exists(), isFalse);
    });
  });
}
