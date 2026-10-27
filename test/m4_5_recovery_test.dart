import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/core/crypto/kdf_service.dart';
import 'package:privacy_notes/core/crypto/recovery_key_service.dart';
import 'package:privacy_notes/core/crypto/vault_service.dart';
import 'package:privacy_notes/core/database/app_database.dart';
import 'package:privacy_notes/features/locked_notes/presentation/controllers/vault_providers.dart';
import 'package:privacy_notes/features/locked_notes/presentation/screens/vault_recovery_key_screen.dart';
import 'package:privacy_notes/features/locked_notes/presentation/screens/vault_recovery_screen.dart';
import 'package:privacy_notes/features/locked_notes/presentation/screens/vault_setup_screen.dart';
import 'package:privacy_notes/features/notes/data/notes_repository.dart';
import 'package:privacy_notes/features/notes/domain/note.dart';
import 'package:privacy_notes/features/settings/presentation/screens/settings_screen.dart';
import 'package:privacy_notes/features/settings/presentation/controllers/settings_provider.dart';
import 'package:privacy_notes/features/settings/domain/app_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.privacynotes.app/security'),
      (call) async {
        if (call.method == 'getElapsedRealtime') {
          return 500000;
        }
        return null;
      },
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.privacynotes.app/security'),
      null,
    );
  });

  group('M4.5 Database Scan for Plaintext Recovery Key (R2)', () {
    late AppDatabase appDb;
    late VaultService vaultService;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_db_password');
      vaultService = VaultService(
        appDatabase: appDb,
        kdfService: const FakeKdfService(),
      );
    });

    tearDown(() async {
      await appDb.close();
    });

    test('Recovery key string NEVER appears in database, settings, or queries', () async {
      final recoveryKey = RecoveryKeyService.generateKey();
      final normalizedKey = RecoveryKeyService.normalize(recoveryKey);
      final raw26Base32 = normalizedKey.substring(0, 26);

      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1000,
        recoveryKeyString: recoveryKey,
      );

      final db = appDb.database;
      // Scan all tables and columns
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
      );

      for (final tableRow in tables) {
        final tableName = tableRow['name'] as String;
        final rows = await db.query(tableName);
        for (final row in rows) {
          for (final entry in row.entries) {
            final val = entry.value;
            if (val is String) {
              expect(val.contains(recoveryKey), isFalse,
                  reason: 'Found recovery key in table $tableName column ${entry.key}');
              expect(val.contains(normalizedKey), isFalse,
                  reason: 'Found normalized recovery key in table $tableName column ${entry.key}');
              expect(val.contains(raw26Base32), isFalse,
                  reason: 'Found base32 recovery key payload in table $tableName column ${entry.key}');
            } else if (val is Uint8List) {
              final valString = String.fromCharCodes(val);
              expect(valString.contains(recoveryKey), isFalse);
              expect(valString.contains(normalizedKey), isFalse);
              expect(valString.contains(raw26Base32), isFalse);
            }
          }
        }
      }
    });
  });

  group('M4.5 Secret Change & Credential Switch Preserves Recovery Key (R8)', () {
    late AppDatabase appDb;
    late VaultService vaultService;
    late SqlNotesRepository repo;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_db_password');
      vaultService = VaultService(
        appDatabase: appDb,
        kdfService: const FakeKdfService(),
      );
      repo = SqlNotesRepository(appDatabase: appDb);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('Recovery key stays valid across PIN change and PIN->Pattern switch', () async {
      final recoveryKey = RecoveryKeyService.generateKey();
      final recoveryBytes = RecoveryKeyService.decodeKey(recoveryKey);

      // 1. Setup vault with PIN '123456'
      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1000,
        recoveryKeyString: recoveryKey,
      );
      final initialVaultKey = vaultService.vaultKey!;

      // 2. Lock a note
      final note = Note.create(title: 'Top Secret Note', body: 'Confidential message');
      await repo.insertNote(note);
      await repo.lockNote(note.id, initialVaultKey);

      // 3. Change PIN to '654321'
      await vaultService.changeSecret(
        currentSecret: '123456',
        newSecret: '654321',
        newCredentialType: CredentialType.pin,
        iterations: 1000,
      );

      // Verify recovery wrap still unwraps the exact same vault key
      final meta1 = await vaultService.getVaultMetadata();
      expect(meta1!.hasRecoveryKey, isTrue);
      final unwrappedKey1 = await RecoveryKeyService.unwrapVaultKey(
        recoveryKeyBytes: recoveryBytes,
        salt: meta1.recoverySalt!,
        wrappedVaultKey: meta1.recoveryWrappedKey!,
        iv: meta1.recoveryIv!,
        tag: meta1.recoveryTag!,
      );
      expect(unwrappedKey1, equals(initialVaultKey));
      final decNote1 = await repo.getLockedNoteById(note.id, unwrappedKey1);
      expect(decNote1!.title, equals('Top Secret Note'));

      // 4. Switch Credential to Pattern '0-1-2-4-7'
      await vaultService.changeSecret(
        currentSecret: '654321',
        newSecret: '0-1-2-4-7',
        newCredentialType: CredentialType.pattern,
        iterations: 1000,
      );

      // Verify recovery wrap still unwraps the same vault key
      final meta2 = await vaultService.getVaultMetadata();
      expect(meta2!.hasRecoveryKey, isTrue);
      final unwrappedKey2 = await RecoveryKeyService.unwrapVaultKey(
        recoveryKeyBytes: recoveryBytes,
        salt: meta2.recoverySalt!,
        wrappedVaultKey: meta2.recoveryWrappedKey!,
        iv: meta2.recoveryIv!,
        tag: meta2.recoveryTag!,
      );
      expect(unwrappedKey2, equals(initialVaultKey));
      final decNote2 = await repo.getLockedNoteById(note.id, unwrappedKey2);
      expect(decNote2!.title, equals('Top Secret Note'));
    });
  });

  group('M4.5 Recovery Key Rotation (R7)', () {
    late AppDatabase appDb;
    late VaultService vaultService;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_db_password');
      vaultService = VaultService(
        appDatabase: appDb,
        kdfService: const FakeKdfService(),
      );
    });

    tearDown(() async {
      await appDb.close();
    });

    test('Generating a new recovery key invalidates the old one', () async {
      final key1 = RecoveryKeyService.generateKey();
      final key2 = RecoveryKeyService.generateKey();
      final keyBytes1 = RecoveryKeyService.decodeKey(key1);
      final keyBytes2 = RecoveryKeyService.decodeKey(key2);

      await vaultService.setupVault(
        secret: '111111',
        credentialType: CredentialType.pin,
        iterations: 1000,
        recoveryKeyString: key1,
      );
      final originalVaultKey = vaultService.vaultKey!;

      // Rotate to key2
      await vaultService.createOrUpdateRecoveryKey(
        currentSecret: '111111',
        recoveryKeyString: key2,
      );

      final meta = await vaultService.getVaultMetadata();

      // Old key1 MUST throw RecoveryKeyAuthException
      expect(
        () => RecoveryKeyService.unwrapVaultKey(
          recoveryKeyBytes: keyBytes1,
          salt: meta!.recoverySalt!,
          wrappedVaultKey: meta.recoveryWrappedKey!,
          iv: meta.recoveryIv!,
          tag: meta.recoveryTag!,
        ),
        throwsA(isA<RecoveryKeyAuthException>()),
      );

      // New key2 unwraps successfully
      final unwrapped = await RecoveryKeyService.unwrapVaultKey(
        recoveryKeyBytes: keyBytes2,
        salt: meta!.recoverySalt!,
        wrappedVaultKey: meta.recoveryWrappedKey!,
        iv: meta.recoveryIv!,
        tag: meta.recoveryTag!,
      );
      expect(unwrapped, equals(originalVaultKey));
    });
  });

  group('M4.5 Forgot Secret Flow (R6)', () {
    late AppDatabase appDb;
    late VaultService vaultService;
    late SqlNotesRepository repo;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_db_password');
      vaultService = VaultService(
        appDatabase: appDb,
        kdfService: const FakeKdfService(),
      );
      repo = SqlNotesRepository(appDatabase: appDb);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('Forgot flow: right key restores vault, sets new secret, keeps notes, does not rotate key', () async {
      final recoveryKey = RecoveryKeyService.generateKey();
      final recoveryBytes = RecoveryKeyService.decodeKey(recoveryKey);

      await vaultService.setupVault(
        secret: '111111',
        credentialType: CredentialType.pin,
        iterations: 1000,
        recoveryKeyString: recoveryKey,
      );
      final vaultKey = vaultService.vaultKey!;

      // Lock note
      final note = Note.create(title: 'Vault Note', body: 'Sensitive data');
      await repo.insertNote(note);
      await repo.lockNote(note.id, vaultKey);

      // Lock the vault
      vaultService.lockVault();
      expect(vaultService.isUnlocked, isFalse);

      // Perform recovery with recoveryKey -> set new PIN '999999'
      await vaultService.recoverVault(
        recoveryKeyString: recoveryKey,
        newSecret: '999999',
        newCredentialType: CredentialType.pin,
        iterations: 1000,
      );

      expect(vaultService.isUnlocked, isTrue);
      expect(vaultService.vaultKey, equals(vaultKey));

      // Note is still decryptable
      final recoveredNote = await repo.getLockedNoteById(note.id, vaultService.vaultKey!);
      expect(recoveredNote!.title, equals('Vault Note'));

      // Relock vault and test secrets
      vaultService.lockVault();

      // Old secret fails cleanly
      expect(
        () => vaultService.unlockVault('111111'),
        throwsA(isA<VaultAuthException>()),
      );

      // New secret unlocks cleanly
      await vaultService.unlockVault('999999');
      expect(vaultService.isUnlocked, isTrue);

      // Recovery key was NOT rotated automatically and still works
      final meta = await vaultService.getVaultMetadata();
      final unwrapped = await RecoveryKeyService.unwrapVaultKey(
        recoveryKeyBytes: recoveryBytes,
        salt: meta!.recoverySalt!,
        wrappedVaultKey: meta.recoveryWrappedKey!,
        iv: meta.recoveryIv!,
        tag: meta.recoveryTag!,
      );
      expect(unwrapped, equals(vaultKey));
    });
  });

  group('M4.5 Attempt Counter & Lockout Isolation (R6)', () {
    late AppDatabase appDb;
    late VaultService vaultService;
    DateTime simulatedNow = DateTime(2026, 10, 26, 12, 0, 0);

    setUp(() async {
      simulatedNow = DateTime(2026, 10, 26, 12, 0, 0);
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_db_password');
      vaultService = VaultService(
        appDatabase: appDb,
        kdfService: const FakeKdfService(),
        clock: () => simulatedNow,
      );
    });

    tearDown(() async {
      await appDb.close();
    });

    test('Checksum failure does not count as attempt; wrong key increments recovery counter without affecting main counter', () async {
      final validKey = RecoveryKeyService.generateKey();
      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1000,
        recoveryKeyString: validKey,
      );
      vaultService.lockVault();

      // 1. Checksum error does not count as attempt (handled by RecoveryKeyService validation)
      final wrongChecksumKey = validKey.substring(0, validKey.length - 1) + (validKey.endsWith('0') ? '1' : '0');
      expect(
        () => RecoveryKeyService.decodeKey(wrongChecksumKey),
        throwsA(isA<RecoveryKeyChecksumException>()),
      );
      // Verify recovery counter is 0
      expect(await vaultService.getRecoveryFailedAttempts(), equals(0));

      // 2. Generate a well-formed DIFFERENT recovery key (valid checksum, wrong key)
      final wrongWellFormedKey = RecoveryKeyService.generateKey();

      // Fail 4 times -> 0s lockout
      for (int i = 1; i <= 4; i++) {
        await expectLater(
          vaultService.recoverVault(
            recoveryKeyString: wrongWellFormedKey,
            newSecret: '000000',
            newCredentialType: CredentialType.pin,
            iterations: 1000,
          ),
          throwsA(isA<RecoveryKeyAuthException>()),
        );
        expect(await vaultService.getRecoveryFailedAttempts(), equals(i));
        expect(await vaultService.getRemainingRecoveryLockoutSeconds(), equals(0));
      }

      // 5th failed attempt -> 30s lockout
      await expectLater(
        vaultService.recoverVault(
          recoveryKeyString: wrongWellFormedKey,
          newSecret: '000000',
          newCredentialType: CredentialType.pin,
          iterations: 1000,
        ),
        throwsA(isA<RecoveryKeyAuthException>()),
      );
      expect(await vaultService.getRecoveryFailedAttempts(), equals(5));
      expect(await vaultService.getRemainingRecoveryLockoutSeconds(), equals(30));

      // Recovery lockout is enforced
      await expectLater(
        vaultService.recoverVault(
          recoveryKeyString: validKey, // even right key is locked out!
          newSecret: '000000',
          newCredentialType: CredentialType.pin,
          iterations: 1000,
        ),
        throwsA(isA<VaultLockoutException>()),
      );

      // MAIN vault secret counter is completely unaffected!
      expect(await vaultService.getFailedAttempts(), equals(0));
      expect(await vaultService.getRemainingLockoutSeconds(), equals(0));
      // Main secret unlock succeeds without lockout
      await vaultService.unlockVault('123456');
      expect(vaultService.isUnlocked, isTrue);
    });
  });

  group('M4.5 Transaction Integrity & Consistency (R4, R6)', () {
    test('Setup error rolls back entire transaction leaving no half-created vault', () async {
      final appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_db_password');

      final errorVaultService = VaultService(
        appDatabase: appDb,
        kdfService: const FakeKdfService(),
      );

      // Pass an invalid recovery key that fails wrap
      expect(
        () => errorVaultService.setupVault(
          secret: '123456',
          credentialType: CredentialType.pin,
          iterations: 1000,
          recoveryKeyString: 'INVALID-RECOVERY-KEY',
        ),
        throwsA(isA<RecoveryKeyException>()),
      );

      // Verify no vault metadata row exists
      final hasVault = await errorVaultService.hasVault();
      expect(hasVault, isFalse);
      final meta = await errorVaultService.getVaultMetadata();
      expect(meta, isNull);

      await appDb.close();
    });
  });

  group('M4.5 Reset Vault Cleans Up Recovery Wrap (R8)', () {
    test('Reset locked notes deletes recovery wrap and clears metadata', () async {
      final appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_db_password');
      final vaultService = VaultService(
        appDatabase: appDb,
        kdfService: const FakeKdfService(),
      );
      final repo = SqlNotesRepository(appDatabase: appDb);

      final recoveryKey = RecoveryKeyService.generateKey();
      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1000,
        recoveryKeyString: recoveryKey,
      );
      expect(await vaultService.hasRecoveryKey(), isTrue);

      final note = Note.create(title: 'To Be Wiped', body: 'Confidential');
      await repo.insertNote(note);
      await repo.lockNote(note.id, vaultService.vaultKey!);

      // Reset
      await vaultService.resetVault();

      expect(await vaultService.hasVault(), isFalse);
      expect(await vaultService.hasRecoveryKey(), isFalse);
      final meta = await vaultService.getVaultMetadata();
      expect(meta, isNull);

      final allActiveNotes = await repo.getActiveNotes();
      expect(allActiveNotes.isEmpty, isTrue);

      await appDb.close();
    });
  });

  group('M4.5 Schema v3 Migration from Real v2 Database File (R3)', () {
    test('Migrate v2 database file to v3: creates safety backup, adds recovery columns as null, preserves data', () async {
      final tempDir = Directory.systemTemp.createTempSync('db_v3_mig_test_');
      final dbPath = '${tempDir.path}/test_v2_to_v3.db';

      // 1. Manually create a genuine v2 database on disk
      final v2Db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            // Create v2 tables without recovery columns
            await db.execute('''
              CREATE TABLE vault_metadata (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                salt BLOB NOT NULL,
                kdf_algorithm TEXT NOT NULL,
                kdf_iterations INTEGER NOT NULL,
                credential_type TEXT NOT NULL DEFAULT 'pin',
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
                title TEXT,
                body TEXT,
                checklist_json TEXT,
                folder_id TEXT,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                is_archived INTEGER NOT NULL DEFAULT 0,
                is_trashed INTEGER NOT NULL DEFAULT 0,
                is_checklist_mode INTEGER NOT NULL DEFAULT 0,
                is_locked INTEGER NOT NULL DEFAULT 0,
                encrypted_blob BLOB,
                nonce BLOB,
                auth_tag BLOB,
                crypto_version INTEGER,
                color_index INTEGER NOT NULL DEFAULT 0,
                reminder_at INTEGER,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                trashed_at INTEGER
              );
            ''');
          },
        ),
      );

      await v2Db.insert('vault_metadata', {
        'id': 1,
        'salt': Uint8List(16),
        'kdf_algorithm': 'PBKDF2-HMAC-SHA256',
        'kdf_iterations': 100000,
        'credential_type': 'pin',
        'wrapped_vault_key': Uint8List(32),
        'wrapped_vault_key_iv': Uint8List(12),
        'wrapped_vault_key_tag': Uint8List(16),
        'version': 1,
        'created_at': 1700000000,
        'updated_at': 1700000000,
      });

      await v2Db.insert('notes', {
        'id': 'note_v2_1',
        'title': 'Existing V2 Note',
        'body': 'Valuable content',
        'is_locked': 0,
        'created_at': 1700000000,
        'updated_at': 1700000000,
      });
      await v2Db.close();

      // 2. Open via AppDatabase, which triggers migration to v3
      final appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
      final status = await appDb.initialize(overridePassword: 'test_db_password');
      expect(status, equals(DatabaseStatus.ready));

      // 3. Verify safety backup was created in backups/
      final backupDir = Directory('${tempDir.path}/backups');
      expect(backupDir.existsSync(), isTrue);
      final backups = backupDir.listSync().where((f) => f.path.endsWith('.db')).toList();
      expect(backups.length, equals(1));

      // 4. Verify v3 schema columns exist and are null
      final rows = await appDb.database.query('vault_metadata');
      expect(rows.length, equals(1));
      final v3Row = rows.first;
      expect(v3Row.containsKey('recovery_salt'), isTrue);
      expect(v3Row['recovery_salt'], isNull);
      expect(v3Row['recovery_wrapped_key'], isNull);
      expect(v3Row['recovery_iv'], isNull);
      expect(v3Row['recovery_tag'], isNull);
      expect(v3Row['recovery_version'], isNull);

      // Verify existing note was preserved
      final noteRows = await appDb.database.query('notes');
      expect(noteRows.length, equals(1));
      expect(noteRows.first['title'], equals('Existing V2 Note'));

      await appDb.close();
      tempDir.deleteSync(recursive: true);
    });
  });

  group('M4.5 Widget Tests (R4, R5, R6, R7)', () {
    testWidgets('VaultSetupScreen: mandatory step 3 & 4 with mismatch blocked', (tester) async {
      final fakeNotifier = _TestVaultNotifier();

      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultProvider.overrideWith((ref) => fakeNotifier),
          ],
          child: const MaterialApp(
            home: VaultSetupScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Enter 6-digit PIN
      expect(find.text('Enter your new PIN'), findsOneWidget);
      for (final digit in ['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.widgetWithText(InkWell, digit));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 2: Confirm 6-digit PIN
      expect(find.text('Confirm your PIN'), findsOneWidget);
      for (final digit in ['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.widgetWithText(InkWell, digit));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      // Step 3: Recovery Key Display (R4)
      expect(find.text('Write down your recovery key'), findsOneWidget);
      // The warning banner text updates for step >= 3
      expect(
        find.textContaining('whoever has this key can open all your notes'),
        findsOneWidget,
      );

      // Find the displayed recovery key text
      final keyFinder = find.byKey(const ValueKey('recovery_key_display_text'));
      expect(keyFinder, findsOneWidget);
      final displayedKey = (tester.widget(keyFinder) as Text).data!;
      expect(displayedKey.split('-').length, equals(7));

      // Advance to Step 4: Re-type confirmation
      // Step 4 has an autofocused TextField — cursor blink prevents pumpAndSettle
      await tester.tap(find.text('I have written it down'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Confirm recovery key'), findsOneWidget);
      expect(find.text('Confirm & Create Vault'), findsOneWidget);

      // Enter mismatched key
      await tester.enterText(find.byType(TextField), 'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-GGGG');
      await tester.tap(find.text('Confirm & Create Vault'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Mismatch is blocked
      expect(find.text('Recovery key does not match. Check for typing mistakes.'), findsOneWidget);
      expect(fakeNotifier.didCompleteSetup, isFalse);

      // Enter correct key
      await tester.enterText(find.byType(TextField), displayedKey);
      await tester.tap(find.text('Confirm & Create Vault'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeNotifier.didCompleteSetup, isTrue);
      expect(fakeNotifier.completedRecoveryKey, equals(displayedKey));
    });

    testWidgets('VaultRecoveryScreen: checksum typo shows warning without attempt; valid key advances', (tester) async {
      final validKey = RecoveryKeyService.generateKey();
      final recoveryBytes = RecoveryKeyService.decodeKey(validKey);
      final recoverySalt = Uint8List(16);
      final recoveryIv = Uint8List(12);
      final wrapBox = await RecoveryKeyService.wrapVaultKey(
        vaultKey: Uint8List(32),
        recoveryKeyBytes: recoveryBytes,
        salt: recoverySalt,
        iv: recoveryIv,
      );
      final fakeMeta = VaultMetadata(
        salt: Uint8List(16),
        kdfAlgorithm: 'argon2id',
        kdfIterations: 1000,
        credentialType: CredentialType.pin,
        wrappedVaultKey: Uint8List(32),
        wrappedVaultKeyIv: Uint8List(12),
        wrappedVaultKeyTag: Uint8List(16),
        version: 3,
        recoverySalt: recoverySalt,
        recoveryWrappedKey: Uint8List.fromList(wrapBox.cipherText),
        recoveryIv: recoveryIv,
        recoveryTag: Uint8List.fromList(wrapBox.mac.bytes),
        recoveryVersion: 1,
        createdAt: 0,
        updatedAt: 0,
      );
      final fakeVaultService = _FakeVaultService(metadata: fakeMeta);
      final fakeNotifier = _TestVaultNotifier();

      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultServiceProvider.overrideWithValue(fakeVaultService),
            vaultProvider.overrideWith((ref) => fakeNotifier),
          ],
          child: const MaterialApp(
            home: VaultRecoveryScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Enter your recovery key'), findsOneWidget);

      // 1. Enter invalid key (bad checksum / bad length) — does NOT count as attempt
      await tester.enterText(find.byType(TextField), 'WRONG-CHECKSUM-KEY');
      await tester.tap(find.text('Verify Recovery Key'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Check for typing mistakes.'), findsOneWidget);
      expect(fakeNotifier.recoverVaultCallCount, equals(0));

      // 1b. Enter well-formed WRONG key (valid checksum, but does not decrypt this vault) — counts as attempt
      final wrongValidKey = RecoveryKeyService.generateKey();
      await tester.enterText(find.byType(TextField), wrongValidKey);
      await tester.tap(find.text('Verify Recovery Key'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Incorrect recovery key. Please check your paper copy.'), findsOneWidget);
      expect(fakeNotifier.recoverVaultCallCount, equals(1));

      // 2. Enter valid key — unwrap succeeds, screen advances to step 1 (new PIN entry)
      await tester.enterText(find.byType(TextField), validKey);
      await tester.tap(find.text('Verify Recovery Key'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Advances to Step 1: Choose new PIN/Pattern
      expect(find.text('Enter your new PIN'), findsOneWidget);
    });

    testWidgets('VaultRecoveryKeyScreen: requires current secret, displays key with paper warning, blocks mismatch (R5, R7)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeVaultService = _FakeVaultService(metadata: null);
      final fakeNotifier = _TestVaultNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultServiceProvider.overrideWithValue(fakeVaultService),
            vaultProvider.overrideWith((ref) => fakeNotifier),
          ],
          child: const MaterialApp(
            home: VaultRecoveryKeyScreen(isRegenerating: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 0: Enter current PIN
      expect(find.text('Enter your current PIN'), findsOneWidget);
      for (final digit in ['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.widgetWithText(InkWell, digit));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Step 1: Display new recovery key (R7)
      expect(find.text('Write down your recovery key'), findsOneWidget);
      expect(find.textContaining('Write it on paper'), findsAtLeastNWidgets(1));

      final keyFinder = find.byWidgetPredicate(
        (w) => w is Text && w.data != null && w.data!.split('-').length == 7,
      );
      expect(keyFinder, findsOneWidget);
      final displayedKey = (tester.widget(keyFinder) as Text).data!;
      expect(displayedKey.split('-').length, equals(7));

      // Advance to Step 2: Confirm key
      await tester.tap(find.text('I have written it down'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Confirm recovery key'), findsOneWidget);

      // Enter mismatched key
      await tester.enterText(find.byType(TextField), 'WRONG-KEY-NOT-MATCHING');
      await tester.tap(find.text('Verify & Finish'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Recovery key does not match. Check for typing mistakes.'), findsOneWidget);
      expect(fakeNotifier.didCreateOrUpdateRecoveryKey, isFalse);

      // Enter correct key
      await tester.enterText(find.byType(TextField), displayedKey);
      await tester.tap(find.text('Verify & Finish'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeNotifier.didCreateOrUpdateRecoveryKey, isTrue);
      expect(fakeNotifier.updatedRecoveryKey, equals(displayedKey));
    });

    testWidgets('SettingsScreen: displays reminder when no recovery key, hides reminder when set (R5)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeNotifier = _TestVaultNotifier(hasRecoveryKey: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultProvider.overrideWith((ref) => fakeNotifier),
            settingsProvider.overrideWith((ref) => _TestSettingsNotifier()),
          ],
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Reminder banner is visible
      expect(find.textContaining('No recovery key created'), findsOneWidget);
      expect(find.text('Create recovery key'), findsOneWidget);

      // Vault notifier state updates to hasRecoveryKey = true
      fakeNotifier.updateHasRecoveryKey(true);
      await tester.pumpAndSettle();

      // Reminder banner is gone; "Generate a new recovery key" is shown
      expect(find.textContaining('No recovery key created'), findsNothing);
      expect(find.text('Generate a new recovery key'), findsOneWidget);
    });
  });
}

class _FakeVaultService implements VaultService {
  final VaultMetadata? metadata;
  final int recoveryLockoutSeconds;

  _FakeVaultService({this.metadata, this.recoveryLockoutSeconds = 0});

  @override
  Future<int> getRemainingRecoveryLockoutSeconds() async => recoveryLockoutSeconds;

  @override
  Future<VaultMetadata?> getVaultMetadata() async => metadata;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettingsNotifier extends ChangeNotifier implements AppSettingsNotifier {
  @override
  AppSettings get settings => AppSettings();

  @override
  bool get isLoaded => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestVaultNotifier extends ChangeNotifier implements VaultNotifier {
  VaultState _testState;
  bool didCompleteSetup = false;
  String? completedRecoveryKey;
  bool didCreateOrUpdateRecoveryKey = false;
  String? updatedRecoveryKey;
  int recoverVaultCallCount = 0;

  _TestVaultNotifier({
    bool hasVault = true,
    bool isUnlocked = false,
    bool hasRecoveryKey = true,
  }) : _testState = VaultState(
          hasVault: hasVault,
          isUnlocked: isUnlocked,
          hasRecoveryKey: hasRecoveryKey,
          credentialType: CredentialType.pin,
        );

  void updateHasRecoveryKey(bool value) {
    _testState = _testState.copyWith(hasRecoveryKey: value);
    notifyListeners();
  }

  @override
  VaultState get state => _testState;

  @override
  bool get hasVault => _testState.hasVault;

  @override
  bool get isUnlocked => _testState.isUnlocked;

  @override
  bool get hasRecoveryKey => _testState.hasRecoveryKey;

  @override
  CredentialType get credentialType => _testState.credentialType;

  @override
  int get remainingLockoutSeconds => _testState.remainingLockoutSeconds;

  @override
  int get remainingRecoveryLockoutSeconds => _testState.remainingRecoveryLockoutSeconds;

  @override
  Uint8List? get vaultKey => null;

  @override
  Future<void> loadVaultState() async {}

  @override
  Future<void> setupVault({
    required String secret,
    required CredentialType credentialType,
    String? recoveryKeyString,
    int? iterations,
  }) async {
    didCompleteSetup = true;
    completedRecoveryKey = recoveryKeyString;
  }

  @override
  Future<void> recoverVault({
    required String recoveryKeyString,
    required String newSecret,
    required CredentialType newCredentialType,
    int? iterations,
  }) async {
    recoverVaultCallCount++;
  }

  @override
  Future<void> createOrUpdateRecoveryKey({
    required String currentSecret,
    required String recoveryKeyString,
  }) async {
    didCreateOrUpdateRecoveryKey = true;
    updatedRecoveryKey = recoveryKeyString;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
