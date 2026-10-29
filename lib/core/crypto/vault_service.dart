import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../database/app_database.dart';
import 'kdf_service.dart';
import 'recovery_key_service.dart';

class VaultAuthException implements Exception {
  final String message;
  const VaultAuthException([this.message = 'Incorrect secret. Please try again.']);
  @override
  String toString() => message;
}

class VaultPlatformException implements Exception {
  final String message;
  const VaultPlatformException([this.message = 'Native cryptographic service error.']);
  @override
  String toString() => message;
}

class VaultLockoutException implements Exception {
  final int remainingSeconds;
  const VaultLockoutException(this.remainingSeconds);
  @override
  String toString() => 'Too many failed attempts. Try again in $remainingSeconds seconds.';
}

enum CredentialType {
  pin,
  pattern;

  static CredentialType fromString(String val) {
    return val.toLowerCase() == 'pattern' ? CredentialType.pattern : CredentialType.pin;
  }
}

class VaultMetadata {
  final Uint8List salt;
  final String kdfAlgorithm;
  final int kdfIterations;
  final CredentialType credentialType;
  final Uint8List wrappedVaultKey;
  final Uint8List wrappedVaultKeyIv;
  final Uint8List wrappedVaultKeyTag;
  final int version;
  final Uint8List? recoverySalt;
  final Uint8List? recoveryWrappedKey;
  final Uint8List? recoveryIv;
  final Uint8List? recoveryTag;
  final int? recoveryVersion;
  final int createdAt;
  final int updatedAt;

