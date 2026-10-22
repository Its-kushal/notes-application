import 'dart:io';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'database_key_service.dart';

enum DatabaseStatus {
  uninitialized,
  ready,
  recoveryNeeded,
}

/// Central database manager for Privacy Notes utilizing SQLCipher.
class AppDatabase {
  static const String databaseFileName = 'privacy_notes.db';
  static const int currentDatabaseVersion = 1;

  final DatabaseKeyService _keyService;
  final DatabaseFactory? customFactory;
  final String? customPath;

  Database? _db;
  DatabaseStatus _status = DatabaseStatus.uninitialized;

  AppDatabase({
    DatabaseKeyService? keyService,
    this.customFactory,
    this.customPath,
  }) : _keyService = keyService ?? DatabaseKeyService();

  DatabaseStatus get status => _status;
  Database get database {
    final db = _db;
    if (db == null || !db.isOpen) {
      throw StateError('Database is not initialized or not open.');
    }
    return db;
  }

  /// Resolves the absolute path to the database file.
  Future<String> resolveDatabasePath() async {
    if (customPath != null) return customPath!;
    final factory = customFactory ?? databaseFactory;
    final databasesDir = await factory.getDatabasesPath();
    return '$databasesDir/$databaseFileName';
  }

  /// Initializes and opens the SQLCipher encrypted database.
  /// If the DB file exists on disk but Keystore read fails, sets status to
  /// [DatabaseStatus.recoveryNeeded] without overwriting or deleting any file.
  Future<DatabaseStatus> initialize({String? overridePassword}) async {
    try {
      final dbPath = await resolveDatabasePath();
      final dbFile = File(dbPath);
      final fileExists = await dbFile.exists();

      String rawPassword;
      if (overridePassword != null) {
        rawPassword = overridePassword;
      } else {
        // If file exists, we MUST NOT generate a new key if Keystore is missing/inaccessible
        try {
          rawPassword = await _keyService.getOrCreateRawDatabaseKey(
            createNewIfMissing: !fileExists,
          );
        } catch (_) {
          // Hardware Keystore read failed on an existing database
          _status = DatabaseStatus.recoveryNeeded;
          return _status;
        }
      }

      final factory = customFactory ?? databaseFactory;
      final options = SqlCipherOpenDatabaseOptions(
        version: currentDatabaseVersion,
        password: rawPassword,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON;');
        },
        onCreate: (db, version) async {
          await createSchemaV1(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await db.transaction((txn) async {
            for (int v = oldVersion + 1; v <= newVersion; v++) {
              await migrateVersion(txn, v);
            }
          });
        },
        onDowngrade: (db, oldVersion, newVersion) {
          throw UnsupportedError(
            'Database downgrade from version $oldVersion to $newVersion is prohibited.',
          );
        },
      );

      _db = await factory.openDatabase(dbPath, options: options);

      _status = DatabaseStatus.ready;
      return _status;
    } catch (e) {
      // If opening failed on existing file
      final dbPath = await resolveDatabasePath();
      if (await File(dbPath).exists()) {
        _status = DatabaseStatus.recoveryNeeded;
        return _status;
      }
      rethrow;
    }
  }

  /// Applies incremental database migrations using the provided transaction [txn].
  static Future<void> migrateVersion(DatabaseExecutor txn, int version) async {
    switch (version) {
      // Future schema migration steps execute queries on txn here:
      // case 2:
      //   await txn.execute(...);
      //   break;
    }
  }

  /// Creates schema version 1.
  static Future<void> createSchemaV1(DatabaseExecutor db) async {
    // 1. Vault Metadata Table
    await db.execute('''
      CREATE TABLE vault_metadata (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        salt BLOB NOT NULL,
        kdf_algorithm TEXT NOT NULL,
        kdf_iterations INTEGER NOT NULL,
        wrapped_vault_key BLOB NOT NULL,
        wrapped_vault_key_iv BLOB NOT NULL,
        wrapped_vault_key_tag BLOB NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    // 2. Folders Table
    await db.execute('''
      CREATE TABLE folders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    // 3. Notes Table with CHECK constraint
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        checklist_json TEXT,
        is_checklist_mode INTEGER NOT NULL DEFAULT 0,
        folder_id TEXT REFERENCES folders(id) ON DELETE SET NULL,
        color_label INTEGER NOT NULL DEFAULT 0,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        is_locked INTEGER NOT NULL DEFAULT 0,
        trashed_at INTEGER,
        encrypted_payload BLOB,
        payload_iv BLOB,
        payload_tag BLOB,
        payload_format_version INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        word_count INTEGER NOT NULL DEFAULT 0,
        CHECK (
          (is_locked = 1 AND encrypted_payload IS NOT NULL AND payload_iv IS NOT NULL AND payload_tag IS NOT NULL AND title = '' AND body = '' AND checklist_json IS NULL AND word_count = 0)
          OR
          (is_locked = 0 AND encrypted_payload IS NULL AND payload_iv IS NULL AND payload_tag IS NULL)
        )
      );
    ''');

    // Indexes
    await db.execute('''
      CREATE INDEX idx_notes_trashed_pinned_updated ON notes(trashed_at, is_pinned, updated_at DESC);
    ''');
    await db.execute('''
      CREATE INDEX idx_notes_folder ON notes(folder_id);
    ''');

    // 4. App Settings Table
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    await db.execute('PRAGMA user_version = $currentDatabaseVersion;');
  }

  /// Closes database connection cleanly.
  Future<void> close() async {
    final db = _db;
    if (db != null && db.isOpen) {
      await db.close();
      _db = null;
      _status = DatabaseStatus.uninitialized;
    }
  }
}
