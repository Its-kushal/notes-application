import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

abstract class RecoveryKeyException implements Exception {
  String get message;
}

class RecoveryKeyFormatException implements RecoveryKeyException {
  @override
  final String message;
  const RecoveryKeyFormatException([this.message = 'Invalid recovery key format.']);
  @override
  String toString() => message;
}

class RecoveryKeyChecksumException implements RecoveryKeyException {
  @override
  final String message;
  const RecoveryKeyChecksumException([
    this.message = 'Recovery key checksum mismatch. Check for typing mistakes.',
  ]);
  @override
  String toString() => message;
}

class RecoveryKeyAuthException implements RecoveryKeyException {
  @override
  final String message;
  const RecoveryKeyAuthException([this.message = 'Incorrect recovery key.']);
  @override
  String toString() => message;
}

/// Service managing the recovery key format, Crockford Base32 encoding,
/// typo-detecting checksum, and HKDF-SHA256 key derivation.
class RecoveryKeyService {
  /// Douglas Crockford's Base32 alphabet (32 symbols).
  /// Excludes I, L, O (mapped to 1, 1, 0) and U.
  static const String alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static const int payloadChars = 26;
  static const int checksumChars = 2;
  static const int totalChars = payloadChars + checksumChars; // 28
  static const int checksumModulus = 1021; // Prime < 1024 (32^2)

  static final Map<String, int> _symbolMap = {
    for (int i = 0; i < alphabet.length; i++) alphabet[i]: i,
  };