  const VaultMetadata({
    required this.salt,
    required this.kdfAlgorithm,
    required this.kdfIterations,
    required this.credentialType,
    required this.wrappedVaultKey,
    required this.wrappedVaultKeyIv,
    required this.wrappedVaultKeyTag,
    required this.version,
    this.recoverySalt,
    this.recoveryWrappedKey,
    this.recoveryIv,
    this.recoveryTag,
    this.recoveryVersion,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasRecoveryKey => recoveryWrappedKey != null;

  factory VaultMetadata.fromMap(Map<String, dynamic> map) {
    return VaultMetadata(
      salt: map['salt'] as Uint8List,
      kdfAlgorithm: map['kdf_algorithm'] as String,
      kdfIterations: map['kdf_iterations'] as int,
      credentialType: CredentialType.fromString(map['credential_type'] as String? ?? 'pin'),
      wrappedVaultKey: map['wrapped_vault_key'] as Uint8List,
      wrappedVaultKeyIv: map['wrapped_vault_key_iv'] as Uint8List,
      wrappedVaultKeyTag: map['wrapped_vault_key_tag'] as Uint8List,
      version: map['version'] as int? ?? 1,
      recoverySalt: map['recovery_salt'] as Uint8List?,
      recoveryWrappedKey: map['recovery_wrapped_key'] as Uint8List?,
      recoveryIv: map['recovery_iv'] as Uint8List?,
      recoveryTag: map['recovery_tag'] as Uint8List?,
      recoveryVersion: map['recovery_version'] as int?,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
    );
  }
}

/// Represents the status and countdown of a 72-hour delayed reset request (Requirement A2).
class DelayedResetStatus {
  final bool isRequested;
  final DateTime? requestedAt;
  final int remainingSeconds;
  final bool isReady;

  const DelayedResetStatus({
    required this.isRequested,
    this.requestedAt,
    required this.remainingSeconds,
    required this.isReady,
  });
}

/// Service managing the cryptographic vault for locked notes.
///
/// NOTE: Dart's runtime and garbage collector cannot guarantee deterministic
/// zeroing of memory for Uint8List or String variables.
class VaultService {
  static const int standardKdfIterations = 400000;
  static const String standardKdfAlgorithm = 'PBKDF2-HMAC-SHA256';
  static final Uint8List vaultWrappingAad = utf8.encode('vault:v1');

  final AppDatabase _appDatabase;
  final KdfService _kdfService;
  DateTime Function() clock;
  final Future<int> Function()? elapsedRealtimeProvider;

  Uint8List? _vaultKey;

  VaultService({
    required this._appDatabase,
    KdfService? kdfService,
    DateTime Function()? clock,
    this.elapsedRealtimeProvider,
  })  : _kdfService = kdfService ?? NativeKdfService(),
        clock = clock ?? DateTime.now;

  Database get _db => _appDatabase.database;

  bool get isUnlocked => _vaultKey != null;
  Uint8List? get vaultKey => _vaultKey;

  /// Returns true if a vault has been set up.
  Future<bool> hasVault() async {
    final res = await _db.query('vault_metadata', limit: 1);
    return res.isNotEmpty;
  }

  /// Retrieves vault metadata if configured.
  Future<VaultMetadata?> getVaultMetadata() async {
    final res = await _db.query('vault_metadata', where: 'id = 1');
    if (res.isEmpty) return null;
    return VaultMetadata.fromMap(res.first);
  }

  /// Sets up a fresh vault with a random 256-bit vault key.
  /// If [recoveryKeyString] is provided, derives and stores a recovery wrap in the same transaction (R3, R4).
  Future<void> setupVault({
    required String secret,
    required CredentialType credentialType,
    String? recoveryKeyString,
    int iterations = standardKdfIterations,
  }) async {
    final random = Random.secure();
    final vaultKey = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      vaultKey[i] = random.nextInt(256);
    }

    final salt = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      salt[i] = random.nextInt(256);
    }

    final wrappingKeyBytes = await _kdfService.deriveKey(
      secret: secret,
      salt: salt,
      iterations: iterations,
      keyLength: 32,
    );

    final iv = Uint8List(12);
    for (int i = 0; i < 12; i++) {
      iv[i] = random.nextInt(256);
    }

    final aesGcm = AesGcm.with256bits();
    final secretBox = await aesGcm.encrypt(
      vaultKey,
      secretKey: SecretKey(wrappingKeyBytes),
      nonce: iv,
      aad: vaultWrappingAad,
    );

    Uint8List? recoverySalt;
    Uint8List? recoveryIv;
    Uint8List? recoveryCiphertext;
    Uint8List? recoveryTag;

    if (recoveryKeyString != null) {
      final recoveryBytes = RecoveryKeyService.decodeKey(recoveryKeyString);
      recoverySalt = Uint8List(16);
      for (int i = 0; i < 16; i++) {
        recoverySalt[i] = random.nextInt(256);
      }
      recoveryIv = Uint8List(12);
      for (int i = 0; i < 12; i++) {
        recoveryIv[i] = random.nextInt(256);
      }

      final recBox = await RecoveryKeyService.wrapVaultKey(
        vaultKey: vaultKey,
        recoveryKeyBytes: recoveryBytes,
        salt: recoverySalt,
        iv: recoveryIv,
      );
      recoveryCiphertext = Uint8List.fromList(recBox.cipherText);
      recoveryTag = Uint8List.fromList(recBox.mac.bytes);
    }

    final now = clock().millisecondsSinceEpoch;

    await _db.insert(
      'vault_metadata',
      {
        'id': 1,
        'salt': salt,
        'kdf_algorithm': standardKdfAlgorithm,
        'kdf_iterations': iterations,
        'credential_type': credentialType.name,
        'wrapped_vault_key': secretBox.cipherText,
        'wrapped_vault_key_iv': iv,
        'wrapped_vault_key_tag': secretBox.mac.bytes,
        'version': 1,
        'recovery_salt': recoverySalt,
        'recovery_wrapped_key': recoveryCiphertext,
        'recovery_iv': recoveryIv,
        'recovery_tag': recoveryTag,
        'recovery_version': recoveryKeyString != null ? 1 : null,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    _vaultKey = vaultKey;
    await _resetFailedAttempts();
    await _resetFailedRecoveryAttempts();
  }

  /// Derives the wrapping key from [secret] using KDF parameters in [metadata],
  /// unwraps the vault key, and returns it.
  ///
  /// On MAC mismatch, records a failed attempt and throws [VaultAuthException]
  /// with [authErrorMessage]. Callers remain responsible for lockout checks and
  /// any success-side bookkeeping (e.g. resetting attempt counters).
  Future<Uint8List> _authenticateAndUnwrapVaultKey({
    required String secret,
    required VaultMetadata metadata,
    String authErrorMessage = 'Incorrect secret. Please try again.',
  }) async {
    final Uint8List wrappingKeyBytes;
    try {
      wrappingKeyBytes = await _kdfService.deriveKey(
        secret: secret,
        salt: metadata.salt,
        iterations: metadata.kdfIterations,
        keyLength: 32,
      );
    } on PlatformException catch (e) {
      throw VaultPlatformException('Cryptographic service error: ${e.message ?? e.code}');
    } catch (e) {
      if (e is StateError) {
        throw VaultPlatformException('Cryptographic service error: ${e.message}');
      }
      rethrow;
    }

    try {
      final aesGcm = AesGcm.with256bits();
      final decrypted = await aesGcm.decrypt(
        SecretBox(
          metadata.wrappedVaultKey,
          nonce: metadata.wrappedVaultKeyIv,
          mac: Mac(metadata.wrappedVaultKeyTag),
        ),
        secretKey: SecretKey(wrappingKeyBytes),
        aad: vaultWrappingAad,
      );
      return Uint8List.fromList(decrypted);
    } on SecretBoxAuthenticationError {
      await _recordFailedAttempt();
      throw VaultAuthException(authErrorMessage);
    } catch (e) {
      if (e is VaultLockoutException || e is VaultAuthException || e is VaultPlatformException) rethrow;
      rethrow;
    }
  }

  /// Unlocks the vault by unwrapping the vault key with the secret.
  Future<void> unlockVault(String secret) async {
    await checkLockout();

    final metadata = await getVaultMetadata();
    if (metadata == null) {
      throw StateError('Vault has not been set up.');
    }

    _vaultKey = await _authenticateAndUnwrapVaultKey(
      secret: secret,
      metadata: metadata,
      authErrorMessage: 'Incorrect secret. Please try again.',
    );
    await _resetFailedAttempts();

    // A2: Cancel any pending delayed reset and record notice for the vault owner
    final delayedReset = await getDelayedResetStatus();
    if (delayedReset.isRequested && delayedReset.requestedAt != null) {
      await _db.insert(
        'app_settings',
        {
          'key': 'vault_pending_reset_notice_date',
          'value': delayedReset.requestedAt!.millisecondsSinceEpoch.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await cancelDelayedReset();
    }
  }

  /// Locks the vault and purges the key from memory.
  void lockVault() {
    _vaultKey = null;
  }

  /// Changes the vault secret and re-wraps the existing vault key.
  /// Always requires and verifies [currentSecret] even if vault is already unlocked.
  Future<void> changeSecret({
    required String currentSecret,
    required String newSecret,
    required CredentialType newCredentialType,
    int iterations = standardKdfIterations,
  }) async {
    final metadata = await getVaultMetadata();
    if (metadata == null) {
      throw StateError('Vault has not been set up.');
    }

    final currentVaultKey = await _authenticateAndUnwrapVaultKey(
      secret: currentSecret,
      metadata: metadata,
      authErrorMessage: 'Current secret is incorrect.',
    );

    final random = Random.secure();
    final newSalt = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      newSalt[i] = random.nextInt(256);
    }

    final newWrappingKeyBytes = await _kdfService.deriveKey(
      secret: newSecret,
      salt: newSalt,
      iterations: iterations,
      keyLength: 32,
    );

    final newIv = Uint8List(12);
    for (int i = 0; i < 12; i++) {
      newIv[i] = random.nextInt(256);
    }

    final aesGcm = AesGcm.with256bits();
    final secretBox = await aesGcm.encrypt(
      currentVaultKey,
      secretKey: SecretKey(newWrappingKeyBytes),
      nonce: newIv,
      aad: vaultWrappingAad,
    );

    final now = clock().millisecondsSinceEpoch;

    await _db.update(
      'vault_metadata',
      {
        'salt': newSalt,
        'kdf_algorithm': standardKdfAlgorithm,
        'kdf_iterations': iterations,
        'credential_type': newCredentialType.name,
        'wrapped_vault_key': secretBox.cipherText,
        'wrapped_vault_key_iv': newIv,
        'wrapped_vault_key_tag': secretBox.mac.bytes,
        'updated_at': now,
      },
      where: 'id = 1',
    );

    _vaultKey = currentVaultKey;
    await _resetFailedAttempts();
  }

  /// Returns true if a recovery key wrap is stored in vault_metadata.
  Future<bool> hasRecoveryKey() async {
    final res = await _db.query(
      'vault_metadata',
      columns: ['recovery_wrapped_key'],
      where: 'id = 1 AND recovery_wrapped_key IS NOT NULL',
    );
    return res.isNotEmpty;
  }

  /// Creates or rotates the recovery key wrap for an existing vault (R5, R7).
  /// Requires authenticating with [currentSecret] even if unlocked.
  /// Replaces the recovery wrap with the new key, immediately invalidating the old recovery key.
  Future<void> createOrUpdateRecoveryKey({
    required String currentSecret,
    required String recoveryKeyString,
  }) async {
    final metadata = await getVaultMetadata();
    if (metadata == null) {
      throw StateError('Vault has not been set up.');
    }

    final currentVaultKey = await _authenticateAndUnwrapVaultKey(
      secret: currentSecret,
      metadata: metadata,
      authErrorMessage: 'Current secret is incorrect.',
    );

    // Decode and validate new recovery key
    final recoveryBytes = RecoveryKeyService.decodeKey(recoveryKeyString);

    final random = Random.secure();
    final recoverySalt = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      recoverySalt[i] = random.nextInt(256);
    }

    final recoveryIv = Uint8List(12);
    for (int i = 0; i < 12; i++) {
      recoveryIv[i] = random.nextInt(256);
    }

    final box = await RecoveryKeyService.wrapVaultKey(
      vaultKey: currentVaultKey,
      recoveryKeyBytes: recoveryBytes,
      salt: recoverySalt,
      iv: recoveryIv,
    );

    final now = clock().millisecondsSinceEpoch;

    await _db.update(
      'vault_metadata',
      {
        'recovery_salt': recoverySalt,
        'recovery_wrapped_key': box.cipherText,
        'recovery_iv': recoveryIv,
        'recovery_tag': box.mac.bytes,
        'recovery_version': 1,
        'updated_at': now,
      },
      where: 'id = 1',
    );

    _vaultKey = currentVaultKey;
    await _resetFailedRecoveryAttempts();
  }

  /// Recovers the vault using a paper recovery key (R6).
  /// Verifies recovery lockout, validates format and checksum, unwraps the vault key,
  /// sets [newSecret], and replaces the primary wrap in a single transaction.
  /// The recovery wrap remains valid and is NOT rotated automatically.
  Future<void> recoverVault({
    required String recoveryKeyString,
    required String newSecret,
    required CredentialType newCredentialType,
    int iterations = standardKdfIterations,
  }) async {
    await checkRecoveryLockout();

    // Decode & validate: format or checksum errors throw and do NOT count as attempt (R6)
    final Uint8List recoveryBytes = RecoveryKeyService.decodeKey(recoveryKeyString);

    final metadata = await getVaultMetadata();
    if (metadata == null ||
        metadata.recoveryWrappedKey == null ||
        metadata.recoverySalt == null ||
        metadata.recoveryIv == null ||
        metadata.recoveryTag == null) {
      throw StateError('No recovery key exists for this vault.');
    }

    final Uint8List recoveredVaultKey;
    try {
      recoveredVaultKey = await RecoveryKeyService.unwrapVaultKey(
        wrappedVaultKey: metadata.recoveryWrappedKey!,
        iv: metadata.recoveryIv!,
        tag: metadata.recoveryTag!,
        recoveryKeyBytes: recoveryBytes,
        salt: metadata.recoverySalt!,
      );
    } on RecoveryKeyAuthException {
      // Well-formed but wrong key counts toward recovery failed attempts! (R6)
      await _recordFailedRecoveryAttempt();
      rethrow;
    }

    // Successfully recovered vault key! Now re-wrap primary secret
    final random = Random.secure();
    final newSalt = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      newSalt[i] = random.nextInt(256);
    }

    final newWrappingKeyBytes = await _kdfService.deriveKey(
      secret: newSecret,
      salt: newSalt,
      iterations: iterations,
      keyLength: 32,
    );

    final newIv = Uint8List(12);
    for (int i = 0; i < 12; i++) {
      newIv[i] = random.nextInt(256);
    }

    final aesGcm = AesGcm.with256bits();
    final secretBox = await aesGcm.encrypt(
      recoveredVaultKey,
      secretKey: SecretKey(newWrappingKeyBytes),
      nonce: newIv,
      aad: vaultWrappingAad,
    );

    final now = clock().millisecondsSinceEpoch;

    await _db.transaction((txn) async {
      await txn.update(
        'vault_metadata',
        {
          'salt': newSalt,
          'kdf_algorithm': standardKdfAlgorithm,
          'kdf_iterations': iterations,
          'credential_type': newCredentialType.name,
          'wrapped_vault_key': secretBox.cipherText,
          'wrapped_vault_key_iv': newIv,
          'wrapped_vault_key_tag': secretBox.mac.bytes,
          'updated_at': now,
        },
        where: 'id = 1',
      );

      // Reset both main and recovery attempt counters
      await txn.delete(
        'app_settings',
        where: "key IN ("
            "'vault_failed_attempts', 'vault_next_allowed_time', 'vault_last_attempt_time', 'vault_lockout_elapsed_realtime', 'vault_lockout_recorded_elapsed', "
            "'vault_recovery_failed_attempts', 'vault_recovery_next_allowed_time', 'vault_recovery_last_attempt_time', 'vault_recovery_lockout_elapsed_realtime', 'vault_recovery_lockout_recorded_elapsed'"
            ")",
      );
    });

    _vaultKey = recoveredVaultKey;

    // A2: Cancel any pending delayed reset and record notice for the vault owner
    final delayedReset = await getDelayedResetStatus();
    if (delayedReset.isRequested && delayedReset.requestedAt != null) {
      await _db.insert(
        'app_settings',
        {
          'key': 'vault_pending_reset_notice_date',
          'value': delayedReset.requestedAt!.millisecondsSinceEpoch.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await cancelDelayedReset();
    }
  }

  /// Permanently deletes all locked notes, vault metadata, and lockout settings (A4).
  /// New vault creation is allowed only after a reset.
  Future<void> resetVault() async {
    await _db.transaction((txn) async {
      await txn.delete('notes', where: 'is_locked = 1');
      await txn.delete('vault_metadata', where: 'id = 1');
      await txn.delete(
        'app_settings',
        where: "key IN ("
            "'vault_failed_attempts', 'vault_next_allowed_time', 'vault_last_attempt_time', 'vault_lockout_elapsed_realtime', 'vault_lockout_recorded_elapsed', 'vault_lockout_boot_time', 'vault_auto_lock_timeout', "
            "'vault_recovery_failed_attempts', 'vault_recovery_next_allowed_time', 'vault_recovery_last_attempt_time', 'vault_recovery_lockout_elapsed_realtime', 'vault_recovery_lockout_recorded_elapsed', "
            "'vault_delayed_reset_requested_at', 'vault_delayed_reset_elapsed', 'vault_delayed_reset_last_seen', 'vault_pending_reset_notice_date'"
            ")",
      );
    });
    _vaultKey = null;
  }

  /// A1: Immediate reset proved with current PIN/pattern and typed DELETE.
  Future<void> immediateResetWithSecret({
    required String secret,
    required String confirmationText,
  }) async {
    if (confirmationText != 'DELETE') {
      throw ArgumentError('Type DELETE exactly to confirm.');
    }
    await checkLockout();
    final metadata = await getVaultMetadata();
    if (metadata == null) {
      await resetVault();
      return;
    }

    await _authenticateAndUnwrapVaultKey(
      secret: secret,
      metadata: metadata,
      authErrorMessage: 'Current secret is incorrect.',
    );
    await resetVault();
  }

  /// A1: Immediate reset proved with paper recovery key and typed DELETE.
  Future<void> immediateResetWithRecoveryKey({
    required String recoveryKeyString,
    required String confirmationText,
  }) async {
    if (confirmationText != 'DELETE') {
      throw ArgumentError('Type DELETE exactly to confirm.');
    }
    final metadata = await getVaultMetadata();
    if (metadata == null) {
      await resetVault();
      return;
    }
    if (!metadata.hasRecoveryKey ||
        metadata.recoveryWrappedKey == null ||
        metadata.recoverySalt == null ||
        metadata.recoveryIv == null ||
        metadata.recoveryTag == null) {
      throw StateError('No recovery key exists for this vault.');
    }
    await checkRecoveryLockout();
    final recoveryBytes = RecoveryKeyService.decodeKey(recoveryKeyString);
    try {
      await RecoveryKeyService.unwrapVaultKey(
        wrappedVaultKey: metadata.recoveryWrappedKey!,
        iv: metadata.recoveryIv!,
        tag: metadata.recoveryTag!,
        recoveryKeyBytes: recoveryBytes,
        salt: metadata.recoverySalt!,
      );
    } on RecoveryKeyAuthException {
      await _recordFailedRecoveryAttempt();
      rethrow;
    }
    await resetVault();
  }

  /// A2: Requests a delayed reset (starts 72-hour countdown).
  Future<void> requestDelayedReset() async {
    final nowWall = clock().millisecondsSinceEpoch;
    await _db.insert(
      'app_settings',
      {'key': 'vault_delayed_reset_requested_at', 'value': nowWall.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _db.insert(
      'app_settings',
      {'key': 'vault_delayed_reset_last_seen', 'value': nowWall.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (elapsedRealtimeProvider != null) {
      try {
        final elapsed = await elapsedRealtimeProvider!();
        await _db.insert(
          'app_settings',
          {'key': 'vault_delayed_reset_elapsed', 'value': elapsed.toString()},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (_) {}
    }
  }

  /// Cancels an active delayed reset request.
  Future<void> cancelDelayedReset() async {
    await _db.delete(
      'app_settings',
      where: "key IN ('vault_delayed_reset_requested_at', 'vault_delayed_reset_elapsed', 'vault_delayed_reset_last_seen')",
    );
  }

  /// Dual-clock verification for 72-hour delayed reset (Requirement A3).
  ///
  /// Uses wall clock (DateTime) coupled with Android's monotonic elapsedRealtime
  /// to prevent trivial clock rollbacks or fast-forwards.
  ///
  /// LIMITATION:
  /// While the device remains booted, elapsedRealtime monotonically increases,
  /// preventing the user from bypassing the 72-hour delay by advancing the system clock.
  /// However, Android's SystemClock.elapsedRealtime resets to 0 upon device reboot.
  /// Following a reboot, elapsedRealtime can no longer measure time elapsed before the
  /// reboot. The service falls back to wall-clock monotonicity (ensuring the current
  /// clock has not moved backward relative to the last recorded timestamp).
  /// Consequently, an attacker with physical access could potentially reboot the device
  /// and manually advance the device wall clock in system settings across the reboot,
  /// as offline Android apps lack access to a tamper-proof hardware RTC or trusted network time.
  Future<DelayedResetStatus> getDelayedResetStatus() async {
    final res = await _db.query(
      'app_settings',
      where: "key IN ('vault_delayed_reset_requested_at', 'vault_delayed_reset_elapsed', 'vault_delayed_reset_last_seen')",
    );
    final map = {for (final r in res) r['key'] as String: r['value'] as String};
    final requestedAtStr = map['vault_delayed_reset_requested_at'];
    if (requestedAtStr == null) {
      return const DelayedResetStatus(
        isRequested: false,
        remainingSeconds: 0,
        isReady: false,
      );
    }

    final requestedAtMs = int.tryParse(requestedAtStr) ?? 0;
    final lastSeenMs = int.tryParse(map['vault_delayed_reset_last_seen'] ?? '') ?? requestedAtMs;
    final requestedElapsedMs = int.tryParse(map['vault_delayed_reset_elapsed'] ?? '');
    final nowWallMs = clock().millisecondsSinceEpoch;

    // Detect wall-clock rollback
    if (nowWallMs >= lastSeenMs) {
      await _db.insert(
        'app_settings',
        {'key': 'vault_delayed_reset_last_seen', 'value': nowWallMs.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    const int seventyTwoHoursMs = 72 * 60 * 60 * 1000;
    int effectivePassedMs;

    if (elapsedRealtimeProvider != null && requestedElapsedMs != null) {
      final currentElapsed = await elapsedRealtimeProvider!();
      if (currentElapsed >= requestedElapsedMs) {
        // Same boot session: monotonic elapsedRealtime governs progress
        final elapsedDelta = currentElapsed - requestedElapsedMs;
        final wallDelta = nowWallMs > requestedAtMs ? (nowWallMs - requestedAtMs) : 0;
        effectivePassedMs = min(wallDelta, elapsedDelta);
      } else {
        // Reboot occurred: fall back to wall-clock with monotonicity protection
        final effectiveWall = (nowWallMs >= lastSeenMs) ? nowWallMs : lastSeenMs;
        effectivePassedMs = effectiveWall > requestedAtMs ? (effectiveWall - requestedAtMs) : 0;
      }
    } else {
      final effectiveWall = (nowWallMs >= lastSeenMs) ? nowWallMs : lastSeenMs;
      effectivePassedMs = effectiveWall > requestedAtMs ? (effectiveWall - requestedAtMs) : 0;
    }

    final remainingMs = max(0, seventyTwoHoursMs - effectivePassedMs);
    final remainingSeconds = (remainingMs / 1000).ceil();

    return DelayedResetStatus(
      isRequested: true,
      requestedAt: DateTime.fromMillisecondsSinceEpoch(requestedAtMs),
      remainingSeconds: remainingSeconds,
      isReady: remainingSeconds <= 0,
    );
  }

  /// Completes the delayed reset with typed confirmation DELETE after 72 hours (A2).
  Future<void> completeDelayedReset({required String confirmationText}) async {
    if (confirmationText != 'DELETE') {
      throw ArgumentError('Type DELETE exactly to confirm.');
    }
    final status = await getDelayedResetStatus();
    if (!status.isRequested) {
      throw StateError('No delayed reset has been requested.');
    }
    if (!status.isReady) {
      throw StateError('Delayed reset period has not elapsed yet (${status.remainingSeconds}s remaining).');
    }
    await resetVault();
  }

  /// Notice displayed to owner if a reset was requested while unlocked/recovered (A2).
  Future<DateTime?> getPendingResetNoticeDate() async {
    final res = await _db.query('app_settings', where: "key = 'vault_pending_reset_notice_date'");
    if (res.isEmpty) return null;
    final ms = int.tryParse(res.first['value'] as String);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> clearPendingResetNoticeDate() async {
    await _db.delete('app_settings', where: "key = 'vault_pending_reset_notice_date'");
  }

  /// Compatibility wrapper for authorized vault resets.
  Future<void> resetVaultWithAuthorization({
    String? recoveryKeyString,
    String? secret,
    bool forceUnprotected = false,
  }) async {
    if (recoveryKeyString != null && recoveryKeyString.isNotEmpty) {
      await immediateResetWithRecoveryKey(
        recoveryKeyString: recoveryKeyString,
        confirmationText: 'DELETE',
      );
    } else if (secret != null && secret.isNotEmpty) {
      await immediateResetWithSecret(
        secret: secret,
        confirmationText: 'DELETE',
      );
    } else if (forceUnprotected) {
      await resetVault();
    } else {
      throw ArgumentError('Authorization is required to reset this vault.');
    }
  }

  // --- Auto-lock Timeout Persistence (D7) ---

  Future<String> getAutoLockTimeout() async {
    final res = await _db.query('app_settings', where: "key = 'vault_auto_lock_timeout'");
    if (res.isEmpty) return 'background';
    return (res.first['value'] as String?) ?? 'background';
  }

  Future<void> setAutoLockTimeout(String timeout) async {
    await _db.insert(
      'app_settings',
      {'key': 'vault_auto_lock_timeout', 'value': timeout},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Failed Attempts & Lockout Schedule (D5) ---

  static int getDelayForFailedAttempts(int failures) {
    if (failures < 5) return 0;
    switch (failures) {
      case 5:
        return 30;
      case 6:
        return 60;
      case 7:
        return 300;
      case 8:
        return 900;
      default:
        return 1800;
    }
  }

  Future<void> checkLockout() async {
    final remaining = await getRemainingLockoutSeconds();
    if (remaining > 0) {
      throw VaultLockoutException(remaining);
    }
  }

  Future<int> getRemainingLockoutSeconds() async {
    final now = clock().millisecondsSinceEpoch;

    // 1. Monotonic elapsedRealtime check if provider configured
    if (elapsedRealtimeProvider != null) {
      final elapsed = await elapsedRealtimeProvider!();
      final res = await _db.query('app_settings', where: "key IN ('vault_lockout_elapsed_realtime', 'vault_lockout_recorded_elapsed')");
      final map = {for (final r in res) r['key'] as String: r['value'] as String};
      final lockoutElapsed = int.tryParse(map['vault_lockout_elapsed_realtime'] ?? '');
      final recordedElapsed = int.tryParse(map['vault_lockout_recorded_elapsed'] ?? '');

      if (lockoutElapsed != null && recordedElapsed != null) {
        // As long as elapsed >= recordedElapsed, device has NOT rebooted
        if (elapsed >= recordedElapsed) {
          if (lockoutElapsed > elapsed) {
            return ((lockoutElapsed - elapsed) / 1000).ceil();
          } else {
            return 0;
          }
        }
      }
    }

    // 2. Clock rollback detection: check if now < last recorded attempt time
    final res = await _db.query('app_settings', where: "key = 'vault_last_attempt_time'");
    final lastTime = res.isNotEmpty ? (int.tryParse(res.first['value'] as String) ?? 0) : 0;
    if (lastTime > 0 && now < lastTime) {
      final failures = await getFailedAttempts();
      final delaySeconds = getDelayForFailedAttempts(failures);
      if (delaySeconds > 0) {
        return delaySeconds;
      }
    }

    // 3. Wall-clock next allowed check
    final nextAllowed = await _getNextAllowedTime();
    if (nextAllowed > now) {
      final failures = await getFailedAttempts();
      final delaySeconds = getDelayForFailedAttempts(failures);
      final remaining = ((nextAllowed - now) / 1000).ceil();
      return (delaySeconds > 0 && remaining > delaySeconds) ? delaySeconds : remaining;
    }

    return 0;
  }

  Future<int> getFailedAttempts() async {
    final res = await _db.query('app_settings', where: "key = 'vault_failed_attempts'");
    if (res.isEmpty) return 0;
    return int.tryParse(res.first['value'] as String) ?? 0;
  }

  Future<int> _getNextAllowedTime() async {
    final res = await _db.query('app_settings', where: "key = 'vault_next_allowed_time'");
    if (res.isEmpty) return 0;
    return int.tryParse(res.first['value'] as String) ?? 0;
  }

  Future<void> _recordFailedAttempt() async {
    final currentFailures = await getFailedAttempts() + 1;
    final delaySeconds = getDelayForFailedAttempts(currentFailures);
    final now = clock().millisecondsSinceEpoch;
    final nextAllowed = now + (delaySeconds * 1000);

    await _db.insert(
      'app_settings',
      {'key': 'vault_failed_attempts', 'value': currentFailures.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _db.insert(
      'app_settings',
      {'key': 'vault_next_allowed_time', 'value': nextAllowed.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _db.insert(
      'app_settings',
      {'key': 'vault_last_attempt_time', 'value': now.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (elapsedRealtimeProvider != null) {
      final elapsed = await elapsedRealtimeProvider!();
      final lockoutElapsed = elapsed + (delaySeconds * 1000);

      await _db.insert(
        'app_settings',
        {'key': 'vault_lockout_elapsed_realtime', 'value': lockoutElapsed.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _db.insert(
        'app_settings',
        {'key': 'vault_lockout_recorded_elapsed', 'value': elapsed.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _resetFailedAttempts() async {
    await _db.delete(
      'app_settings',
      where: "key IN ('vault_failed_attempts', 'vault_next_allowed_time', 'vault_last_attempt_time', 'vault_lockout_elapsed_realtime', 'vault_lockout_recorded_elapsed')",
    );
  }

  // --- Recovery Failed Attempts & Lockout Schedule (R6) ---

  Future<void> checkRecoveryLockout() async {
    final remaining = await getRemainingRecoveryLockoutSeconds();
    if (remaining > 0) {
      throw VaultLockoutException(remaining);
    }
  }

  Future<int> getRemainingRecoveryLockoutSeconds() async {
    final now = clock().millisecondsSinceEpoch;

    // 1. Monotonic elapsedRealtime check if provider configured
    if (elapsedRealtimeProvider != null) {
      final elapsed = await elapsedRealtimeProvider!();
      final res = await _db.query('app_settings', where: "key IN ('vault_recovery_lockout_elapsed_realtime', 'vault_recovery_lockout_recorded_elapsed')");
      final map = {for (final r in res) r['key'] as String: r['value'] as String};
      final lockoutElapsed = int.tryParse(map['vault_recovery_lockout_elapsed_realtime'] ?? '');
      final recordedElapsed = int.tryParse(map['vault_recovery_lockout_recorded_elapsed'] ?? '');

      if (lockoutElapsed != null && recordedElapsed != null) {
        if (elapsed >= recordedElapsed) {
          if (lockoutElapsed > elapsed) {
            return ((lockoutElapsed - elapsed) / 1000).ceil();
          } else {
            return 0;
          }
        }
      }
    }

    // 2. Clock rollback detection
    final res = await _db.query('app_settings', where: "key = 'vault_recovery_last_attempt_time'");
    final lastTime = res.isNotEmpty ? (int.tryParse(res.first['value'] as String) ?? 0) : 0;
    if (lastTime > 0 && now < lastTime) {
      final failures = await getRecoveryFailedAttempts();
      final delaySeconds = getDelayForFailedAttempts(failures);
      if (delaySeconds > 0) {
        return delaySeconds;
      }
    }

    // 3. Wall-clock next allowed check
    final nextAllowedRes = await _db.query('app_settings', where: "key = 'vault_recovery_next_allowed_time'");
    final nextAllowed = nextAllowedRes.isNotEmpty ? (int.tryParse(nextAllowedRes.first['value'] as String) ?? 0) : 0;
    if (nextAllowed > now) {
      final failures = await getRecoveryFailedAttempts();
      final delaySeconds = getDelayForFailedAttempts(failures);
      final remaining = ((nextAllowed - now) / 1000).ceil();
      return (delaySeconds > 0 && remaining > delaySeconds) ? delaySeconds : remaining;
    }

    return 0;
  }

  Future<int> getRecoveryFailedAttempts() async {
    final res = await _db.query('app_settings', where: "key = 'vault_recovery_failed_attempts'");
    if (res.isEmpty) return 0;
    return int.tryParse(res.first['value'] as String) ?? 0;
  }

  Future<void> _recordFailedRecoveryAttempt() async {
    final currentFailures = await getRecoveryFailedAttempts() + 1;
    final delaySeconds = getDelayForFailedAttempts(currentFailures);
    final now = clock().millisecondsSinceEpoch;
    final nextAllowed = now + (delaySeconds * 1000);

    await _db.insert(
      'app_settings',
      {'key': 'vault_recovery_failed_attempts', 'value': currentFailures.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _db.insert(
      'app_settings',
      {'key': 'vault_recovery_next_allowed_time', 'value': nextAllowed.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _db.insert(
      'app_settings',
      {'key': 'vault_recovery_last_attempt_time', 'value': now.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (elapsedRealtimeProvider != null) {
      final elapsed = await elapsedRealtimeProvider!();
      final lockoutElapsed = elapsed + (delaySeconds * 1000);

      await _db.insert(
        'app_settings',
        {'key': 'vault_recovery_lockout_elapsed_realtime', 'value': lockoutElapsed.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _db.insert(
        'app_settings',
        {'key': 'vault_recovery_lockout_recorded_elapsed', 'value': elapsed.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _resetFailedRecoveryAttempts() async {
    await _db.delete(
      'app_settings',
      where: "key IN ('vault_recovery_failed_attempts', 'vault_recovery_next_allowed_time', 'vault_recovery_last_attempt_time', 'vault_recovery_lockout_elapsed_realtime', 'vault_recovery_lockout_recorded_elapsed')",
    );
  }
}
