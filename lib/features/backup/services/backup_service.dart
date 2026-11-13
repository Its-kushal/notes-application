import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../../core/crypto/recovery_key_service.dart';
import '../../../core/database/app_database.dart';
import '../domain/backup_manifest.dart';

abstract class BackupException implements Exception {
  final String message;
  const BackupException(this.message);

  @override
  String toString() => message;
}

class BackupSecurityException extends BackupException {
  const BackupSecurityException([
    super.message = 'Wrong recovery key or damaged file.',
  ]);
}

class BackupOversizeException extends BackupException {
  const BackupOversizeException([
    super.message = 'Backup file exceeds the 64 MB limit.',
  ]);
}

class BackupUnsupportedVersionException extends BackupException {
  const BackupUnsupportedVersionException([
    super.message = 'This backup was created with a newer version of LeafLock.',
  ]);
}

class BackupSelfTestException extends BackupException {
  const BackupSelfTestException([
    super.message = 'Backup self-test failed. The backup file was not saved.',
  ]);
}

class BackupDecompressionBombException extends BackupException {
  final int bytesDecompressed;

  const BackupDecompressionBombException({
    this.bytesDecompressed = 0,
    String message = 'Decompressed backup exceeds the 64 MB decompression limit.',
  }) : super(message);
}

class BackupSafetyCopyException extends BackupException {
  const BackupSafetyCopyException([
    super.message = 'Could not create safety copy of database. Restore was cancelled.',
  ]);
}

class BackupInvalidDataException extends BackupException {
  const BackupInvalidDataException([
    super.message = 'The backup contains invalid or corrupted data.',
  ]);
}

/// Sink that counts every output chunk as it arrives from the decompressor,
/// throwing [BackupDecompressionBombException] the moment [maxBytes] is exceeded (Requirement 1).
class _CappedDecompressionSink implements ChunkedConversionSink<List<int>> {
  final int maxBytes;
  final BytesBuilder builder = BytesBuilder(copy: false);
  int totalBytes = 0;

  _CappedDecompressionSink(this.maxBytes);

  @override
  void add(List<int> chunk) {
    totalBytes += chunk.length;
    if (totalBytes > maxBytes) {
      throw BackupDecompressionBombException(bytesDecompressed: totalBytes);
    }
    builder.add(chunk);
  }

  @override
  void close() {}
}

/// Service managing offline authenticated encrypted backup creation, verification,
/// SAF export, share staging, and non-destructive restore (B1-B5).
class BackupService {
  static const List<int> magicBytes = [0x4C, 0x4C, 0x42, 0x4B]; // ASCII "LLBK"
  static const int currentFormatVersion = 0x01;
  static const int saltBytesLength = 16;
  static const int nonceBytesLength = 12;
  static const int headerLength = 4 + 1 + saltBytesLength + nonceBytesLength; // 33 bytes
  static const int maxFileSizeBytes = 64 * 1024 * 1024; // 64 MB (C)
  static const int maxDecompressedSizeBytes = 64 * 1024 * 1024; // 64 MB (C)

  @visibleForTesting
  static bool failRestoreForTesting = false;

  @visibleForTesting
  static bool failSafetyCopyForTesting = false;

  final AppDatabase appDatabase;

  BackupService({required this.appDatabase});

  Database get _db => appDatabase.database;

