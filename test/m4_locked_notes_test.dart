import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/core/crypto/id_generator.dart';
import 'package:privacy_notes/core/crypto/kdf_service.dart';
import 'package:privacy_notes/core/crypto/vault_service.dart';
import 'package:privacy_notes/core/database/app_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:privacy_notes/features/locked_notes/presentation/controllers/vault_providers.dart';
import 'package:privacy_notes/features/locked_notes/presentation/screens/vault_setup_screen.dart';
import 'package:privacy_notes/features/locked_notes/presentation/screens/vault_unlock_screen.dart';
import 'package:privacy_notes/features/locked_notes/presentation/widgets/pattern_lock_widget.dart';
import 'package:privacy_notes/features/locked_notes/presentation/widgets/pin_pad_widget.dart';
import 'package:privacy_notes/features/notes/data/notes_repository.dart';
import 'package:privacy_notes/features/notes/domain/checklist_item.dart';
import 'package:privacy_notes/features/notes/domain/note.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('M4 Crypto & Derivation Unit Tests', () {
    late AppDatabase appDb;
    late SqlNotesRepository repo;
    late VaultService vaultService;
    late FakeKdfService fakeKdf;
    DateTime simulatedNow = DateTime(2026, 10, 22, 12, 0, 0);

    setUp(() async {
      simulatedNow = DateTime(2026, 10, 22, 12, 0, 0);
      fakeKdf = FakeKdfService();
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_db_password');
      repo = SqlNotesRepository(appDatabase: appDb);
      vaultService = VaultService(
        appDatabase: appDb,
        kdfService: fakeKdf,
        clock: () => simulatedNow,
      );
    });

    tearDown(() async {
      await appDb.close();
    });

    test('Round-trip encryption & decryption for text note and checklist note', () async {
      // 1. Setup vault
      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1000,
      );
      expect(vaultService.isUnlocked, isTrue);
      final vaultKey = vaultService.vaultKey!;

      // 2. Create text note and lock it
      final textNote = Note.create(
        title: 'Secret Text Title',
        body: 'Confidential body content',
      );
      await repo.insertNote(textNote);
      await repo.lockNote(textNote.id, vaultKey);

      // Verify decrypted locked note
      final decryptedTextNote = await repo.getLockedNoteById(textNote.id, vaultKey);
      expect(decryptedTextNote, isNotNull);
      expect(decryptedTextNote!.title, equals('Secret Text Title'));
      expect(decryptedTextNote.body, equals('Confidential body content'));
      expect(decryptedTextNote.isLocked, isTrue);

      // 3. Create checklist note and lock it
      final items = [
        ChecklistItem(id: 'c1', text: 'Task 1', isChecked: true),
        ChecklistItem(id: 'c2', text: 'Task 2', isChecked: false),
      ];
      final checklistNote = Note.create(
        title: 'Secret Checklist',
        body: ChecklistItem.toPlainText(items),
        checklistJson: ChecklistItem.encodeList(items),
        isChecklistMode: true,
      );
      await repo.insertNote(checklistNote);
      await repo.lockNote(checklistNote.id, vaultKey);

      final decryptedChecklistNote = await repo.getLockedNoteById(checklistNote.id, vaultKey);
      expect(decryptedChecklistNote, isNotNull);
      expect(decryptedChecklistNote!.title, equals('Secret Checklist'));
      expect(decryptedChecklistNote.isChecklistMode, isTrue);
      expect(decryptedChecklistNote.checklistJson, isNotNull);

      final parsedItems = ChecklistItem.parseList(decryptedChecklistNote.checklistJson);
      expect(parsedItems.length, equals(2));
      expect(parsedItems[0].text, equals('Task 1'));
      expect(parsedItems[0].isChecked, isTrue);
      expect(parsedItems[1].text, equals('Task 2'));
      expect(parsedItems[1].isChecked, isFalse);
    });

    test('Ciphertext tampering (flip a byte) fails authentication', () async {
      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1000,
      );
      final vaultKey = vaultService.vaultKey!;

      final note = Note.create(title: 'Top Secret', body: 'Sensitive data');
      await repo.insertNote(note);
      await repo.lockNote(note.id, vaultKey);

      // Read raw ciphertext from database
      final rows = await appDb.database.query(
        'notes',
        columns: ['encrypted_payload'],
        where: 'id = ?',
        whereArgs: [note.id],
      );
      final rawPayload = Uint8List.fromList(rows.first['encrypted_payload'] as List<int>);

      // Tamper with first byte
      rawPayload[0] ^= 0xFF;

      await appDb.database.update(
        'notes',
        {'encrypted_payload': rawPayload},
        where: 'id = ?',
        whereArgs: [note.id],
      );

      // Decryption must throw SecretBoxAuthenticationError
      expect(
        () async => await repo.getLockedNoteById(note.id, vaultKey),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('Swapping ciphertext between two notes fails because AAD is bound to note ID', () async {
      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1000,
      );
      final vaultKey = vaultService.vaultKey!;

      final noteA = Note.create(title: 'Note A', body: 'Body A');
      final noteB = Note.create(title: 'Note B', body: 'Body B');
      await repo.insertNote(noteA);
      await repo.insertNote(noteB);

      await repo.lockNote(noteA.id, vaultKey);
      await repo.lockNote(noteB.id, vaultKey);

      final rowA = (await appDb.database.query('notes', where: 'id = ?', whereArgs: [noteA.id])).first;

      // Copy Note A's payload, IV, and tag onto Note B
      await appDb.database.update(
        'notes',
        {
          'encrypted_payload': rowA['encrypted_payload'],
          'payload_iv': rowA['payload_iv'],
          'payload_tag': rowA['payload_tag'],
        },
        where: 'id = ?',
        whereArgs: [noteB.id],
      );

      // Decrypting Note B with Note A's ciphertext must fail because AAD differs ('vault:note:<id>')
      expect(
        () async => await repo.getLockedNoteById(noteB.id, vaultKey),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('Wrong secret fails cleanly and throws VaultAuthException', () async {
      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1000,
      );
      vaultService.lockVault();

      expect(
        () async => await vaultService.unlockVault('wrong_pin'),
        throwsA(isA<VaultAuthException>()),
      );
      expect(vaultService.isUnlocked, isFalse);
    });
  });

  group('M4 Plaintext Sanitization & Database Constraints', () {
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

    test('Locking note sanitizes plaintext columns at DB level and satisfies CHECK constraint', () async {
      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1000,
      );
      final vaultKey = vaultService.vaultKey!;

      final note = Note.create(
        title: 'Sensitive Title',
        body: 'Sensitive Body with multiple words',
      );
      await repo.insertNote(note);
      await repo.lockNote(note.id, vaultKey);

      // Check SQLite raw columns directly
      final rows = await appDb.database.query('notes', where: 'id = ?', whereArgs: [note.id]);
      expect(rows.length, equals(1));
      final row = rows.first;

      expect(row['title'], equals(''));
      expect(row['body'], equals(''));
      expect(row['checklist_json'], isNull);
      expect(row['word_count'], equals(0));
      expect(row['is_locked'], equals(1));
      expect(row['encrypted_payload'], isNotNull);
      expect(row['payload_iv'], isNotNull);
      expect(row['payload_tag'], isNotNull);
    });

    test('SQLite CHECK constraint rejects locked notes with plaintext content or missing crypto fields', () async {
      final sampleBytes = Uint8List.fromList([1, 2, 3]);

      // 1. Violate: is_locked = 1 with non-empty title
      await expectLater(
        () => appDb.database.insert('notes', {
          'id': IdGenerator.generateUuidV4(),
          'title': 'Leaked Title',
          'body': '',
          'is_locked': 1,
          'encrypted_payload': sampleBytes,
          'payload_iv': sampleBytes,
          'payload_tag': sampleBytes,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );

      // 2. Violate: is_locked = 1 with null encrypted_payload
      await expectLater(
        () => appDb.database.insert('notes', {
          'id': IdGenerator.generateUuidV4(),
          'title': '',
          'body': '',
          'is_locked': 1,
          'encrypted_payload': null,
          'payload_iv': sampleBytes,
          'payload_tag': sampleBytes,
          'created_at': 1000,
          'updated_at': 1000,
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('M4 Complete Exclusion of Locked Notes from Normal Operations', () {
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
      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1000,
      );
    });

    tearDown(() async {
      await appDb.close();
    });

    test('Locked notes are excluded from active list, search, archive, trash, word counts, and bulk actions', () async {
      final vaultKey = vaultService.vaultKey!;

      // Create folder
      final folder = await repo.createFolder('Confidential Folder');
      final folderId = folder.id;

      // Create regular note and locked note
      final regularNote = Note.create(
        title: 'Public Document',
        body: 'Public body information',
        folderId: folderId,
      );
      final sensitiveNote = Note.create(
        title: 'Classified Document',
        body: 'Classified body information',
        folderId: folderId,
      );

      await repo.insertNote(regularNote);
      await repo.insertNote(sensitiveNote);

      await repo.lockNote(sensitiveNote.id, vaultKey);

      // 1. Active notes list does not contain locked note
      final activeNotes = await repo.getActiveNotes();
      expect(activeNotes.length, equals(1));
      expect(activeNotes.first.id, equals(regularNote.id));

      // 2. Folder filter does not contain locked note
      final folderNotes = await repo.getActiveNotes(folderId: folderId);
      expect(folderNotes.length, equals(1));
      expect(folderNotes.first.id, equals(regularNote.id));

      // 3. Search does not match locked note
      final searchResults = await repo.searchNotes('Classified');
      expect(searchResults, isEmpty);

      // 4. Archive does not contain locked note
      final archived = await repo.getArchivedNotes();
      expect(archived, isEmpty);

      // 5. Trash does not contain locked note
      final trashed = await repo.getTrashedNotes();
      expect(trashed, isEmpty);

      // 6. Bulk move ignores locked note
      await repo.moveNotesToFolder([regularNote.id, sensitiveNote.id], folderId);
      final rawSensitive = (await appDb.database.query('notes', where: 'id = ?', whereArgs: [sensitiveNote.id])).first;
      expect(rawSensitive['folder_id'], isNull); // Remains null, locked notes cannot be moved

      // 7. Bulk trash ignores locked note
      await repo.trashNotes([regularNote.id, sensitiveNote.id]);
      final rawSensitiveAfterTrash = (await appDb.database.query('notes', where: 'id = ?', whereArgs: [sensitiveNote.id])).first;
      expect(rawSensitiveAfterTrash['trashed_at'], isNull);

      // 8. Empty trash does NOT delete locked note
      await repo.emptyTrash();
      final sensitiveStillExists = await appDb.database.query('notes', where: 'id = ?', whereArgs: [sensitiveNote.id]);
      expect(sensitiveStillExists, isNotEmpty);

      // 9. Startup purge does NOT delete locked note
      await repo.purgeEmptyNotes();
      final sensitiveStillExistsAfterPurge = await appDb.database.query('notes', where: 'id = ?', whereArgs: [sensitiveNote.id]);
      expect(sensitiveStillExistsAfterPurge, isNotEmpty);
    });
  });

  group('M4 Lockout Delay Schedule & Persistence', () {
    late AppDatabase appDb;
    late VaultService vaultService;
    DateTime simulatedNow = DateTime(2026, 10, 22, 12, 0, 0);

    setUp(() async {
      simulatedNow = DateTime(2026, 10, 22, 12, 0, 0);
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_db_password');
      vaultService = VaultService(
        appDatabase: appDb,
        kdfService: FakeKdfService(),
        clock: () => simulatedNow,
      );
      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1000,
      );
      vaultService.lockVault();
    });

    tearDown(() async {
      await appDb.close();
    });

    test('Lockout schedule enforces 0s (1-4), 30s (5), 1m (6), 5m (7), 15m (8), 30m (9+) delays and persists', () async {
      // Attempts 1-4: no delay
      for (int i = 1; i <= 4; i++) {
        await expectLater(() => vaultService.unlockVault('wrong'), throwsA(isA<VaultAuthException>()));
        expect(await vaultService.getRemainingLockoutSeconds(), equals(0));
      }

      // Attempt 5: 30s delay
      await expectLater(() => vaultService.unlockVault('wrong'), throwsA(isA<VaultAuthException>()));
      expect(await vaultService.getRemainingLockoutSeconds(), equals(30));

      // Attempting to unlock while locked out throws VaultLockoutException
      await expectLater(
        () => vaultService.unlockVault('123456'),
        throwsA(isA<VaultLockoutException>()),
      );

      // Advance clock by 31 seconds -> lockout expires
      simulatedNow = simulatedNow.add(const Duration(seconds: 31));
      expect(await vaultService.getRemainingLockoutSeconds(), equals(0));

      // Attempt 6: 60s delay
      await expectLater(() => vaultService.unlockVault('wrong'), throwsA(isA<VaultAuthException>()));
      expect(await vaultService.getRemainingLockoutSeconds(), equals(60));

      // Advance clock 61 seconds
      simulatedNow = simulatedNow.add(const Duration(seconds: 61));

      // Attempt 7: 300s (5 min) delay
      await expectLater(() => vaultService.unlockVault('wrong'), throwsA(isA<VaultAuthException>()));
      expect(await vaultService.getRemainingLockoutSeconds(), equals(300));

      // Advance clock 301 seconds
      simulatedNow = simulatedNow.add(const Duration(seconds: 301));

      // Attempt 8: 900s (15 min) delay
      await expectLater(() => vaultService.unlockVault('wrong'), throwsA(isA<VaultAuthException>()));
      expect(await vaultService.getRemainingLockoutSeconds(), equals(900));

      // Advance clock 901 seconds
      simulatedNow = simulatedNow.add(const Duration(seconds: 901));

      // Attempt 9+: 1800s (30 min) delay cap
      await expectLater(() => vaultService.unlockVault('wrong'), throwsA(isA<VaultAuthException>()));
      expect(await vaultService.getRemainingLockoutSeconds(), equals(1800));

      // Persistence check: simulate app kill and restart
      final newVaultService = VaultService(
        appDatabase: appDb,
        kdfService: FakeKdfService(),
        clock: () => simulatedNow,
      );
      expect(await newVaultService.getRemainingLockoutSeconds(), equals(1800));
      expect(await newVaultService.getFailedAttempts(), equals(9));

      // Advance past 1800 seconds and unlock with correct secret -> clears failures
      simulatedNow = simulatedNow.add(const Duration(seconds: 1801));
      await newVaultService.unlockVault('123456');
      expect(newVaultService.isUnlocked, isTrue);
      expect(await newVaultService.getFailedAttempts(), equals(0));
      expect(await newVaultService.getRemainingLockoutSeconds(), equals(0));
    });
  });

  group('M4 Secret Change, Credential Switch & Reset Vault', () {
    late AppDatabase appDb;
    late SqlNotesRepository repo;
    late VaultService vaultService;
    DateTime simulatedNow = DateTime(2026, 10, 22, 12, 0, 0);

    setUp(() async {
      simulatedNow = DateTime(2026, 10, 22, 12, 0, 0);
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_db_password');
      repo = SqlNotesRepository(appDatabase: appDb);
      vaultService = VaultService(
        appDatabase: appDb,
        kdfService: FakeKdfService(),
        clock: () => simulatedNow,
      );
      await vaultService.setupVault(
        secret: '1111',
        credentialType: CredentialType.pin,
        iterations: 1000,
      );
    });

    tearDown(() async {
      await appDb.close();
    });

    test('Change secret re-wraps vault key; existing notes decrypt with new secret and fail with old', () async {
      final oldKey = vaultService.vaultKey!;

      // Create and lock a note
      final note = Note.create(title: 'Important Note', body: 'Confidential message');
      await repo.insertNote(note);
      await repo.lockNote(note.id, oldKey);

      // Change PIN from 1111 to 2222
      await vaultService.changeSecret(
        currentSecret: '1111',
        newSecret: '2222',
        newCredentialType: CredentialType.pin,
        iterations: 1000,
      );

      // Lock vault
      vaultService.lockVault();
      expect(vaultService.isUnlocked, isFalse);

      // Old secret fails
      expect(() async => await vaultService.unlockVault('1111'), throwsA(isA<VaultAuthException>()));

      // New secret unlocks
      await vaultService.unlockVault('2222');
      expect(vaultService.isUnlocked, isTrue);

      // Existing note decryptions continue to succeed
      final decrypted = await repo.getLockedNoteById(note.id, vaultService.vaultKey!);
      expect(decrypted, isNotNull);
      expect(decrypted!.title, equals('Important Note'));
      expect(decrypted.body, equals('Confidential message'));
    });

    test('Switch credential from PIN to Pattern works and updates metadata', () async {
      // Switch to pattern '01258'
      await vaultService.changeSecret(
        currentSecret: '1111',
        newSecret: '01258',
        newCredentialType: CredentialType.pattern,
        iterations: 1000,
      );

      final meta = await vaultService.getVaultMetadata();
      expect(meta, isNotNull);
      expect(meta!.credentialType, equals(CredentialType.pattern));

      vaultService.lockVault();

      // Unlock with pattern
      await vaultService.unlockVault('01258');
      expect(vaultService.isUnlocked, isTrue);
    });

    test('Reset locked notes deletes all locked notes and vault metadata, leaving normal notes untouched', () async {
      final normalNote = Note.create(title: 'Normal Note', body: 'Keep me safe');
      final lockedNote = Note.create(title: 'Locked Note', body: 'Sensitive');

      await repo.insertNote(normalNote);
      await repo.insertNote(lockedNote);
      await repo.lockNote(lockedNote.id, vaultService.vaultKey!);

      // Reset vault
      await vaultService.resetVault();
      expect(await vaultService.hasVault(), isFalse);
      expect(vaultService.isUnlocked, isFalse);

      // Locked note is permanently deleted
      final lockedRows = await appDb.database.query('notes', where: 'id = ?', whereArgs: [lockedNote.id]);
      expect(lockedRows, isEmpty);

      // Normal note remains intact
      final normalRows = await appDb.database.query('notes', where: 'id = ?', whereArgs: [normalNote.id]);
      expect(normalRows, isNotEmpty);
      expect(normalRows.first['title'], equals('Normal Note'));
    });

    test('Auto-lock drops vault key on background pause and when timeout threshold is exceeded', () async {
      final notifier = VaultNotifier(vaultService: vaultService);
      await notifier.setAutoLockTimeout('background');

      // Setup and unlock
      await notifier.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        iterations: 1000,
      );
      expect(notifier.isUnlocked, isTrue);

      // App paused with 'background' auto-lock immediately locks vault
      notifier.onAppPaused();
      expect(notifier.isUnlocked, isFalse);
      expect(vaultService.vaultKey, isNull);

      // Unlock again
      await notifier.unlockVault('123456');
      expect(notifier.isUnlocked, isTrue);

      // Change timeout to '1_min'
      await notifier.setAutoLockTimeout('1_min');

      // Pause at T=0
      notifier.onAppPaused();
      expect(notifier.isUnlocked, isTrue); // Not locked yet

      // Resume at T=30s -> remains unlocked
      simulatedNow = simulatedNow.add(const Duration(seconds: 30));
      notifier.onAppResumed();
      expect(notifier.isUnlocked, isTrue);

      // Pause again at T=30s
      notifier.onAppPaused();

      // Resume at T=95s (65s elapsed > 60s) -> locks!
      simulatedNow = simulatedNow.add(const Duration(seconds: 65));
      notifier.onAppResumed();
      expect(notifier.isUnlocked, isFalse);
      expect(vaultService.vaultKey, isNull);
    });
  });

  group('M4 UI & Widget Tests', () {
    testWidgets('PinPadWidget responds to digit taps, backspace, and TalkBack semantics', (tester) async {
      String currentPin = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return PinPadWidget(
                  pin: currentPin,
                  onPinChanged: (val) {
                    setState(() {
                      currentPin = val;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap digit 1, 2, 3
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      expect(currentPin, equals('1'));

      await tester.tap(find.text('2'));
      await tester.pumpAndSettle();
      expect(currentPin, equals('12'));

      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      expect(currentPin, equals('123'));

      // Tap backspace
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pumpAndSettle();
      expect(currentPin, equals('12'));
    });

    testWidgets('PatternLockWidget centers its board horizontally in parent', (tester) async {
      tester.view.physicalSize = const Size(500, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatternLockWidget(
              onPatternComplete: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gridFinder = find.bySemanticsLabel('Pattern lock grid. Touch and drag across dots to enter pattern.');
      expect(gridFinder, findsOneWidget);
      final center = tester.getCenter(gridFinder);
      expect(center.dx, equals(250.0));
    });

    testWidgets('VaultUnlockScreen pattern unlock layout is horizontally centered', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.privacynotes.app/security'),
        (call) async => null,
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('com.privacynotes.app/security'),
          null,
        );
      });

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeNotifier = _FakeVaultNotifier(
        const VaultState(
          hasVault: true,
          isUnlocked: false,
          credentialType: CredentialType.pattern,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultProvider.overrideWith((ref) => fakeNotifier),
          ],
          child: const MaterialApp(
            home: VaultUnlockScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Screen width is 400.0, so the center line is exactly dx = 200.0
      const expectedCenterX = 200.0;

      final lockIconFinder = find.byIcon(Icons.lock_rounded);
      expect(lockIconFinder, findsOneWidget);
      expect(tester.getCenter(lockIconFinder).dx, equals(expectedCenterX));

      final titleFinder = find.text('Draw your pattern');
      expect(titleFinder, findsOneWidget);
      expect(tester.getCenter(titleFinder).dx, equals(expectedCenterX));

      final patternFinder = find.byType(PatternLockWidget);
      expect(patternFinder, findsOneWidget);
      expect(tester.getCenter(patternFinder).dx, equals(expectedCenterX));

      final resetBtnFinder = find.text('Forgot secret? Reset locked notes');
      expect(resetBtnFinder, findsOneWidget);
      expect(tester.getCenter(resetBtnFinder).dx, equals(expectedCenterX));
    });

    testWidgets('VaultUnlockScreen PIN unlock layout is horizontally centered', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.privacynotes.app/security'),
        (call) async => null,
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('com.privacynotes.app/security'),
          null,
        );
      });

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeNotifier = _FakeVaultNotifier(
        const VaultState(
          hasVault: true,
          isUnlocked: false,
          credentialType: CredentialType.pin,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            vaultProvider.overrideWith((ref) => fakeNotifier),
          ],
          child: const MaterialApp(
            home: VaultUnlockScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      const expectedCenterX = 200.0;

      final lockIconFinder = find.byIcon(Icons.lock_rounded);
      expect(lockIconFinder, findsOneWidget);
      expect(tester.getCenter(lockIconFinder).dx, equals(expectedCenterX));

      final titleFinder = find.text('Enter your PIN');
      expect(titleFinder, findsOneWidget);
      expect(tester.getCenter(titleFinder).dx, equals(expectedCenterX));

      final pinPadFinder = find.byType(PinPadWidget);
      expect(pinPadFinder, findsOneWidget);
      expect(tester.getCenter(pinPadFinder).dx, equals(expectedCenterX));

      final resetBtnFinder = find.text('Forgot secret? Reset locked notes');
      expect(resetBtnFinder, findsOneWidget);
      expect(tester.getCenter(resetBtnFinder).dx, equals(expectedCenterX));
    });

    testWidgets('VaultSetupScreen clears pattern board on step 2 and resets to step 1 on mismatch', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.privacynotes.app/security'),
        (call) async => null,
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('com.privacynotes.app/security'),
          null,
        );
      });

      final fakeNotifier = _FakeVaultNotifier(
        const VaultState(
          hasVault: false,
          isUnlocked: false,
          credentialType: CredentialType.pin,
        ),
      );

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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Switch to Pattern mode
      await tester.tap(find.text('Pattern (min 5)'));
      await tester.pumpAndSettle();

      expect(find.text('Draw your pattern'), findsOneWidget);
      expect(find.byKey(const ValueKey('pattern_setup_1_1')), findsOneWidget);

      // 2. Complete Step 1 with a 5-dot pattern
      PatternLockWidget patternWidget = tester.widget(find.byType(PatternLockWidget));
      patternWidget.onPatternComplete([0, 1, 2, 4, 7]);
      await tester.pumpAndSettle();

      // 3. Verify Step 2 is shown and pattern board has a new key (fresh clean board)
      expect(find.text('Confirm your pattern'), findsOneWidget);
      expect(find.byKey(const ValueKey('pattern_setup_2_2')), findsOneWidget);

      // 4. Input mismatching pattern in Step 2
      patternWidget = tester.widget(find.byType(PatternLockWidget));
      patternWidget.onPatternComplete([0, 1, 2, 5, 8]);
      await tester.pump();

      // Error message shown immediately and error state active
      expect(find.text('Patterns do not match. Please try again.'), findsOneWidget);

      // 5. Advance 700ms delay: automatically resets to Step 1 with clean board
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pumpAndSettle();

      expect(find.text('Draw your pattern'), findsOneWidget);
      expect(find.text('Patterns do not match. Please try again.'), findsOneWidget);
      expect(find.byKey(const ValueKey('pattern_setup_1_3')), findsOneWidget);
    });
  });
}

class _FakeVaultNotifier extends ChangeNotifier implements VaultNotifier {
  final VaultState _testState;
  _FakeVaultNotifier(this._testState);

  @override
  VaultState get state => _testState;

  @override
  bool get hasVault => _testState.hasVault;

  @override
  bool get isUnlocked => _testState.isUnlocked;

  @override
  CredentialType get credentialType => _testState.credentialType;

  @override
  Uint8List? get vaultKey => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
