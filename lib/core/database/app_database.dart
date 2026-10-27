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
  static const int currentDatabaseVersion = 3;

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

  static bool failMigrationForTesting = false;

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

      // D2: Safety backup before schema migration
      if (fileExists && dbPath != inMemoryDatabasePath) {
        try {
          final tempDb = await factory.openDatabase(
            dbPath,
            options: SqlCipherOpenDatabaseOptions(password: rawPassword),
          );
          final versionRows = await tempDb.rawQuery('PRAGMA user_version;');
          final diskVersion = Sqflite.firstIntValue(versionRows) ?? 0;
          await tempDb.close();

          if (diskVersion > 0 && diskVersion < currentDatabaseVersion) {
            await _createMigrationBackup(dbPath, diskVersion, rawPassword, factory);
          }
        } catch (e) {
          _status = DatabaseStatus.recoveryNeeded;
          return _status;
        }
      }

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

      // D3: Startup quick_check integrity verification
      final checkRows = await _db!.rawQuery('PRAGMA quick_check;');
      final quickStatus = checkRows.isNotEmpty ? checkRows.first.values.first?.toString() : null;
      if (quickStatus != 'ok') {
        await _db!.close();
        _db = null;
        _status = DatabaseStatus.recoveryNeeded;
        return _status;
      }

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

  /// Creates a verified safety backup of the database before running schema migrations (D2).
  /// Checkpoints WAL, closes the database, copies to app-private backups directory,
  /// verifies that the copy opens with the same key, and maintains only the last 2 backups.
  static Future<void> _createMigrationBackup(
    String dbPath,
    int diskVersion,
    String password,
    DatabaseFactory factory,
  ) async {
    final dbFile = File(dbPath);
    final backupDir = Directory('${dbFile.parent.path}/backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    // 1. Checkpoint WAL to flush pending journal pages before copying
    try {
      final tempDb = await factory.openDatabase(
        dbPath,
        options: SqlCipherOpenDatabaseOptions(password: password),
      );
      await tempDb.execute('PRAGMA wal_checkpoint(TRUNCATE);');
      await tempDb.close();
    } catch (_) {}

    // 2. Copy database file to backups directory
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final backupPath = '${backupDir.path}/privacy_notes_v${diskVersion}_backup_$timestamp.db';
    await dbFile.copy(backupPath);

    // 3. Verify the copy opens with the exact same SQLCipher key
    final backupDb = await factory.openDatabase(
      backupPath,
      options: SqlCipherOpenDatabaseOptions(password: password),
    );
    final checkRows = await backupDb.rawQuery('PRAGMA quick_check;');
    await backupDb.close();

    final status = checkRows.isNotEmpty ? checkRows.first.values.first?.toString() : null;
    if (status != 'ok') {
      await File(backupPath).delete();
      throw StateError('Migration backup integrity verification failed.');
    }

    // 4. Prune old backups, keeping only the last 2
    final backupFiles = await backupDir
        .list()
        .where((e) => e is File && e.path.endsWith('.db'))
        .cast<File>()
        .toList();
    if (backupFiles.length > 2) {
      backupFiles.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      while (backupFiles.length > 2) {
        final oldest = backupFiles.removeAt(0);
        try {
          await oldest.delete();
        } catch (_) {}
      }
    }
  }

  /// Applies incremental database migrations using the provided transaction [txn].
  static Future<void> migrateVersion(DatabaseExecutor txn, int version) async {
    if (failMigrationForTesting) {
      throw StateError('Simulated migration failure for testing.');
    }
    switch (version) {
      case 2:
        await txn.execute(
          "ALTER TABLE vault_metadata ADD COLUMN credential_type TEXT NOT NULL DEFAULT 'pin';",
        );
        break;
      case 3:
        await txn.execute('ALTER TABLE vault_metadata ADD COLUMN recovery_salt BLOB;');
        await txn.execute('ALTER TABLE vault_metadata ADD COLUMN recovery_wrapped_key BLOB;');
        await txn.execute('ALTER TABLE vault_metadata ADD COLUMN recovery_iv BLOB;');
        await txn.execute('ALTER TABLE vault_metadata ADD COLUMN recovery_tag BLOB;');
        await txn.execute('ALTER TABLE vault_metadata ADD COLUMN recovery_version INTEGER;');
        break;
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
        credential_type TEXT NOT NULL DEFAULT 'pin',
        wrapped_vault_key BLOB NOT NULL,
        wrapped_vault_key_iv BLOB NOT NULL,
        wrapped_vault_key_tag BLOB NOT NULL,
        version INTEGER NOT NULL DEFAULT 1,
        recovery_salt BLOB,
        recovery_wrapped_key BLOB,
        recovery_iv BLOB,
        recovery_tag BLOB,
        recovery_version INTEGER,
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
