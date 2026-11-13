import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:leaflock/core/crypto/kdf_service.dart';
import 'package:leaflock/core/crypto/recovery_key_service.dart';
import 'package:leaflock/core/crypto/vault_service.dart';
import 'package:leaflock/core/database/app_database.dart';
import 'package:leaflock/features/backup/presentation/controllers/backup_provider.dart';
import 'package:leaflock/features/backup/services/backup_service.dart';
import 'package:leaflock/features/locked_notes/presentation/controllers/vault_providers.dart';
import 'package:leaflock/l10n/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockGoRouter extends ChangeNotifier implements GoRouter {
  final List<String> pushedLocations = [];
  final List<dynamic> pushedExtras = [];
  Future<dynamic> Function(String location, Object? extra)? onPush;

  @override
  Future<T?> push<T extends Object?>(String location, {Object? extra}) async {
    pushedLocations.add(location);
    pushedExtras.add(extra);
    if (onPush != null) {
      final res = await onPush!(location, extra);
      return res as T?;
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBackupService implements BackupService {
  bool _hasSubkey = false;

  @override
  Future<bool> hasStoredBackupSubkey() async => _hasSubkey;

  @override
  Future<void> storeBackupSubkey(Uint8List subkey) async {
    _hasSubkey = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeVaultNotifier extends ChangeNotifier implements VaultNotifier {
  @override
  VaultState state = const VaultState(
    hasVault: true,
    hasRecoveryKey: false,
  );

  @override
  bool get hasVault => state.hasVault;
  @override
  bool get hasRecoveryKey => state.hasRecoveryKey;
  @override
  bool get isUnlocked => false;
  @override
  CredentialType get credentialType => CredentialType.pin;
  @override
  Uint8List? get vaultKey => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.leaflock.app/security'),
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
      const MethodChannel('com.leaflock.app/security'),
      null,
    );
  });

  late Directory tempDir;
  late AppDatabase appDb;
  late VaultService vaultService;
  late BackupService backupService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('leaf_lock_key_states_');
    appDb = AppDatabase(
      customFactory: databaseFactoryFfi,
      customPath: '${tempDir.path}/test_app.db',
    );
    await appDb.initialize(overridePassword: 'test_password');
    vaultService = VaultService(
      appDatabase: appDb,
      kdfService: const FakeKdfService(testIterations: 1),
    );
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

  group('A: Key States & Single Root Key Architecture Tests', () {
    test('Case 1: No vault and no backup subkey: create root key and store backup subkey', () async {
      // 1. Initial state: no vault, no subkey
      expect(await vaultService.getVaultMetadata(), isNull);
      expect(await backupService.hasStoredBackupSubkey(), isFalse);

      // 2. User generates new root key during backup setup
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final derivedSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);
      await backupService.storeBackupSubkey(derivedSubkey);

      // 3. Subkey is stored in app_settings; root key itself is NOT stored
      expect(await backupService.hasStoredBackupSubkey(), isTrue);
      final storedSubkey = await backupService.getStoredBackupSubkey();
      expect(storedSubkey, isNotNull);
      expect(RecoveryKeyService.constantTimeEquals(storedSubkey!, derivedSubkey), isTrue);

      final settings = await appDb.database.query('app_settings');
      for (final row in settings) {
        expect((row['value'] as String).contains(rootKey), isFalse);
      }
    });

    test('Case 2: Vault with recovery wrap exists, no backup subkey (user phone state): link existing key', () async {
      // 1. User previously created vault with secret and recovery wrap
      final existingPaperKey = RecoveryKeyService.generateKey();
      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        recoveryKeyString: existingPaperKey,
        iterations: 1,
      );

      // Verify vault has recovery wrap, but simulate missing backup subkey (as currently on user device)
      await appDb.database.delete('app_settings', where: 'key = ?', whereArgs: ['backup_subkey']);
      expect(await vaultService.hasRecoveryKey(), isTrue);
      expect(await backupService.hasStoredBackupSubkey(), isFalse);

      // 2. User types wrong paper key -> verification fails, no subkey stored
      final wrongKey = RecoveryKeyService.generateKey();
      final wrongMatch = await vaultService.verifyRecoveryKeyAgainstVault(wrongKey);
      expect(wrongMatch, isFalse);
      expect(await backupService.hasStoredBackupSubkey(), isFalse);

      // 3. User types correct existing paper key -> verified by unwrapping vault wrap
      final correctMatch = await vaultService.verifyRecoveryKeyAgainstVault(existingPaperKey);
      expect(correctMatch, isTrue);

      // Derive and store subkey from verified paper key (NEVER generates a new root key!)
      final existingBytes = RecoveryKeyService.decodeKey(existingPaperKey);
      final derivedSubkey = await RecoveryKeyService.deriveBackupSubkey(existingBytes);
      await backupService.storeBackupSubkey(derivedSubkey);

      expect(await backupService.hasStoredBackupSubkey(), isTrue);

      // 4. Verify subkey encrypts a backup that can be restored with existingPaperKey
      final backupBytes = await backupService.createBackupBytes();
      final decrypted = await BackupService.decryptContainerToManifest(
        containerBytes: backupBytes,
        recoveryKeyString: existingPaperKey,
      );
      expect(decrypted.schemaVersion, equals(1));
    });

    test('Case 3: Vault exists without recovery wrap: createRecoveryKey stores backup subkey', () async {
      // 1. Vault set up without recovery key
      await vaultService.setupVault(
        secret: '123456',
        credentialType: CredentialType.pin,
        recoveryKeyString: null,
        iterations: 1,
      );
      expect(await vaultService.hasRecoveryKey(), isFalse);
      expect(await backupService.hasStoredBackupSubkey(), isFalse);

      // 2. User creates recovery key
      final newRootKey = RecoveryKeyService.generateKey();
      await vaultService.createOrUpdateRecoveryKey(
        currentSecret: '123456',
        recoveryKeyString: newRootKey,
      );

      // 3. Vault now has recovery key AND backup subkey is stored!
      expect(await vaultService.hasRecoveryKey(), isTrue);
      expect(await backupService.hasStoredBackupSubkey(), isTrue);

      final rootBytes = RecoveryKeyService.decodeKey(newRootKey);
      final expectedSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);
      final storedSubkey = await backupService.getStoredBackupSubkey();
      expect(RecoveryKeyService.constantTimeEquals(storedSubkey!, expectedSubkey), isTrue);
    });

    test('Case 4: Backup subkey exists; later vault setup verifies paper key and reuses single root key', () async {
      // 1. User created backup first
      final rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);
      await backupService.storeBackupSubkey(backupSubkey);

      expect(await vaultService.hasBackupSubkey(), isTrue);

      // 2. Later, user sets up a vault. Typing wrong key is rejected by constant-time subkey compare
      final wrongKey = RecoveryKeyService.generateKey();
      final wrongMatch = await vaultService.verifyRecoveryKeyAgainstBackupSubkey(wrongKey);
      expect(wrongMatch, isFalse);

      // 3. Typing correct existing key is accepted
      final correctMatch = await vaultService.verifyRecoveryKeyAgainstBackupSubkey(rootKey);
      expect(correctMatch, isTrue);

      // 4. Setup vault with the verified paper key
      await vaultService.setupVault(
        secret: '654321',
        credentialType: CredentialType.pin,
        recoveryKeyString: rootKey,
        iterations: 1,
      );

      // Verify single root key governs both vault wrap and backup subkey!
      expect(await vaultService.hasRecoveryKey(), isTrue);
      expect(await vaultService.verifyRecoveryKeyAgainstVault(rootKey), isTrue);
    });

    test('Rotation: Regenerating recovery key updates backup subkey; older backups need old key', () async {
      // 1. Initial vault and backup subkey with Key 1
      final key1 = RecoveryKeyService.generateKey();
      await vaultService.setupVault(
        secret: '111111',
        credentialType: CredentialType.pin,
        recoveryKeyString: key1,
        iterations: 1,
      );
      final key1Bytes = RecoveryKeyService.decodeKey(key1);
      final subkey1 = await RecoveryKeyService.deriveBackupSubkey(key1Bytes);

      // Create Backup 1 using Key 1
      final backup1Bytes = await backupService.createBackupBytes();

      // 2. User regenerates recovery key to Key 2
      final key2 = RecoveryKeyService.generateKey();
      await vaultService.createOrUpdateRecoveryKey(
        currentSecret: '111111',
        recoveryKeyString: key2,
      );

      // 3. Stored backup subkey is updated to Key 2 subkey
      final key2Bytes = RecoveryKeyService.decodeKey(key2);
      final subkey2 = await RecoveryKeyService.deriveBackupSubkey(key2Bytes);
      final currentStoredSubkey = await backupService.getStoredBackupSubkey();

      expect(RecoveryKeyService.constantTimeEquals(currentStoredSubkey!, subkey2), isTrue);
      expect(RecoveryKeyService.constantTimeEquals(currentStoredSubkey, subkey1), isFalse);

      // 4. Older Backup 1 CANNOT be decrypted with new Key 2
      expect(
        () async => await BackupService.decryptContainerToManifest(
          containerBytes: backup1Bytes,
          recoveryKeyString: key2,
        ),
        throwsA(isA<BackupSecurityException>()),
      );

      // 5. Older Backup 1 CAN still be decrypted with OLD Key 1
      final decryptedBackup1 = await BackupService.decryptContainerToManifest(
        containerBytes: backup1Bytes,
        recoveryKeyString: key1,
      );
      expect(decryptedBackup1.schemaVersion, equals(1));

      // 6. Fresh Backup 2 is encrypted with Key 2
      final backup2Bytes = await backupService.createBackupBytes();
      final decryptedBackup2 = await BackupService.decryptContainerToManifest(
        containerBytes: backup2Bytes,
        recoveryKeyString: key2,
      );
      expect(decryptedBackup2.schemaVersion, equals(1));
    });

    testWidgets('Case 3 Widget Test: ensureBackupSubkey prompts to create recovery key, navigates to /vault/recovery-key, and continues backup', (tester) async {
      bool backupCompleted = false;

      final fakeBackup = FakeBackupService();
      final fakeVault = FakeVaultNotifier();

      final mockRouter = MockGoRouter();
      mockRouter.onPush = (location, extra) async {
        if (location == '/vault/recovery-key') {
          await fakeBackup.storeBackupSubkey(Uint8List(32));
          return true;
        }
        return false;
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            backupServiceProvider.overrideWithValue(fakeBackup),
            vaultProvider.overrideWith((ref) => fakeVault),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: InheritedGoRouter(
              goRouter: mockRouter,
              child: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => ElevatedButton(
                    onPressed: () async {
                      final success = await ref.read(backupProvider).ensureBackupSubkey(context);
                      if (success) {
                        backupCompleted = true;
                      }
                    },
                    child: const Text('Start Backup'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 'Start Backup'
      await tester.tap(find.text('Start Backup'));
      await tester.pumpAndSettle();

      // Dialog is displayed: "Create recovery key"
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      // Tap 'Continue'
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Proves it navigated to /vault/recovery-key!
      expect(mockRouter.pushedLocations, contains('/vault/recovery-key'));

      // Proves backup continued afterwards!
      expect(backupCompleted, isTrue);
      expect(await fakeBackup.hasStoredBackupSubkey(), isTrue);
    });
  });
}
