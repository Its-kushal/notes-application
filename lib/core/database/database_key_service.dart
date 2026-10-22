import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service responsible for managing the 256-bit SQLCipher database encryption key
/// securely in Android Keystore / FlutterSecureStorage.
class DatabaseKeyService {
  final FlutterSecureStorage _secureStorage;
  static const String _dbKeyStorageKey = 'sqlcipher_db_key_v1';

  DatabaseKeyService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: false,
              ),
            );

  /// Retrieves the existing 256-bit SQLCipher raw key in "x'HEX'" format.
  /// If [createNewIfMissing] is true, generates and stores a new 256-bit cryptographically
  /// secure key.
  /// Throws if Keystore read fails or if key is missing and [createNewIfMissing] is false.
  Future<String> getOrCreateRawDatabaseKey({required bool createNewIfMissing}) async {
    try {
      final existingKeyHex = await _secureStorage.read(key: _dbKeyStorageKey);
      if (existingKeyHex != null && existingKeyHex.length == 64) {
        return "x'$existingKeyHex'";
      }

      if (!createNewIfMissing) {
        throw StateError('Database key missing in hardware Keystore.');
      }

      // Generate a new 256-bit (32-byte) cryptographically secure key
      final secureRandom = Random.secure();
      final keyBytes = List<int>.generate(32, (_) => secureRandom.nextInt(256));
      final hexKey = keyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      await _secureStorage.write(key: _dbKeyStorageKey, value: hexKey);
      return "x'$hexKey'";
    } catch (e) {
      if (!createNewIfMissing) {
        rethrow;
      }
      throw StateError('Failed to access or initialize hardware Keystore key: $e');
    }
  }

  /// Checks if a key already exists in Keystore without generating a new one.
  Future<bool> hasStoredKey() async {
    try {
      final key = await _secureStorage.read(key: _dbKeyStorageKey);
      return key != null && key.length == 64;
    } catch (_) {
      return false;
    }
  }
}
