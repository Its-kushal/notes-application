import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

abstract class KdfService {
  Future<Uint8List> deriveKey({
    required String secret,
    required Uint8List salt,
    required int iterations,
    int keyLength = 32,
  });
}

/// Production implementation executing PBKDF2-HMAC-SHA256 natively in Kotlin via MethodChannel.
class NativeKdfService implements KdfService {
  static const MethodChannel _channel = MethodChannel('com.privacynotes.app/security');

  @override
  Future<Uint8List> deriveKey({
    required String secret,
    required Uint8List salt,
    required int iterations,
    int keyLength = 32,
  }) async {
    final result = await _channel.invokeMethod<Uint8List>('pbkdf2', {
      'secret': secret,
      'salt': salt,
      'iterations': iterations,
      'keyLengthBits': keyLength * 8,
    });
    if (result == null) {
      throw StateError('Native PBKDF2 derivation failed to return a key.');
    }
    return result;
  }
}

/// Fake implementation for fast host unit/widget tests without native MethodChannel.
class FakeKdfService implements KdfService {
  final int testIterations;

  const FakeKdfService({this.testIterations = 1});

  @override
  Future<Uint8List> deriveKey({
    required String secret,
    required Uint8List salt,
    required int iterations,
    int keyLength = 32,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: testIterations,
      bits: keyLength * 8,
    );
    final secretKey = SecretKey(secret.codeUnits);
    final derived = await pbkdf2.deriveKey(secretKey: secretKey, nonce: salt);
    final bytes = await derived.extractBytes();
    return Uint8List.fromList(bytes);
  }
}
