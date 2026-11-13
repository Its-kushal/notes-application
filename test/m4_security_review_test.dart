import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaflock/core/crypto/kdf_service.dart';
import 'package:leaflock/core/crypto/vault_service.dart';
import 'package:leaflock/core/database/app_database.dart';
import 'package:leaflock/features/export/export_service.dart';
import 'package:leaflock/features/locked_notes/presentation/controllers/vault_providers.dart';
import 'package:leaflock/features/locked_notes/presentation/screens/vault_setup_screen.dart';
import 'package:leaflock/features/notes/data/notes_repository.dart';
import 'package:leaflock/features/notes/domain/note.dart';
import 'package:leaflock/features/notes/presentation/controllers/notes_providers.dart';
import 'package:leaflock/features/notes/presentation/screens/note_editor_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ErroringKdfService implements KdfService {
  final Exception errorToThrow;
  ErroringKdfService(this.errorToThrow);

  @override
  Future<Uint8List> deriveKey({
    required String secret,
    required Uint8List salt,
    required int iterations,
    int keyLength = 32,
  }) async {
    throw errorToThrow;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.leaflock.app/security'),
      (call) async {
        if (call.method == 'getElapsedRealtime') {
          return 100000;
        }
        return null;
      },
    );
  });

  group('B1: changeSecret & Setup Screen Require Current Secret', () {
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
        kdfService: FakeKdfService(),
      );
      await vaultService.setupVault(
        secret: '111111',
        credentialType: CredentialType.pin,
        iterations: 1000,
      );
    });

    tearDown(() async {
      await appDb.close();
    });

    test('changeSecret throws VaultAuthException when currentSecret is wrong even if vault is unlocked', () async {
      expect(vaultService.isUnlocked, isTrue);

      // Wrong current secret must throw VaultAuthException
      await expectLater(
        () => vaultService.changeSecret(
          currentSecret: 'wrong_pin',
          newSecret: '222222',
          newCredentialType: CredentialType.pin,
          iterations: 1000,
        ),
        throwsA(isA<VaultAuthException>()),
      );

      // Re-locking and unlocking with old secret succeeds (secret was NOT changed)
      vaultService.lockVault();
      await vaultService.unlockVault('111111');
      expect(vaultService.isUnlocked, isTrue);

      // Correct current secret succeeds and re-wraps key
      await vaultService.changeSecret(
        currentSecret: '111111',
        newSecret: '222222',
        newCredentialType: CredentialType.pin,
        iterations: 1000,
      );

      vaultService.lockVault();
      // Old secret now fails
      await expectLater(
        () => vaultService.unlockVault('111111'),
        throwsA(isA<VaultAuthException>()),
      );
      // New secret unlocks
      await vaultService.unlockVault('222222');
      expect(vaultService.isUnlocked, isTrue);
    });

    testWidgets('VaultSetupScreen(isChangingSecret: true) asks for current secret first at step 0', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fakeNotifier = VaultNotifier(vaultService: vaultService);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultProvider.overrideWith((ref) => fakeNotifier),
            vaultServiceProvider.overrideWithValue(vaultService),
            kdfServiceProvider.overrideWithValue(FakeKdfService()),
          ],
          child: const MaterialApp(
            home: VaultSetupScreen(isChangingSecret: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 0: prompt asks for current PIN
      expect(find.text('Enter your current PIN'), findsOneWidget);
      expect(find.text('Confirm current secret before setting a new credential'), findsOneWidget);

      // Input incorrect current PIN (e.g. 999999)
      for (final digit in ['9', '9', '9', '9', '9', '9']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      // Error shown
      expect(find.text('Current secret is incorrect.'), findsOneWidget);
      expect(find.text('Enter your current PIN'), findsOneWidget);

      // Clear with backspace x6
      for (int i = 0; i < 6; i++) {
        await tester.tap(find.byIcon(Icons.backspace_outlined));
        await tester.pump();
      }

      // Input correct current PIN 111111
      for (final digit in ['1', '1', '1', '1', '1', '1']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();

      // Advanced to Step 1: Enter your new PIN + shows credential type selector
      expect(find.text('Enter your new PIN'), findsOneWidget);
      expect(find.text('PIN (min 6)'), findsOneWidget);
      expect(find.text('Pattern (min 5)'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('B3: Distinguish Native/KDF Failure from Wrong Secret', () {
    late AppDatabase appDb;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_db_password');
    });

    tearDown(() async {
      await appDb.close();
    });

    test('PlatformException during KDF throws VaultPlatformException and does not increment failed attempts', () async {
      final setupVault = VaultService(appDatabase: appDb, kdfService: FakeKdfService());
      await setupVault.setupVault(secret: '123456', credentialType: CredentialType.pin, iterations: 1000);
      setupVault.lockVault();

      // VaultService with failing KDF
      final failingVault = VaultService(
        appDatabase: appDb,
        kdfService: ErroringKdfService(PlatformException(code: 'KDF_CRASH', message: 'Hardware keystore dead')),
      );

      // Attempt unlock -> must throw VaultPlatformException, NOT VaultAuthException
      await expectLater(
        () => failingVault.unlockVault('123456'),
        throwsA(isA<VaultPlatformException>()),
      );

      // Failed attempts counter must remain 0!
      expect(await failingVault.getFailedAttempts(), equals(0));
      expect(await failingVault.getRemainingLockoutSeconds(), equals(0));
    });

    test('VaultNotifier reports KDF error message and does not say Incorrect secret', () async {
      final setupVault = VaultService(appDatabase: appDb, kdfService: FakeKdfService());
      await setupVault.setupVault(secret: '123456', credentialType: CredentialType.pin, iterations: 1000);
      setupVault.lockVault();

      final failingVault = VaultService(
        appDatabase: appDb,
        kdfService: ErroringKdfService(PlatformException(code: 'KDF_CRASH', message: 'Hardware keystore dead')),
      );
      final notifier = VaultNotifier(vaultService: failingVault);

      try {
        await notifier.unlockVault('123456');
      } catch (_) {}

      expect(notifier.state.errorMessage, contains('Hardware keystore dead'));
      expect(notifier.state.errorMessage, isNot(contains('Incorrect secret')));
      expect(notifier.state.failedAttempts, equals(0));
    });
  });

  group('B4: Tamper-Resistant Lockout (elapsedRealtime & Rollback Protection)', () {
    late AppDatabase appDb;
    late VaultService vaultService;
    DateTime simulatedNow = DateTime(2026, 10, 23, 10, 0, 0);
    int simulatedElapsed = 100000; // 100 seconds since boot

    setUp(() async {
      simulatedNow = DateTime(2026, 10, 23, 10, 0, 0);
      simulatedElapsed = 100000;
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_db_password');
      vaultService = VaultService(
        appDatabase: appDb,
        kdfService: FakeKdfService(),
        clock: () => simulatedNow,
        elapsedRealtimeProvider: () async => simulatedElapsed,
      );
      await vaultService.setupVault(secret: '123456', credentialType: CredentialType.pin, iterations: 1000);
      vaultService.lockVault();
    });

    tearDown(() async {
      await appDb.close();
    });

    test('Forward wall-clock change cannot bypass lockout when elapsedRealtime has not expired', () async {
      // 5 failed attempts -> 30s lockout
      for (int i = 0; i < 5; i++) {
        try {
          await vaultService.unlockVault('wrong');
        } catch (_) {}
      }
      expect(await vaultService.getRemainingLockoutSeconds(), equals(30));

      // User leaps wall-clock 1 day into future, but only 5s passed on elapsedRealtime
      simulatedNow = simulatedNow.add(const Duration(days: 1));
      simulatedElapsed += 5000;

      // Lockout must STILL be in effect (~25s remaining)!
      final remaining = await vaultService.getRemainingLockoutSeconds();
      expect(remaining, greaterThan(20));
      expect(remaining, lessThanOrEqualTo(25));

      await expectLater(
        () => vaultService.unlockVault('123456'),
        throwsA(isA<VaultLockoutException>()),
      );

      // Advance elapsedRealtime by remaining 26 seconds -> expires
      simulatedElapsed += 26000;
      expect(await vaultService.getRemainingLockoutSeconds(), equals(0));
      await vaultService.unlockVault('123456');
      expect(vaultService.isUnlocked, isTrue);
    });

    test('Clock rollback detection prevents bypassing lockout by winding clock backwards', () async {
      for (int i = 0; i < 5; i++) {
        try {
          await vaultService.unlockVault('wrong');
        } catch (_) {}
      }

      // User winds clock backward by 2 hours
      simulatedNow = simulatedNow.subtract(const Duration(hours: 2));

      // VaultService without elapsedRealtime (simulating wall-clock mode or reboot)
      final wallClockVault = VaultService(
        appDatabase: appDb,
        kdfService: FakeKdfService(),
        clock: () => simulatedNow,
      );

      // Rollback detected! Lockout remains enforced
      final remaining = await wallClockVault.getRemainingLockoutSeconds();
      expect(remaining, equals(30));
    });
  });

  group('B5: lockNote Concurrency Guard & Lock Confirmation Dialog', () {
    late AppDatabase appDb;
    late SqlNotesRepository repo;
    late VaultService vaultService;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_db_password');
      repo = SqlNotesRepository(appDatabase: appDb);
      vaultService = VaultService(appDatabase: appDb, kdfService: FakeKdfService());
      await vaultService.setupVault(secret: '123456', credentialType: CredentialType.pin, iterations: 1000);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('lockNote throws StateError if note updated_at changed concurrently', () async {
      final note = Note.create(title: 'Race Note', body: 'Original Content');
      await repo.insertNote(note);

      // Read note
      final fetched = await repo.getNoteById(note.id);
      expect(fetched, isNotNull);

      // Simulate concurrent update before lockNote executes
      await appDb.database.update(
        'notes',
        {'updated_at': fetched!.updatedAt + 500, 'body': 'Concurrent edit content'},
        where: 'id = ?',
        whereArgs: [note.id],
      );

      // lockNote must detect updated_at mismatch and reject the lock
      await expectLater(
        () => repo.lockNote(note.id, vaultService.vaultKey!, expectedUpdatedAt: fetched.updatedAt),
        throwsA(isA<StateError>()),
      );

      // Verify the concurrent content was preserved and note was NOT locked
      final preserved = await repo.getNoteById(note.id);
      expect(preserved!.isLocked, isFalse);
      expect(preserved.body, equals('Concurrent edit content'));
    });

    testWidgets('Editor lock confirmation dialog warns that folder, pin, archive and color are cleared', (tester) async {
      final note = Note.create(
        title: 'Important Note',
        body: 'Body content',
        isPinned: true,
        isArchived: false,
        colorLabel: 2,
      );
      await tester.runAsync(() async {
        await repo.insertNote(note);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notesRepositoryProvider.overrideWithValue(repo),
            vaultServiceProvider.overrideWithValue(vaultService),
            vaultProvider.overrideWith((ref) => VaultNotifier(vaultService: vaultService)),
          ],
          child: MaterialApp(
            home: NoteEditorScreen(note: note),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Open overflow menu and tap "Lock note"
      await tester.tap(find.byTooltip('More options'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Lock note'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify confirmation dialog title and content
      expect(find.text('Lock note?'), findsOneWidget);
      expect(
        find.text('Locking will encrypt this note with your vault key. Its folder, pin, archive status, and color label will be cleared.'),
        findsOneWidget,
      );

      // Tap Cancel -> does NOT lock
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      late Note? noteAfterCancel;
      await tester.runAsync(() async {
        noteAfterCancel = await repo.getNoteById(note.id);
      });
      expect(noteAfterCancel!.isLocked, isFalse);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('C1: Export of Locked Note is Impossible', () {
    late AppDatabase appDb;
    late SqlNotesRepository repo;
    late VaultService vaultService;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_db_password');
      repo = SqlNotesRepository(appDatabase: appDb);
      vaultService = VaultService(
        appDatabase: appDb,
        kdfService: FakeKdfService(),
      );
    });

    tearDown(() async {
      await appDb.close();
    });

    test('ExportService refuses to export locked notes', () async {
      final lockedNote = Note.create(title: 'Locked Note', body: 'Secret').copyWith(isLocked: true);

      expect(
        () => ExportService.formatNoteText(lockedNote),
        throwsA(isA<ExportSecurityException>()),
      );

      await expectLater(
        () => ExportService.shareNote(lockedNote),
        throwsA(isA<ExportSecurityException>()),
      );

      await expectLater(
        () => ExportService.saveToDevice(lockedNote),
        throwsA(isA<ExportSecurityException>()),
      );
    });

    testWidgets('NoteEditorScreen does not display Export option when note is locked', (tester) async {
      late Note lockedNote;
      await tester.runAsync(() async {
        await vaultService.setupVault(secret: '123456', credentialType: CredentialType.pin, iterations: 1000);
        final normalNote = Note.create(title: 'Top Secret Note', body: 'Confidential content');
        await repo.insertNote(normalNote);
        await repo.lockNote(normalNote.id, vaultService.vaultKey!);
        lockedNote = (await repo.getNoteById(normalNote.id))!;
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notesRepositoryProvider.overrideWithValue(repo),
            vaultServiceProvider.overrideWithValue(vaultService),
            vaultProvider.overrideWith((ref) => VaultNotifier(vaultService: vaultService)),
            kdfServiceProvider.overrideWithValue(FakeKdfService()),
          ],
          child: MaterialApp(
            home: NoteEditorScreen(note: lockedNote),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byTooltip('More options'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Export note'), findsNothing);
      expect(find.text('Unlock note'), findsOneWidget);
      expect(find.text('Delete permanently'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('D2 & D3: Pre-migration Safety Backup & Startup Integrity Check', () {
    test('Safety copy before migration: failed migration leaves original untouched and enters recoveryNeeded', () async {
      final tempDir = Directory.systemTemp.createTempSync('db_mig_test_');
      final dbPath = '${tempDir.path}/test_migration.db';

      // 1. Create v1 database on disk
      final v1Db = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await AppDatabase.createSchemaV1(db);
          },
        ),
      );
      await v1Db.insert('notes', {
        'id': 'v1_note_1',
        'title': 'Original V1 Note',
        'body': 'Crucial user note that must survive',
        'is_locked': 0,
        'created_at': 1000,
        'updated_at': 1000,
      });
      await v1Db.close();

      // 2. Simulate failed migration to v2
      AppDatabase.failMigrationForTesting = true;
      addTearDown(() => AppDatabase.failMigrationForTesting = false);

      final appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
      final status = await appDb.initialize(overridePassword: 'test_password');
      expect(status, equals(DatabaseStatus.recoveryNeeded));

      // 3. Verify backup file was created in backups/ directory and opens with key
      final backupDir = Directory('${tempDir.path}/backups');
      expect(backupDir.existsSync(), isTrue);
      final backups = backupDir.listSync().where((f) => f.path.endsWith('.db')).toList();
      expect(backups.length, equals(1));

      final backupDb = await databaseFactoryFfi.openDatabase(
        backups.first.path,
        options: OpenDatabaseOptions(),
      );
      final backupNotes = await backupDb.query('notes');
      expect(backupNotes.length, equals(1));
      expect(backupNotes.first['title'], equals('Original V1 Note'));
      await backupDb.close();

      // 4. Verify original file still exists and was NOT corrupted or lost
      final checkDb = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(),
      );
      final notes = await checkDb.query('notes');
      expect(notes.length, equals(1));
      expect(notes.first['title'], equals('Original V1 Note'));
      await checkDb.close();

      tempDir.deleteSync(recursive: true);
    });

    test('Corrupted DB at startup triggers recoveryNeeded without deleting the file', () async {
      final tempDir = Directory.systemTemp.createTempSync('db_corrupt_test_');
      final dbPath = '${tempDir.path}/corrupt.db';

      // Write garbage data to file
      File(dbPath).writeAsBytesSync(List.filled(2048, 0xAA));

      final appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: dbPath,
      );
      final status = await appDb.initialize(overridePassword: 'any_password');
      expect(status, equals(DatabaseStatus.recoveryNeeded));

      // File must NOT be deleted
      expect(File(dbPath).existsSync(), isTrue);
      tempDir.deleteSync(recursive: true);
    });
  });

  group('B1: Unauthenticated Reset Paths Strictly Removed', () {
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

      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1000,
      );

      final note = Note.create(title: 'Top Secret Note', body: 'Sensitive contents');
      await repo.insertNote(note);
      await repo.lockNote(note.id, vaultService.vaultKey!);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('VaultService.resetVaultWithAuthorization with no proof throws and deletes nothing', () async {
      expect(await vaultService.hasVault(), isTrue);
      final preNotes = await appDb.database.query('notes', where: 'is_locked = 1');
      expect(preNotes, isNotEmpty);

      // Attempt reset with no secret and no recovery key
      await expectLater(
        () => vaultService.resetVaultWithAuthorization(),
        throwsA(isA<ArgumentError>()),
      );

      // Vault and locked notes must remain completely intact
      expect(await vaultService.hasVault(), isTrue);
      final postNotes = await appDb.database.query('notes', where: 'is_locked = 1');
      expect(postNotes.length, equals(preNotes.length));
    });

    test('VaultNotifier.resetVault with no proof throws and deletes nothing', () async {
      final notifier = VaultNotifier(vaultService: vaultService);
      await notifier.loadVaultState();
      expect(notifier.state.hasVault, isTrue);

      final preNotes = await appDb.database.query('notes', where: 'is_locked = 1');
      expect(preNotes, isNotEmpty);

      // Attempt unauthenticated reset
      await expectLater(
        () => notifier.resetVault(),
        throwsA(isA<ArgumentError>()),
      );

      // Vault and locked notes must remain completely intact
      expect(await vaultService.hasVault(), isTrue);
      final postNotes = await appDb.database.query('notes', where: 'is_locked = 1');
      expect(postNotes.length, equals(preNotes.length));
    });
  });
}
