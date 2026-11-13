import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaflock/core/crypto/recovery_key_service.dart';
import 'package:leaflock/features/backup/domain/backup_manifest.dart';
import 'package:leaflock/features/backup/services/backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Backup Cryptography & Wire Format Security Tests (B1, B3, B5, C, E)', () {
    late String rootKey;
    late Uint8List backupSubkey;
    late BackupManifest sampleManifest;
    late Uint8List manifestBytes;

    setUp(() async {
      rootKey = RecoveryKeyService.generateKey();
      final rootBytes = RecoveryKeyService.decodeKey(rootKey);
      backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootBytes);

      sampleManifest = BackupManifest(
        schemaVersion: 1,
        appVersion: '1.0.0',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        folders: [
          {'id': 'f1', 'name': 'Work', 'color': 12345, 'created_at': 1000, 'updated_at': 1000},
        ],
        notes: [
          {
            'id': 'n1',
            'title': 'Test Title',
            'body': 'Test Body Content',
            'checklist_json': null,
            'is_checklist_mode': 0,
            'folder_id': 'f1',
            'color_label': 0,
            'is_pinned': 0,
            'is_archived': 0,
            'is_locked': 0,
            'trashed_at': null,
            'encrypted_payload': null,
            'payload_iv': null,
            'payload_tag': null,
            'payload_format_version': 1,
            'created_at': 1000,
            'updated_at': 1000,
            'word_count': 3,
          },
        ],
        vaultMetadata: null,
        settings: {'theme_mode': 'dark'},
      );

      manifestBytes = Uint8List.fromList(utf8.encode(sampleManifest.toJsonString()));
    });

    test('B3/B4: Round-trip encryption and decryption with paper recovery key', () async {
      final containerBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      // Verify header structure (33 bytes)
      expect(containerBytes.length, greaterThan(33 + 16));
      expect(containerBytes.sublist(0, 4), equals(BackupService.magicBytes));
      expect(containerBytes[4], equals(BackupService.currentFormatVersion));

      // Decrypt container
      final decryptedManifest = await BackupService.decryptContainerToManifest(
        containerBytes: containerBytes,
        recoveryKeyString: rootKey,
      );

      expect(decryptedManifest.folders.length, equals(1));
      expect(decryptedManifest.folders.first['id'], equals('f1'));
      expect(decryptedManifest.notes.length, equals(1));
      expect(decryptedManifest.notes.first['title'], equals('Test Title'));
      expect(decryptedManifest.settings['theme_mode'], equals('dark'));
    });

    test('E: Wrong recovery key throws BackupSecurityException with friendly text', () async {
      final containerBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      // Generate a completely different valid recovery key
      final wrongKey = RecoveryKeyService.generateKey();

      expect(
        () async => await BackupService.decryptContainerToManifest(
          containerBytes: containerBytes,
          recoveryKeyString: wrongKey,
        ),
        throwsA(
          isA<BackupSecurityException>().having(
            (e) => e.message,
            'message',
            equals('Wrong recovery key or damaged file.'),
          ),
        ),
      );
    });

    test('B3/B5: Header tampering (magic bytes) throws BackupSecurityException', () async {
      final containerBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      // Tamper magic bytes
      final tampered = Uint8List.fromList(containerBytes);
      tampered[0] = 0x58; // 'X' instead of 'L'

      expect(
        () async => await BackupService.decryptContainerToManifest(
          containerBytes: tampered,
          recoveryKeyString: rootKey,
        ),
        throwsA(isA<BackupSecurityException>()),
      );
    });

    test('B3/B5: Newer format version throws BackupUnsupportedVersionException', () async {
      final containerBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      // Tamper version byte to version 0x02
      final tampered = Uint8List.fromList(containerBytes);
      tampered[4] = 0x02;

      expect(
        () async => await BackupService.decryptContainerToManifest(
          containerBytes: tampered,
          recoveryKeyString: rootKey,
        ),
        throwsA(isA<BackupUnsupportedVersionException>()),
      );
    });

    test('B3/B5: AAD tampering (salt or nonce) triggers GCM authentication failure', () async {
      final containerBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      // Tamper byte inside salt (offset 5..20)
      final tamperedSalt = Uint8List.fromList(containerBytes);
      tamperedSalt[10] ^= 0xFF;

      expect(
        () async => await BackupService.decryptContainerToManifest(
          containerBytes: tamperedSalt,
          recoveryKeyString: rootKey,
        ),
        throwsA(isA<BackupSecurityException>()),
      );

      // Tamper byte inside nonce (offset 21..32)
      final tamperedNonce = Uint8List.fromList(containerBytes);
      tamperedNonce[25] ^= 0xFF;

      expect(
        () async => await BackupService.decryptContainerToManifest(
          containerBytes: tamperedNonce,
          recoveryKeyString: rootKey,
        ),
        throwsA(isA<BackupSecurityException>()),
      );
    });

    test('B3/B5: Ciphertext tampering triggers GCM authentication failure', () async {
      final containerBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      final tamperedCiphertext = Uint8List.fromList(containerBytes);
      // Flip bit in the ciphertext payload
      tamperedCiphertext[40] ^= 0x01;

      expect(
        () async => await BackupService.decryptContainerToManifest(
          containerBytes: tamperedCiphertext,
          recoveryKeyString: rootKey,
        ),
        throwsA(isA<BackupSecurityException>()),
      );
    });

    test('B3/B5: Tag tampering triggers GCM authentication failure', () async {
      final containerBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      final tamperedTag = Uint8List.fromList(containerBytes);
      // Flip bit in the trailing 16-byte MAC tag
      tamperedTag[tamperedTag.length - 1] ^= 0x01;

      expect(
        () async => await BackupService.decryptContainerToManifest(
          containerBytes: tamperedTag,
          recoveryKeyString: rootKey,
        ),
        throwsA(isA<BackupSecurityException>()),
      );
    });

    test('B5: Truncated file throws BackupSecurityException', () async {
      final containerBytes = await BackupService.encryptManifestToBytes(
        manifestBytes: manifestBytes,
        backupSubkey: backupSubkey,
      );

      // Truncate to less than header + tag
      final truncated = containerBytes.sublist(0, 30);

      expect(
        () async => await BackupService.decryptContainerToManifest(
          containerBytes: truncated,
          recoveryKeyString: rootKey,
        ),
        throwsA(isA<BackupSecurityException>()),
      );
    });

    test('C: File over 64 MB limit throws BackupOversizeException', () async {
      // 64 MB + 1 byte
      final oversizedBytes = Uint8List((64 * 1024 * 1024) + 1);
      // Fill header with magic bytes
      oversizedBytes.setRange(0, 4, BackupService.magicBytes);

      expect(
        () async => await BackupService.decryptContainerToManifest(
          containerBytes: oversizedBytes,
          recoveryKeyString: rootKey,
        ),
        throwsA(isA<BackupOversizeException>()),
      );
    });

    test('C: Decompression bomb (> 64 MB decompressed) is safely aborted', () async {
      // Create a payload that compresses to a small size but decompresses to 65 MB
      // (65 MB of repeated zeroes compresses to ~64 KB with gzip)
      final sixtyFiveMbZeroes = Uint8List(65 * 1024 * 1024);
      final gzippedBomb = Uint8List.fromList(gzip.encode(sixtyFiveMbZeroes));

      expect(gzippedBomb.length, lessThan(200 * 1024)); // Verify it compressed to < 200 KB

      // Encrypt the bomb payload
      final salt = Uint8List(16);
      final nonce = Uint8List(12);
      final fileKeyBytes = await RecoveryKeyService.deriveBackupFileKey(
        backupSubkey: backupSubkey,
        fileSalt: salt,
      );

      final header = Uint8List(33);
      header.setRange(0, 4, BackupService.magicBytes);
      header[4] = BackupService.currentFormatVersion;
      header.setRange(5, 21, salt);
      header.setRange(21, 33, nonce);

      final aesGcm = AesGcm.with256bits();
      final box = await aesGcm.encrypt(
        gzippedBomb,
        secretKey: SecretKey(fileKeyBytes),
        nonce: nonce,
        aad: header,
      );

      final bombContainer = Uint8List(33 + box.cipherText.length + box.mac.bytes.length);
      bombContainer.setRange(0, 33, header);
      bombContainer.setRange(33, 33 + box.cipherText.length, box.cipherText);
      bombContainer.setRange(33 + box.cipherText.length, bombContainer.length, box.mac.bytes);

      // Verification should abort with BackupDecompressionBombException without running out of memory
      expect(
        () async => await BackupService.decryptContainerToManifest(
          containerBytes: bombContainer,
          recoveryKeyString: rootKey,
        ),
        throwsA(isA<BackupDecompressionBombException>()),
      );
    });

    test('C: Custom decompression sink aborts early the moment cap is exceeded without decompressing whole bomb', () {
      // 100 MB of zeroes compresses to ~100 KB
      final oneHundredMbZeroes = Uint8List(100 * 1024 * 1024);
      final gzipped = gzip.encode(oneHundredMbZeroes);

      const cap = 2 * 1024 * 1024; // 2 MB cap for targeted early-abort measurement
      try {
        BackupService.safeGzipDecodeForTesting(gzipped, cap);
        fail('Should have thrown BackupDecompressionBombException');
      } on BackupDecompressionBombException catch (e) {
        // Assert that decompression aborted immediately once cap was passed,
        // producing only about the cap (e.g. within 128 KB buffer size), NOT 100 MB!
        expect(e.bytesDecompressed, greaterThan(cap));
        expect(
          e.bytesDecompressed,
          lessThan(cap + 128 * 1024),
          reason: 'Decompression must abort early as soon as cap is exceeded, produced: ${e.bytesDecompressed}',
        );
      }

      // Also verify on full 64 MB cap
      const fullCap = 64 * 1024 * 1024;
      try {
        BackupService.safeGzipDecodeForTesting(gzipped, fullCap);
        fail('Should have thrown BackupDecompressionBombException');
      } on BackupDecompressionBombException catch (e) {
        expect(e.bytesDecompressed, greaterThan(fullCap));
        expect(
          e.bytesDecompressed,
          lessThan(fullCap + 128 * 1024),
          reason: 'Must abort immediately after exceeding 64 MB, not decompressing full 100 MB',
        );
      }
    });
  });
}