  /// Normalizes user input:
  /// - Strips whitespace, dashes, tabs, and newlines
  /// - Case-insensitive (uppercases)
  /// - Maps 'O' -> '0'
  /// - Maps 'I' -> '1'
  /// - Maps 'L' -> '1'
  static String normalize(String input) {
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final char = input[i].toUpperCase();
      if (char == '-' || char == ' ' || char == '\t' || char == '\n' || char == '\r') {
        continue;
      }
      if (char == 'O') {
        buffer.write('0');
      } else if (char == 'I' || char == 'L') {
        buffer.write('1');
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  /// Computes a weighted sum checksum modulo 1021 over the 26 base-32 payload digits.
  /// Provably detects 100% of single-character substitutions and 100% of adjacent transpositions.
  static int computeChecksum(List<int> digits) {
    int sum = 0;
    for (int i = 0; i < digits.length; i++) {
      sum += digits[i] * (i + 1);
    }
    return sum % checksumModulus;
  }

  /// Formats a 28-character raw key string into 7 groups of 4 separated by dashes.
  /// e.g. "XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX"
  static String format(String raw28Chars) {
    if (raw28Chars.length != totalChars) {
      return raw28Chars;
    }
    final groups = <String>[];
    for (int i = 0; i < totalChars; i += 4) {
      groups.add(raw28Chars.substring(i, i + 4));
    }
    return groups.join('-');
  }

  /// Encodes 16 raw bytes (128 bits) into a 28-character formatted Crockford Base32 key with checksum.
  static String encodeBytes(Uint8List rawBytes) {
    if (rawBytes.length != 16) {
      throw ArgumentError('Raw recovery key bytes must be exactly 16 bytes (128 bits).');
    }

    BigInt val = BigInt.zero;
    for (final b in rawBytes) {
      val = (val << 8) | BigInt.from(b);
    }

    final digits = List<int>.filled(payloadChars, 0);
    for (int i = 0; i < payloadChars; i++) {
      final shift = 125 - (5 * i);
      digits[i] = ((val >> shift) & BigInt.from(0x1F)).toInt();
    }

    final checksum = computeChecksum(digits);
    final checkDigit0 = checksum ~/ 32;
    final checkDigit1 = checksum % 32;

    final chars = StringBuffer();
    for (final d in digits) {
      chars.write(alphabet[d]);
    }
    chars.write(alphabet[checkDigit0]);
    chars.write(alphabet[checkDigit1]);

    return format(chars.toString());
  }

  /// Generates a fresh 128-bit recovery key from a secure random source.
  static String generateKey({Random? random}) {
    final rng = random ?? Random.secure();
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return encodeBytes(bytes);
  }

  /// Decodes and validates a recovery key string.
  /// Throws [RecoveryKeyFormatException] if length or characters are invalid.
  /// Throws [RecoveryKeyChecksumException] if checksum does not match.
  static Uint8List decodeKey(String input) {
    final normalized = normalize(input);
    if (normalized.length != totalChars) {
      throw RecoveryKeyFormatException(
        'Recovery key must be 28 characters (got ${normalized.length}).',
      );
    }

    final digits = <int>[];
    for (int i = 0; i < payloadChars; i++) {
      final char = normalized[i];
      final val = _symbolMap[char];
      if (val == null) {
        throw RecoveryKeyFormatException('Invalid character in recovery key: $char');
      }
      digits.add(val);
    }

    final checkChar0 = normalized[payloadChars];
    final checkChar1 = normalized[payloadChars + 1];
    final val0 = _symbolMap[checkChar0];
    final val1 = _symbolMap[checkChar1];
    if (val0 == null || val1 == null) {
      throw const RecoveryKeyFormatException('Invalid character in recovery key checksum.');
    }

    final expectedChecksum = computeChecksum(digits);
    final actualChecksum = (val0 * 32) + val1;
    if (expectedChecksum != actualChecksum) {
      throw const RecoveryKeyChecksumException(
        'Recovery key checksum mismatch. Check for typing mistakes.',
      );
    }

    // 128-bit payload encoded in 130 bits (26 × 5). Top 2 bits must be zero,
    // so the first base-32 digit must be 0–7 (binary 00xxx).
    if (digits[0] > 7) {
      throw const RecoveryKeyFormatException(
        'Invalid recovery key: value exceeds 128-bit range.',
      );
    }

    // Reconstruct 128-bit BigInt
    BigInt val = BigInt.zero;
    for (int i = 0; i < payloadChars; i++) {
      val = (val << 5) | BigInt.from(digits[i]);
    }

    final bytes = Uint8List(16);
    for (int i = 15; i >= 0; i--) {
      bytes[i] = (val & BigInt.from(0xFF)).toInt();
      val = val >> 8;
    }
    return bytes;
  }

  /// Derives a wrapping key using HKDF-SHA256 (RFC 5869) with a caller-supplied info string (R9).
  static Future<Uint8List> deriveWrappingKey({
    required Uint8List recoveryKeyBytes,
    required Uint8List salt,
    required String infoString,
    int keyLength = 32,
  }) async {
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: keyLength,
    );
    final secretKey = SecretKey(recoveryKeyBytes);
    final derived = await hkdf.deriveKey(
      secretKey: secretKey,
      nonce: salt,
      info: utf8.encode(infoString),
    );
    final keyBytes = await derived.extractBytes();
    return Uint8List.fromList(keyBytes);
  }

  /// Wraps the 256-bit vault key using AES-256-GCM and HKDF-derived wrapping key (R3).
  static Future<SecretBox> wrapVaultKey({
    required Uint8List vaultKey,
    required Uint8List recoveryKeyBytes,
    required Uint8List salt,
    required Uint8List iv,
    String infoString = 'pn-vault-recovery-v1',
    String aadString = 'vault-recovery:v1',
  }) async {
    final wrappingKey = await deriveWrappingKey(
      recoveryKeyBytes: recoveryKeyBytes,
      salt: salt,
      infoString: infoString,
    );
    final aesGcm = AesGcm.with256bits();
    return aesGcm.encrypt(
      vaultKey,
      secretKey: SecretKey(wrappingKey),
      nonce: iv,
      aad: utf8.encode(aadString),
    );
  }

  /// Unwraps the 256-bit vault key using AES-256-GCM and HKDF-derived wrapping key (R3, R6).
  /// Throws [RecoveryKeyAuthException] if authentication tag verification fails.
  static Future<Uint8List> unwrapVaultKey({
    required Uint8List wrappedVaultKey,
    required Uint8List iv,
    required Uint8List tag,
    required Uint8List recoveryKeyBytes,
    required Uint8List salt,
    String infoString = 'pn-vault-recovery-v1',
    String aadString = 'vault-recovery:v1',
  }) async {
    final wrappingKey = await deriveWrappingKey(
      recoveryKeyBytes: recoveryKeyBytes,
      salt: salt,
      infoString: infoString,
    );
    final aesGcm = AesGcm.with256bits();
    try {
      final decrypted = await aesGcm.decrypt(
        SecretBox(
          wrappedVaultKey,
          nonce: iv,
          mac: Mac(tag),
        ),
        secretKey: SecretKey(wrappingKey),
        aad: utf8.encode(aadString),
      );
      return Uint8List.fromList(decrypted);
    } on SecretBoxAuthenticationError {
      throw const RecoveryKeyAuthException('Incorrect recovery key.');
    }
  }
}
