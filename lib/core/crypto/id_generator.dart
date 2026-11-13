import 'dart:math';

/// Utility to generate RFC 4122 version 4 UUIDs using Dart's cryptographically
/// secure random number generator without requiring any external dependencies.
abstract final class IdGenerator {
  static final Random _secureRandom = Random.secure();

  /// Generates a 36-character standard UUID v4 string.
  /// Format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx where y is [8, 9, a, or b].
  static String generateUuidV4() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));

    // Set version 4: bits 12-15 of time_hi_and_version to 0100
    bytes[6] = (bytes[6] & 0x0f) | 0x40;

    // Set variant 1 (RFC 4122): bits 6-7 of clock_seq_hi_and_reserved to 10
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }
}