  Database? get _dbOrNull {
    if (!appDatabase.isReady) return null;
    try {
      return appDatabase.database;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // SUBKEY & SETTINGS PERSISTENCE (B1, B2)
  // ---------------------------------------------------------------------------

  /// Returns the stored 32-byte backup subkey, or null if none exists.
  Future<Uint8List?> getStoredBackupSubkey() async {
    final db = _dbOrNull;
    if (db == null) return null;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['backup_subkey'],
    );
    if (rows.isEmpty) return null;
    final val = rows.first['value'] as String?;
    if (val == null || val.isEmpty) return null;
    try {
      final decoded = base64Decode(val);
      if (decoded.length == 32) return decoded;
    } catch (_) {}
    return null;
  }

  /// Stores the derived 32-byte backup subkey in encrypted app_settings.
  Future<void> storeBackupSubkey(Uint8List subkey) async {
    if (subkey.length != 32) {
      throw ArgumentError('Backup subkey must be exactly 32 bytes.');
    }
    await _db.insert(
      'app_settings',
      {
        'key': 'backup_subkey',
        'value': base64Encode(subkey),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Whether a backup subkey is currently stored.
  Future<bool> hasStoredBackupSubkey() async {
    final subkey = await getStoredBackupSubkey();
    return subkey != null;
  }

  /// Returns the timestamp (ms) of the last confirmed backup, or null if none.
  Future<DateTime?> getLastBackupDate() async {
    final db = _dbOrNull;
    if (db == null) return null;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['last_backup_at'],
    );
    if (rows.isEmpty) return null;
    final val = rows.first['value'] as String?;
    if (val == null || val.isEmpty) return null;
    final ms = int.tryParse(val);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Records a successful, confirmed backup timestamp (B4).
  Future<void> recordLastBackupDate([DateTime? date]) async {
    final db = _dbOrNull;
    if (db == null) return;
    final now = date ?? DateTime.now();
    await db.insert(
      'app_settings',
      {
        'key': 'last_backup_at',
        'value': now.millisecondsSinceEpoch.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns whether the 30-day backup reminder is enabled in settings (default true).
  Future<bool> isBackupReminderEnabled() async {
    final db = _dbOrNull;
    if (db == null) return true;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['backup_reminder_enabled'],
    );
    if (rows.isEmpty) return true;
    final val = rows.first['value'] as String?;
    return val != 'false';
  }

  /// Updates the 30-day backup reminder toggle in settings.
  Future<void> setBackupReminderEnabled(bool enabled) async {
    final db = _dbOrNull;
    if (db == null) return;
    await db.insert(
      'app_settings',
      {
        'key': 'backup_reminder_enabled',
        'value': enabled ? 'true' : 'false',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns the snooze expiration date for the backup reminder banner, or null.
  Future<DateTime?> getBackupReminderSnoozeDate() async {
    final db = _dbOrNull;
    if (db == null) return null;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['backup_reminder_snoozed_until'],
    );
    if (rows.isEmpty) return null;
    final val = rows.first['value'] as String?;
    if (val == null) return null;
    final ms = int.tryParse(val);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Snoozes the backup reminder banner for 3 days (B6).
  Future<void> snoozeBackupReminder({int snoozeDays = 3}) async {
    final db = _dbOrNull;
    if (db == null) return;
    final until = DateTime.now().add(Duration(days: snoozeDays));
    await db.insert(
      'app_settings',
      {
        'key': 'backup_reminder_snoozed_until',
        'value': until.millisecondsSinceEpoch.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns true if the 30-day backup reminder banner should be shown (B, G).
  Future<bool> shouldShowReminderBanner() async {
    final db = _dbOrNull;
    if (db == null) return false;
    final enabled = await isBackupReminderEnabled();
    if (!enabled) return false;

    final snoozedUntil = await getBackupReminderSnoozeDate();
    if (snoozedUntil != null && DateTime.now().isBefore(snoozedUntil)) {
      return false;
    }

    final lastBackup = await getLastBackupDate();
    if (lastBackup == null) {
      final firstNote = await db.query('notes', columns: ['created_at'], orderBy: 'created_at ASC', limit: 1);
      if (firstNote.isEmpty) return false;
      final createdAtMs = firstNote.first['created_at'] as int?;
      if (createdAtMs == null) return false;
      final firstNoteDate = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
      return DateTime.now().difference(firstNoteDate).inDays >= 30;
    }

    return DateTime.now().difference(lastBackup).inDays >= 30;
  }

  // ---------------------------------------------------------------------------
  // SHARE CACHE CLEANUP (B)
  // ---------------------------------------------------------------------------

  /// Cleans any staged backup files in the cache directory (B).
  static Future<void> cleanShareCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final dir = Directory('${cacheDir.path}/backup_share');
      if (await dir.exists()) {
        final entities = await dir.list().toList();
        for (final entity in entities) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // BACKUP CREATION & SELF-TEST (B3, B4, C)
  // ---------------------------------------------------------------------------

  /// Exports the database state into an authenticated, encrypted .llbackup binary container.
  /// Executes heavy compression, JSON parsing, and crypto in a background worker isolate (C).
  /// Performs an in-memory decryption self-test verifying entity counts before returning (B4).
  Future<Uint8List> createBackupBytes() async {
    final backupSubkey = await getStoredBackupSubkey();
    if (backupSubkey == null) {
      throw StateError('Cannot create backup: No backup subkey found in settings.');
    }

    // 1. Gather all database records (including archived, trashed, and locked notes)
    final notesRows = await _db.query('notes');
    final foldersRows = await _db.query('folders');
    final vaultRows = await _db.query('vault_metadata', where: 'id = 1');
    final settingsRows = await _db.query('app_settings');

    final safeSettings = <String, String>{};
    for (final row in settingsRows) {
      final k = row['key'] as String?;
      final v = row['value'] as String?;
      if (k != null && v != null && BackupManifest.allowedSettingsKeys.contains(k)) {
        safeSettings[k] = v;
      }
    }

    final manifest = BackupManifest(
      schemaVersion: BackupManifest.currentSchemaVersion,
      appVersion: BackupManifest.currentAppVersion,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      folders: foldersRows.map((r) => Map<String, dynamic>.from(r)).toList(),
      notes: notesRows.map((r) => Map<String, dynamic>.from(r)).toList(),
      vaultMetadata: vaultRows.isNotEmpty ? Map<String, dynamic>.from(vaultRows.first) : null,
      settings: safeSettings,
    );

    final jsonString = manifest.toJsonString();

    // 2. Run compression and encryption in an isolate (C)
    final backupBytes = await compute(_isolateCreateBackup, {
      'jsonString': jsonString,
      'backupSubkey': backupSubkey,
    });

    // 3. In-memory self-test: decrypt and verify counts match before returning (B4)
    final testManifest = await compute(_isolateDecryptAndParse, {
      'backupBytes': backupBytes,
      'backupSubkey': backupSubkey,
    });

    if (testManifest.notes.length != manifest.notes.length ||
        testManifest.folders.length != manifest.folders.length) {
      throw const BackupSelfTestException();
    }

    return backupBytes;
  }

  /// Default file name formatted as LeafLock-YYYY-MM-DD.llbackup (B4).
  static String defaultBackupFileName([DateTime? date]) {
    final d = date ?? DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(d);
    return 'LeafLock-$dateStr.llbackup';
  }

  /// Prompts user to save the backup file via Android Storage Access Framework (SAF) (B4).
  /// Records last_backup_at only upon confirmed successful save.
  Future<String?> saveBackupViaSaf(Uint8List bytes) async {
    final fileName = defaultBackupFileName();
    final result = await FilePicker.saveFile(
      dialogTitle: 'Save LeafLock Backup',
      fileName: fileName,
      bytes: bytes,
    );

    if (result != null) {
      await recordLastBackupDate();
      return result.toString();
    }
    return null;
  }

  /// Stages backup file in cache and opens the Android system share sheet (B4).
  /// Note: last_backup_at is NOT automatically updated by the share sheet alone (B).
  Future<String> stageAndShareBackup(Uint8List bytes) async {
    await cleanShareCache();
    final cacheDir = await getTemporaryDirectory();
    final shareDir = Directory('${cacheDir.path}/backup_share');
    if (!await shareDir.exists()) {
      await shareDir.create(recursive: true);
    }

    final fileName = defaultBackupFileName();
    final filePath = '${shareDir.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);

    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile(filePath, mimeType: 'application/octet-stream', name: fileName)],
      subject: 'LeafLock Backup ($fileName)',
    );

    return filePath;
  }

  // ---------------------------------------------------------------------------
  // RESTORE & INTEGRITY VALIDATION (B5, C, D, E)
  // ---------------------------------------------------------------------------

  /// Validates container headers, decrypts with paper key, decompressing with 64 MB cap,
  /// makes pre-restore safety copy, and non-destructively merges missing notes and folders.
  Future<RestoreSummary> validateAndRestoreBackup({
    required Uint8List fileBytes,
    required String recoveryKeyString,
  }) async {
    // 1. Size cap check (64 MB) (C, D)
    if (fileBytes.length > maxFileSizeBytes) {
      throw const BackupOversizeException();
    }

    if (fileBytes.length < headerLength + 16) {
      // Must hold header + at least 16-byte GCM auth tag
      throw const BackupSecurityException();
    }

    // 2. Validate magic bytes (D)
    for (int i = 0; i < 4; i++) {
      if (fileBytes[i] != magicBytes[i]) {
        throw const BackupSecurityException();
      }
    }

    // 3. Validate version (D)
    final version = fileBytes[4];
    if (version > currentFormatVersion) {
      throw const BackupUnsupportedVersionException();
    }

    // 4. Validate recovery key format and mod-1021 checksum first (E)
    Uint8List rootKeyBytes;
    try {
      rootKeyBytes = RecoveryKeyService.decodeKey(recoveryKeyString);
    } catch (_) {
      throw const BackupSecurityException();
    }

    // 5. Derive backupSubkey
    final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootKeyBytes);

    // 6. Decrypt and decompress in isolate with 64 MB decompression cap (C)
    BackupManifest manifest;
    try {
      manifest = await compute(_isolateDecryptAndParse, {
        'backupBytes': fileBytes,
        'backupSubkey': backupSubkey,
      });
    } on BackupDecompressionBombException {
      rethrow;
    } on BackupUnsupportedVersionException {
      rethrow;
    } on BackupInvalidDataException {
      rethrow;
    } catch (e) {
      throw const BackupSecurityException();
    }

    // 7. Validate data structure, column names, types, lengths before touching DB (Requirement 5)
    manifest.validate();

    // 8. Make pre-restore safety copy in databases/backups/ (B5, Requirement 4)
    await _createPreRestoreSafetyCopy();

    // 9. Apply in ONE transaction and ONLY ADD missing entities by ID (B5)
    return await _applyRestoreTransaction(manifest, backupSubkey, rootKeyBytes);
  }

  /// Creates a pre-restore database safety copy keeping the last 2 copies (B5).
  /// Aborts and throws [BackupSafetyCopyException] if copying fails or file size differs (Requirement 4).
  Future<void> _createPreRestoreSafetyCopy() async {
    if (failSafetyCopyForTesting) {
      throw const BackupSafetyCopyException();
    }

    try {
      final dbPath = await appDatabase.resolveDatabasePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        if (dbPath == inMemoryDatabasePath) return;
        throw const BackupSafetyCopyException('Source database file not found for safety copy.');
      }

      final sourceSize = await dbFile.length();
      final databasesDir = dbFile.parent.path;
      final backupDir = Directory('$databasesDir/backups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final copyPath = '${backupDir.path}/leaflock_pre_restore_$timestamp.db';
      final copyFile = await dbFile.copy(copyPath);

      final copySize = await copyFile.length();
      if (copySize != sourceSize) {
        try {
          await copyFile.delete();
        } catch (_) {}
        throw const BackupSafetyCopyException(
          'Safety copy size mismatch. Restore was cancelled.',
        );
      }

      // Prune old pre-restore copies, keeping only the last 2
      final copies = await backupDir
          .list()
          .where((e) => e is File && e.path.contains('pre_restore'))
          .cast<File>()
          .toList();

      if (copies.length > 2) {
        copies.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        while (copies.length > 2) {
          final oldest = copies.removeAt(0);
          try {
            await oldest.delete();
          } catch (_) {}
        }
      }
    } on BackupSafetyCopyException {
      rethrow;
    } catch (e) {
      throw BackupSafetyCopyException('Failed to create pre-restore safety copy: $e');
    }
  }

  static Uint8List? _toUint8List(dynamic value) {
    if (value == null) return null;
    if (value is Uint8List) return value;
    if (value is List) return Uint8List.fromList(value.cast<int>());
    return null;
  }

  static Map<String, dynamic> _normalizeRow(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.from(row);
    for (final entry in row.entries) {
      if (entry.value is List && entry.value is! Uint8List) {
        copy[entry.key] = Uint8List.fromList((entry.value as List).cast<int>());
      }
    }
    return copy;
  }

  /// Applies restore changes in a single SQLite transaction with strict non-destructive rules (B5).
  Future<RestoreSummary> _applyRestoreTransaction(
    BackupManifest manifest,
    Uint8List backupSubkey,
    Uint8List rootKeyBytes,
  ) async {
    return await _db.transaction((txn) async {
      int addedFolders = 0;
      int skippedFolders = 0;
      int addedNotes = 0;
      int skippedNotes = 0;
      int lockedNotesSkipped = 0;
      bool vaultAdopted = false;

      // 1. Folders: insert missing by ID, never overwrite existing
      for (final folder in manifest.folders) {
        final id = folder['id'] as String?;
        if (id == null) continue;
        final existing = await txn.query('folders', where: 'id = ?', whereArgs: [id]);
        if (existing.isNotEmpty) {
          skippedFolders++;
        } else {
          await txn.insert('folders', folder, conflictAlgorithm: ConflictAlgorithm.ignore);
          addedFolders++;
        }
      }

      // 2. Vault Reconciliation:
      // If no local vault exists, adopt the backup's vault metadata.
      // If a local vault exists, test unwrap on both: if identical key, allow locked notes;
      // if different vault, skip locked notes and report count.
      bool canRestoreLockedNotes = false;
      final localVaultRows = await txn.query('vault_metadata', where: 'id = 1');

      if (localVaultRows.isEmpty) {
        if (manifest.vaultMetadata != null) {
          await txn.insert(
            'vault_metadata',
            _normalizeRow(manifest.vaultMetadata!),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          vaultAdopted = true;
          canRestoreLockedNotes = true;
        } else {
          canRestoreLockedNotes = false;
        }
      } else {
        // Local vault exists: verify whether it is the SAME vault
        if (manifest.vaultMetadata != null) {
          final localMeta = localVaultRows.first;
          final backupMeta = manifest.vaultMetadata!;

          final localWrap = _toUint8List(localMeta['recovery_wrapped_key']);
          final localIv = _toUint8List(localMeta['recovery_iv']);
          final localTag = _toUint8List(localMeta['recovery_tag']);
          final localSalt = _toUint8List(localMeta['recovery_salt']);

          final backupWrap = _toUint8List(backupMeta['recovery_wrapped_key']);
          final backupIv = _toUint8List(backupMeta['recovery_iv']);
          final backupTag = _toUint8List(backupMeta['recovery_tag']);
          final backupSalt = _toUint8List(backupMeta['recovery_salt']);

          if (localWrap != null &&
              localIv != null &&
              localTag != null &&
              localSalt != null &&
              backupWrap != null &&
              backupIv != null &&
              backupTag != null &&
              backupSalt != null) {
            try {
              final localKey = await RecoveryKeyService.unwrapVaultKey(
                wrappedVaultKey: localWrap,
                iv: localIv,
                tag: localTag,
                recoveryKeyBytes: rootKeyBytes,
                salt: localSalt,
              );
              final backupKey = await RecoveryKeyService.unwrapVaultKey(
                wrappedVaultKey: backupWrap,
                iv: backupIv,
                tag: backupTag,
                recoveryKeyBytes: rootKeyBytes,
                salt: backupSalt,
              );
              if (RecoveryKeyService.constantTimeEquals(localKey, backupKey)) {
                canRestoreLockedNotes = true;
              }
            } catch (_) {
              canRestoreLockedNotes = false;
            }
          }
        }
      }

      // 3. Notes: insert missing by ID, never overwrite existing
      for (final note in manifest.notes) {
        final id = note['id'] as String?;
        if (id == null) continue;

        final existing = await txn.query('notes', where: 'id = ?', whereArgs: [id]);
        if (existing.isNotEmpty) {
          skippedNotes++;
          continue;
        }

        final isLocked = (note['is_locked'] == 1);
        final normalizedNote = _normalizeRow(note);
        if (isLocked) {
          if (canRestoreLockedNotes) {
            await txn.insert('notes', normalizedNote, conflictAlgorithm: ConflictAlgorithm.ignore);
            addedNotes++;
          } else {
            lockedNotesSkipped++;
          }
        } else {
          await txn.insert('notes', normalizedNote, conflictAlgorithm: ConflictAlgorithm.ignore);
          addedNotes++;
        }

        if (failRestoreForTesting && addedNotes >= 1) {
          throw StateError('Simulated midway restore transaction failure.');
        }
      }

      // 4. Store the derived backupSubkey in app_settings after successful restore (B5)
      await txn.insert(
        'app_settings',
        {
          'key': 'backup_subkey',
          'value': base64Encode(backupSubkey),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 5. Restore missing allowed settings without modifying any existing settings (Requirement 6)
      for (final entry in manifest.settings.entries) {
        if (BackupManifest.allowedSettingsKeys.contains(entry.key)) {
          await txn.insert(
            'app_settings',
            {
              'key': entry.key,
              'value': entry.value,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      return RestoreSummary(
        addedNotes: addedNotes,
        skippedNotes: skippedNotes,
        addedFolders: addedFolders,
        skippedFolders: skippedFolders,
        lockedNotesSkipped: lockedNotesSkipped,
        vaultAdopted: vaultAdopted,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // BACKGROUND ISOLATE HELPERS (C)
  // ---------------------------------------------------------------------------

  /// Helper for testing and direct encryption of manifest bytes.
  static Future<Uint8List> encryptManifestToBytes({
    required Uint8List manifestBytes,
    required Uint8List backupSubkey,
  }) async {
    final jsonString = utf8.decode(manifestBytes);
    return _isolateCreateBackup({
      'jsonString': jsonString,
      'backupSubkey': backupSubkey,
    });
  }

  /// Helper for testing and direct decryption of container bytes.
  static Future<BackupManifest> decryptContainerToManifest({
    required Uint8List containerBytes,
    required String recoveryKeyString,
  }) async {
    if (containerBytes.length > maxFileSizeBytes) {
      throw const BackupOversizeException();
    }
    if (containerBytes.length < headerLength + 16) {
      throw const BackupSecurityException();
    }
    for (int i = 0; i < magicBytes.length; i++) {
      if (containerBytes[i] != magicBytes[i]) {
        throw const BackupSecurityException();
      }
    }
    if (containerBytes[4] > currentFormatVersion) {
      throw const BackupUnsupportedVersionException();
    }

    final rootKeyBytes = RecoveryKeyService.decodeKey(recoveryKeyString);
    final backupSubkey = await RecoveryKeyService.deriveBackupSubkey(rootKeyBytes);

    final manifest = await _isolateDecryptAndParse({
      'backupBytes': containerBytes,
      'backupSubkey': backupSubkey,
    });
    manifest.validate();
    return manifest;
  }

  /// Worker isolate function for creating compressed, encrypted backup bytes.
  static Future<Uint8List> _isolateCreateBackup(Map<String, dynamic> args) async {
    final jsonString = args['jsonString'] as String;
    final backupSubkey = args['backupSubkey'] as Uint8List;

    // 1. Gzip compression
    final rawBytes = utf8.encode(jsonString);
    final compressedBytes = gzip.encode(rawBytes);

    // 2. Generate random 16B salt and 12B nonce
    final random = Random.secure();
    final salt = Uint8List(saltBytesLength);
    for (int i = 0; i < saltBytesLength; i++) {
      salt[i] = random.nextInt(256);
    }

    final nonce = Uint8List(nonceBytesLength);
    for (int i = 0; i < nonceBytesLength; i++) {
      nonce[i] = random.nextInt(256);
    }

    // 3. Build 33-byte AAD header: [ 'L','L','B','K', 0x01, ...salt, ...nonce ]
    final header = Uint8List(headerLength);
    header.setRange(0, 4, magicBytes);
    header[4] = currentFormatVersion;
    header.setRange(5, 5 + saltBytesLength, salt);
    header.setRange(5 + saltBytesLength, headerLength, nonce);

    // 4. Derive file key using HKDF-SHA256
    final fileKey = await RecoveryKeyService.deriveBackupFileKey(
      backupSubkey: backupSubkey,
      fileSalt: salt,
    );

    // 5. Encrypt with AES-256-GCM using header as AAD
    final aesGcm = AesGcm.with256bits();
    final box = await aesGcm.encrypt(
      compressedBytes,
      secretKey: SecretKey(fileKey),
      nonce: nonce,
      aad: header,
    );

    final result = Uint8List(headerLength + box.cipherText.length + box.mac.bytes.length);
    result.setRange(0, headerLength, header);
    result.setRange(headerLength, headerLength + box.cipherText.length, box.cipherText);
    result.setRange(headerLength + box.cipherText.length, result.length, box.mac.bytes);
    return result;
  }

  /// Worker isolate function for decrypting, validating AAD, decompressing with 64 MB cap,
  /// and parsing the BackupManifest.
  static Future<BackupManifest> _isolateDecryptAndParse(Map<String, dynamic> args) async {
    final backupBytes = args['backupBytes'] as Uint8List;
    final backupSubkey = args['backupSubkey'] as Uint8List;

    // Header extraction
    final header = backupBytes.sublist(0, headerLength);
    final salt = backupBytes.sublist(5, 5 + saltBytesLength);
    final nonce = backupBytes.sublist(5 + saltBytesLength, headerLength);
    // Extract ciphertext and 16-byte MAC tag
    final cipherTextLength = backupBytes.length - headerLength - 16;
    final cipherText = backupBytes.sublist(headerLength, headerLength + cipherTextLength);
    final macBytes = backupBytes.sublist(headerLength + cipherTextLength);

    // Derive file key
    final fileKey = await RecoveryKeyService.deriveBackupFileKey(
      backupSubkey: backupSubkey,
      fileSalt: salt,
    );

    // Decrypt AES-256-GCM
    final aesGcm = AesGcm.with256bits();

    List<int> compressedBytes;
    try {
      compressedBytes = await aesGcm.decrypt(
        SecretBox(
          cipherText,
          nonce: nonce,
          mac: Mac(macBytes),
        ),
        secretKey: SecretKey(fileKey),
        aad: header,
      );
    } catch (_) {
      throw const BackupSecurityException('Wrong recovery key or damaged file.');
    }

    // Decompress gzip with 64 MB cap (C)
    final decompressedBytes = _safeGzipDecode(compressedBytes, maxDecompressedSizeBytes);
    final jsonString = utf8.decode(decompressedBytes);
    final manifest = BackupManifest.fromJsonString(jsonString);
    manifest.validate();
    return manifest;
  }

  /// Decompresses gzip bytes in small chunks, counting every output chunk as it arrives
  /// and throwing [BackupDecompressionBombException] the moment [maxBytes] is exceeded (Requirement 1).
  static Uint8List _safeGzipDecode(List<int> compressed, int maxBytes) {
    final outSink = _CappedDecompressionSink(maxBytes);
    final inSink = gzip.decoder.startChunkedConversion(outSink);

    const int chunkSize = 16 * 1024;
    try {
      for (int i = 0; i < compressed.length; i += chunkSize) {
        final end = (i + chunkSize < compressed.length) ? i + chunkSize : compressed.length;
        inSink.add(compressed.sublist(i, end));
      }
      inSink.close();
    } catch (e) {
      if (e is BackupDecompressionBombException) rethrow;
      throw const FormatException('Invalid or corrupted compressed backup payload.');
    }

    return outSink.builder.takeBytes();
  }

  @visibleForTesting
  static Uint8List safeGzipDecodeForTesting(List<int> compressed, int maxBytes) =>
      _safeGzipDecode(compressed, maxBytes);
}
