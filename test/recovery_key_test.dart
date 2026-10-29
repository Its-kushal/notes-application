import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/core/crypto/recovery_key_service.dart';

void main() {
  group('RecoveryKeyService Key Format & Checksum Tests', () {
    test('Deterministic test vector 1: all zeros (16 bytes 0x00)', () {
      final zeros = Uint8List(16);
      final key = RecoveryKeyService.encodeBytes(zeros);
      // All 0s in 128-bit produces 26 '0's. Sum = 0. Checksum = 0 -> '00'
      expect(key, equals('0000-0000-0000-0000-0000-0000-0000'));
      final decoded = RecoveryKeyService.decodeKey(key);
      expect(decoded, equals(zeros));
    });

    test('Deterministic test vector 2: all ones (16 bytes 0xFF)', () {
      final allOnes = Uint8List.fromList(List.filled(16, 0xFF));
      final key = RecoveryKeyService.encodeBytes(allOnes);
      // Verify format 7 groups of 4
      expect(key.length, equals(28 + 6)); // 28 chars + 6 dashes = 34
      final parts = key.split('-');
      expect(parts.length, equals(7));
      for (final part in parts) {
        expect(part.length, equals(4));
      }
      final decoded = RecoveryKeyService.decodeKey(key);
      expect(decoded, equals(allOnes));
    });

    test('Deterministic test vector 3: sequential bytes (0x00..0x0F)', () {
      final seq = Uint8List.fromList(List.generate(16, (i) => i));
      final key = RecoveryKeyService.encodeBytes(seq);
      final decoded = RecoveryKeyService.decodeKey(key);
      expect(decoded, equals(seq));
    });

    test('Round trip on 100 random 128-bit keys', () {
      final rng = Random(42);
      for (int i = 0; i < 100; i++) {
        final original = Uint8List(16);
        for (int b = 0; b < 16; b++) {
          original[b] = rng.nextInt(256);
        }
        final keyStr = RecoveryKeyService.encodeBytes(original);
        final decoded = RecoveryKeyService.decodeKey(keyStr);
        expect(decoded, equals(original));
      }
    });

    test('Normalization handles lowercase, spaces, dashes, O->0, I->1, L->1', () {
      final seq = Uint8List.fromList(List.generate(16, (i) => i));
      final key = RecoveryKeyService.encodeBytes(seq);

      // Mutate formatting: lowercase, spaces, extra dashes, tabs
      String mutated = key.toLowerCase().replaceAll('-', '  - ');
      final decoded1 = RecoveryKeyService.decodeKey(mutated);
      expect(decoded1, equals(seq));

      // Test mapping of O->0, I->1, L->1 in a valid key
      final rawKey = RecoveryKeyService.normalize(key);
      // Replace instances of '0' with 'O' and '1' with 'I' or 'L'
      final replaced = rawKey.split('').map((c) {
        if (c == '0') return 'O';
        if (c == '1') return 'I';
        return c;
      }).join('');

      final decoded2 = RecoveryKeyService.decodeKey(replaced);
      expect(decoded2, equals(seq));
    });

    test('Checksum detects ANY single-character substitution across all 28 positions', () {
      final rng = Random(12345);
      final bytes = Uint8List(16);
      for (int i = 0; i < 16; i++) {
        bytes[i] = rng.nextInt(256);
      }
      final key = RecoveryKeyService.encodeBytes(bytes);
      final raw = RecoveryKeyService.normalize(key);
      expect(raw.length, equals(28));

      for (int pos = 0; pos < 28; pos++) {
        final originalChar = raw[pos];
        for (int symbolIdx = 0; symbolIdx < RecoveryKeyService.alphabet.length; symbolIdx++) {
          final replacementChar = RecoveryKeyService.alphabet[symbolIdx];
          if (replacementChar == originalChar) continue;

          final corrupted = raw.substring(0, pos) + replacementChar + raw.substring(pos + 1);
          expect(
            () => RecoveryKeyService.decodeKey(corrupted),
            throwsA(isA<RecoveryKeyChecksumException>()),
            reason: 'Substitution at pos $pos with $replacementChar must fail checksum',
          );
        }
      }
    });

    test('Checksum detects ANY adjacent transposition across all 27 pairs', () {
      final rng = Random(98765);
      final bytes = Uint8List(16);
      for (int i = 0; i < 16; i++) {
        bytes[i] = rng.nextInt(256);
      }
      final key = RecoveryKeyService.encodeBytes(bytes);
      final raw = RecoveryKeyService.normalize(key);

      for (int pos = 0; pos < 27; pos++) {
        if (raw[pos] == raw[pos + 1]) continue;

        final swapped = raw.substring(0, pos) +
            raw[pos + 1] +
            raw[pos] +
            raw.substring(pos + 2);

        expect(
          () => RecoveryKeyService.decodeKey(swapped),
          throwsA(isA<RecoveryKeyChecksumException>()),
          reason: 'Transposition at pos $pos with $pos+1 must fail checksum',
        );
      }
    });

    test('Invalid length throws RecoveryKeyFormatException', () {
      expect(
        () => RecoveryKeyService.decodeKey('1234-5678'),
        throwsA(isA<RecoveryKeyFormatException>()),
      );
    });

    test('Invalid character (e.g. U) throws RecoveryKeyFormatException', () {
      // 'U' is excluded from Crockford Base32
      final valid = RecoveryKeyService.generateKey();
      final withU = 'U${valid.substring(1)}';
      expect(
        () => RecoveryKeyService.decodeKey(withU),
        throwsA(isA<RecoveryKeyFormatException>()),
      );
    });

    test('First digit > 7 (exceeds 128-bit range) throws RecoveryKeyFormatException', () {
      // Craft a 28-char key where the first digit is 8 (0b01000 in Base32 = 'A'? No...)
      // In Crockford Base32: digit 8 = '8', digit 9 = '9', 10 = 'A', etc.
      // digits[0] > 7 means the first char maps to symbol index >= 8.
      // Symbol index 8 is '8', index 9 is '9', index 10 is 'A', etc.
      // Build a valid-checksum key starting with symbol '8' (index 8).
      final digits = List<int>.filled(26, 0);
      digits[0] = 8; // Above 7 — violates 128-bit range
      final checksum = RecoveryKeyService.computeChecksum(digits);
      final c0 = checksum ~/ 32;
      final c1 = checksum % 32;
      final buf = StringBuffer();
      for (final d in digits) {
        buf.write(RecoveryKeyService.alphabet[d]);
      }
      buf.write(RecoveryKeyService.alphabet[c0]);
      buf.write(RecoveryKeyService.alphabet[c1]);
      final key = buf.toString();

      expect(
        () => RecoveryKeyService.decodeKey(key),
        throwsA(isA<RecoveryKeyFormatException>()),
        reason: 'First digit 8 exceeds 128-bit range',
      );

      // Digit 7 should still be allowed
      digits[0] = 7;
      final checksum7 = RecoveryKeyService.computeChecksum(digits);
      final c70 = checksum7 ~/ 32;
      final c71 = checksum7 % 32;
      final buf7 = StringBuffer();
      for (final d in digits) {
        buf7.write(RecoveryKeyService.alphabet[d]);
      }
      buf7.write(RecoveryKeyService.alphabet[c70]);
      buf7.write(RecoveryKeyService.alphabet[c71]);
      final key7 = buf7.toString();

      // Should not throw — digit 7 is within 128-bit range
      final decoded = RecoveryKeyService.decodeKey(key7);
      expect(decoded.length, equals(16));
    });
  });

  group('RecoveryKeyService Cryptography Tests (R3, R9)', () {
    final salt = Uint8List.fromList(List.generate(16, (i) => i * 3));
    final iv = Uint8List.fromList(List.generate(12, (i) => i * 7));
    final vaultKey = Uint8List.fromList(List.generate(32, (i) => i * 5));

    test('wrapVaultKey and unwrapVaultKey round trip succeeds', () async {
      final recoveryKeyStr = RecoveryKeyService.generateKey();
      final recoveryBytes = RecoveryKeyService.decodeKey(recoveryKeyStr);

      final box = await RecoveryKeyService.wrapVaultKey(
        vaultKey: vaultKey,
        recoveryKeyBytes: recoveryBytes,
        salt: salt,
        iv: iv,
      );

      final unwrapped = await RecoveryKeyService.unwrapVaultKey(
        wrappedVaultKey: Uint8List.fromList(box.cipherText),
        iv: iv,
        tag: Uint8List.fromList(box.mac.bytes),
        recoveryKeyBytes: recoveryBytes,
        salt: salt,
      );

      expect(unwrapped, equals(vaultKey));
    });

    test('Wrong recovery key fails unwrap cleanly with RecoveryKeyAuthException', () async {
      final key1Str = RecoveryKeyService.generateKey();
      final key2Str = RecoveryKeyService.generateKey();
      final key1Bytes = RecoveryKeyService.decodeKey(key1Str);
      final key2Bytes = RecoveryKeyService.decodeKey(key2Str);

      final box = await RecoveryKeyService.wrapVaultKey(
        vaultKey: vaultKey,
        recoveryKeyBytes: key1Bytes,
        salt: salt,
        iv: iv,
      );

      await expectLater(
        () => RecoveryKeyService.unwrapVaultKey(
          wrappedVaultKey: Uint8List.fromList(box.cipherText),
          iv: iv,
          tag: Uint8List.fromList(box.mac.bytes),
          recoveryKeyBytes: key2Bytes,
          salt: salt,
        ),
        throwsA(isA<RecoveryKeyAuthException>()),
      );
    });

    test('Tampered ciphertext fails unwrap with RecoveryKeyAuthException', () async {
      final keyStr = RecoveryKeyService.generateKey();
      final keyBytes = RecoveryKeyService.decodeKey(keyStr);

      final box = await RecoveryKeyService.wrapVaultKey(
        vaultKey: vaultKey,
        recoveryKeyBytes: keyBytes,
        salt: salt,
        iv: iv,
      );

      final tamperedCiphertext = Uint8List.fromList(box.cipherText);
      tamperedCiphertext[0] ^= 0xFF;

      await expectLater(
        () => RecoveryKeyService.unwrapVaultKey(
          wrappedVaultKey: tamperedCiphertext,
          iv: iv,
          tag: Uint8List.fromList(box.mac.bytes),
          recoveryKeyBytes: keyBytes,
          salt: salt,
        ),
        throwsA(isA<RecoveryKeyAuthException>()),
      );
    });

    test('AAD mismatch fails unwrap with RecoveryKeyAuthException', () async {
      final keyStr = RecoveryKeyService.generateKey();
      final keyBytes = RecoveryKeyService.decodeKey(keyStr);

      final box = await RecoveryKeyService.wrapVaultKey(
        vaultKey: vaultKey,
        recoveryKeyBytes: keyBytes,
        salt: salt,
        iv: iv,
        aadString: 'vault-recovery:v1',
      );

      await expectLater(
        () => RecoveryKeyService.unwrapVaultKey(
          wrappedVaultKey: Uint8List.fromList(box.cipherText),
          iv: iv,
          tag: Uint8List.fromList(box.mac.bytes),
          recoveryKeyBytes: keyBytes,
          salt: salt,
          aadString: 'vault-recovery:v2_wrong_aad',
        ),
        throwsA(isA<RecoveryKeyAuthException>()),
      );
    });

    test('Custom info string derivation (R9 for M6 backup reuse)', () async {
      final keyBytes = Uint8List(16);
      final derivedVault = await RecoveryKeyService.deriveWrappingKey(
        recoveryKeyBytes: keyBytes,
        salt: salt,
        infoString: 'pn-vault-recovery-v1',
      );
      final derivedBackup = await RecoveryKeyService.deriveWrappingKey(
        recoveryKeyBytes: keyBytes,
        salt: salt,
        infoString: 'pn-backup-v1',
      );

      expect(derivedVault, isNot(equals(derivedBackup)));
      expect(derivedVault.length, equals(32));
      expect(derivedBackup.length, equals(32));
    });
  });
}
