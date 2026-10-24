import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../../core/database/app_database.dart';
import '../domain/checklist_item.dart';
import '../domain/folder.dart';
import '../domain/note.dart';
import '../domain/note_sort.dart';

abstract class NotesRepository {
  Future<Note> insertNote(Note note);
  Future<void> updateNote(Note note);

  /// Partial update of content fields only.
  /// Modifies ONLY title, body, checklist_json, is_checklist_mode, word_count, and updated_at.
  /// Preserves all metadata/list-level fields: pin, color, folder, trash, archive, lock.
  Future<void> updateNoteContent({
    required String id,
    required String title,
    required String body,
    String? checklistJson,
    bool? isChecklistMode,
    required int wordCount,
    int? updatedAt,
  });

  Future<Note?> getNoteById(String id);
  Future<List<Note>> getActiveNotes({
    bool includeArchived = false,
    String? folderId,
    NoteSortOption? sortOption,
  });

  /// SQLite LIKE search escaping % and _ with ESCAPE '\'.
  /// Excludes archived notes unless [includeArchived] is true.
  Future<List<Note>> searchNotes(
    String query, {
    bool includeArchived = false,
    String? folderId,
    NoteSortOption? sortOption,
  });

  Future<List<Note>> getArchivedNotes({NoteSortOption? sortOption});
  Future<List<Note>> getTrashedNotes();

  Future<void> trashNote(String id);
  Future<void> trashNotes(List<String> ids);
  Future<void> restoreNote(String id);
  Future<void> restoreNotes(List<String> ids);
  Future<void> deleteNotePermanently(String id);
  Future<void> deleteNotesPermanently(List<String> ids);
  Future<void> emptyTrash();

  /// Purges notes in trash older than [retentionDays] (default 30 days).
  Future<int> purgeExpiredTrash({int retentionDays = 30});

  /// Purges phantom notes where both title and body are empty whitespace.
  Future<int> purgeEmptyNotes();

  Future<void> setPinned(String id, bool isPinned);
  Future<void> setPinnedMultiple(List<String> ids, bool isPinned);
  Future<void> setColorLabel(String id, int colorLabel);
  Future<void> archiveNote(String id);
  Future<void> archiveNotes(List<String> ids);
  Future<void> unarchiveNote(String id);
  Future<void> unarchiveNotes(List<String> ids);
  Future<void> moveNotesToFolder(List<String> ids, String? folderId);

  // Folders
  Future<List<Folder>> getFolders();
  Future<Folder> createFolder(String name, {int? color});
  Future<void> renameFolder(String id, String newName);
  Future<void> deleteFolder(String id);

  // Locked Notes (M4)
  Future<void> lockNote(String noteId, Uint8List vaultKey, {int? expectedUpdatedAt});
  Future<void> unlockNote(String noteId, Uint8List vaultKey);
  Future<void> updateLockedNoteContent({
    required String id,
    required String title,
    required String body,
    String? checklistJson,
    bool? isChecklistMode,
    required Uint8List vaultKey,
    int? updatedAt,
  });
  Future<List<Note>> getLockedNotes(Uint8List vaultKey);
  Future<Note?> getLockedNoteById(String id, Uint8List vaultKey);
  Future<void> deleteLockedNotePermanently(String id);
}

class SqlNotesRepository implements NotesRepository {
  final AppDatabase appDatabase;

  SqlNotesRepository({required this.appDatabase});

  Database get _db => appDatabase.database;

  /// Helper to escape %, _, and \ for SQLite LIKE queries.
  static String escapeLikePattern(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  @override
  Future<Note> insertNote(Note note) async {
    await _db.insert(
      'notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    return note;
  }

  @override
  Future<void> updateNote(Note note) async {
    final updatedNote = note.copyWith(
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final count = await _db.update(
      'notes',
      updatedNote.toMap(),
      where: 'id = ? AND is_locked = 0',
      whereArgs: [note.id],
    );
    if (count == 0) {
      throw StateError('Note with id ${note.id} does not exist or is locked.');
    }
  }

  @override
  Future<void> updateNoteContent({
    required String id,
    required String title,
    required String body,
    String? checklistJson,
    bool? isChecklistMode,
    required int wordCount,
    int? updatedAt,
  }) async {
    final now = updatedAt ?? DateTime.now().millisecondsSinceEpoch;
    final Map<String, dynamic> values = {
      'title': title,
      'body': body,
      'checklist_json': checklistJson,
      'word_count': wordCount,
      'updated_at': now,
    };
    if (isChecklistMode != null) {
      values['is_checklist_mode'] = isChecklistMode ? 1 : 0;
    }
    final count = await _db.update(
      'notes',
      values,
      where: 'id = ? AND is_locked = 0',
      whereArgs: [id],
    );
    if (count == 0) {
      throw StateError('Note with id $id does not exist to update.');
    }
  }

  @override
  Future<Note?> getNoteById(String id) async {
    final results = await _db.query(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return Note.fromMap(results.first);
  }

  @override
  Future<List<Note>> getActiveNotes({
    bool includeArchived = false,
    String? folderId,
    NoteSortOption? sortOption,
  }) async {
    String whereClause = 'trashed_at IS NULL AND is_locked = 0';
    final List<dynamic> whereArgs = [];

    if (!includeArchived) {
      whereClause += ' AND is_archived = 0';
    }

    if (folderId != null) {
      whereClause += ' AND folder_id = ?';
      whereArgs.add(folderId);
    }

    final orderBy = (sortOption ?? const NoteSortOption()).sqlOrderBy;

    final results = await _db.query(
      'notes',
      where: whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: orderBy,
    );

    return results.map(Note.fromMap).toList();
  }

  @override
  Future<List<Note>> searchNotes(
    String query, {
    bool includeArchived = false,
    String? folderId,
    NoteSortOption? sortOption,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return getActiveNotes(
        includeArchived: includeArchived,
        folderId: folderId,
        sortOption: sortOption,
      );
    }

    // Escape special SQLite LIKE characters
    final escaped = escapeLikePattern(trimmed);
    final matchPattern = '%$escaped%';

    String whereClause =
        "trashed_at IS NULL AND is_locked = 0 AND (title LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\')";
    final List<dynamic> whereArgs = [matchPattern, matchPattern];

    if (!includeArchived) {
      whereClause += ' AND is_archived = 0';
    }

    if (folderId != null) {
      whereClause += ' AND folder_id = ?';
      whereArgs.add(folderId);
    }

    final orderBy = (sortOption ?? const NoteSortOption()).sqlOrderBy;

    final results = await _db.query(
      'notes',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );

    return results.map(Note.fromMap).toList();
  }

  @override
  Future<List<Note>> getArchivedNotes({NoteSortOption? sortOption}) async {
    final orderBy = (sortOption ?? const NoteSortOption()).sqlOrderBy;
    final results = await _db.query(
      'notes',
      where: 'trashed_at IS NULL AND is_archived = 1 AND is_locked = 0',
      orderBy: orderBy,
    );
    return results.map(Note.fromMap).toList();
  }

  @override
  Future<List<Note>> getTrashedNotes() async {
    final results = await _db.query(
      'notes',
      where: 'trashed_at IS NOT NULL AND is_locked = 0',
      orderBy: 'trashed_at DESC',
    );
    return results.map(Note.fromMap).toList();
  }

  @override
  Future<void> trashNote(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'notes',
      {'trashed_at': now, 'updated_at': now},
      where: 'id = ? AND is_locked = 0',
      whereArgs: [id],
    );
  }

  @override
  Future<void> trashNotes(List<String> ids) async {
    if (ids.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'notes',
          {'trashed_at': now, 'updated_at': now},
          where: 'id = ? AND is_locked = 0',
          whereArgs: [id],
        );
      }
    });
  }

  @override
  Future<void> restoreNote(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'notes',
      {'trashed_at': null, 'updated_at': now},
      where: 'id = ? AND is_locked = 0',
      whereArgs: [id],
    );
  }

  @override
  Future<void> restoreNotes(List<String> ids) async {
    if (ids.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'notes',
          {'trashed_at': null, 'updated_at': now},
          where: 'id = ? AND is_locked = 0',
          whereArgs: [id],
        );
      }
    });
  }

  @override
  Future<void> deleteNotePermanently(String id) async {
    await _db.delete(
      'notes',
      where: 'id = ? AND is_locked = 0',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteNotesPermanently(List<String> ids) async {
    if (ids.isEmpty) return;
    await _db.transaction((txn) async {
      for (final id in ids) {
        await txn.delete(
          'notes',
          where: 'id = ? AND is_locked = 0',
          whereArgs: [id],
        );
      }
    });
  }

  @override
  Future<void> emptyTrash() async {
    await _db.delete(
      'notes',
      where: 'trashed_at IS NOT NULL AND is_locked = 0',
    );
  }

  @override
  Future<int> purgeExpiredTrash({int retentionDays = 30}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final retentionMillis = retentionDays * 24 * 60 * 60 * 1000;
    final threshold = now - retentionMillis;
    return await _db.delete(
      'notes',
      where: 'trashed_at IS NOT NULL AND trashed_at < ? AND is_locked = 0',
      whereArgs: [threshold],
    );
  }

  @override
  Future<void> setPinned(String id, bool isPinned) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'notes',
      {'is_pinned': isPinned ? 1 : 0, 'updated_at': now},
      where: 'id = ? AND is_locked = 0',
      whereArgs: [id],
    );
  }

  @override
  Future<void> setPinnedMultiple(List<String> ids, bool isPinned) async {
    if (ids.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'notes',
          {'is_pinned': isPinned ? 1 : 0, 'updated_at': now},
          where: 'id = ? AND is_locked = 0',
          whereArgs: [id],
        );
      }
    });
  }

  @override
  Future<void> setColorLabel(String id, int colorLabel) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'notes',
      {'color_label': colorLabel, 'updated_at': now},
      where: 'id = ? AND is_locked = 0',
      whereArgs: [id],
    );
  }

  @override
  Future<void> archiveNote(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'notes',
      {'is_archived': 1, 'updated_at': now},
      where: 'id = ? AND is_locked = 0',
      whereArgs: [id],
    );
  }

  @override
  Future<void> archiveNotes(List<String> ids) async {
    if (ids.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'notes',
          {'is_archived': 1, 'updated_at': now},
          where: 'id = ? AND is_locked = 0',
          whereArgs: [id],
        );
      }
    });
  }

  @override
  Future<void> unarchiveNote(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'notes',
      {'is_archived': 0, 'updated_at': now},
      where: 'id = ? AND is_locked = 0',
      whereArgs: [id],
    );
  }

  @override
  Future<void> unarchiveNotes(List<String> ids) async {
    if (ids.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'notes',
          {'is_archived': 0, 'updated_at': now},
          where: 'id = ? AND is_locked = 0',
          whereArgs: [id],
        );
      }
    });
  }

  @override
  Future<void> moveNotesToFolder(List<String> ids, String? folderId) async {
    if (ids.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((txn) async {
      for (final id in ids) {
        await txn.update(
          'notes',
          {'folder_id': folderId, 'updated_at': now},
          where: 'id = ? AND is_locked = 0',
          whereArgs: [id],
        );
      }
    });
  }

  // Folders Implementation
  @override
  Future<List<Folder>> getFolders() async {
    final results = await _db.query(
      'folders',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return results.map(Folder.fromMap).toList();
  }

  @override
  Future<Folder> createFolder(String name, {int? color}) async {
    final folder = Folder.create(name: name.trim(), color: color);
    await _db.insert('folders', folder.toMap());
    return folder;
  }

  @override
  Future<void> renameFolder(String id, String newName) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      'folders',
      {'name': newName.trim(), 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteFolder(String id) async {
    // Foreign key constraint `ON DELETE SET NULL` on `notes.folder_id` automatically
    // assigns all notes previously in this folder to NULL ("No folder").
    await _db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<int> purgeEmptyNotes() async {
    // A note is empty only when title and body are blank AND every checklist item is blank.
    // Locked notes (is_locked = 1) are strictly preserved and never touched.
    // Runs in a single transaction.
    return await _db.transaction<int>((txn) async {
      final candidates = await txn.query(
        'notes',
        columns: ['id', 'title', 'body', 'checklist_json'],
        where: "(trim(title) = '' OR title IS NULL) AND (trim(body) = '' OR body IS NULL) AND is_locked = 0",
      );

      final idsToDelete = <String>[];
      for (final row in candidates) {
        final checklistJson = row['checklist_json'] as String?;
        if (checklistJson == null || checklistJson.trim().isEmpty) {
          idsToDelete.add(row['id'] as String);
        } else {
          final items = ChecklistItem.parseList(checklistJson);
          final hasContent = items.any((item) => item.text.trim().isNotEmpty);
          if (!hasContent) {
            idsToDelete.add(row['id'] as String);
          }
        }
      }

      int deletedCount = 0;
      for (final id in idsToDelete) {
        deletedCount += await txn.delete('notes', where: 'id = ?', whereArgs: [id]);
      }
      return deletedCount;
    });
  }

  // --- Locked Notes Cryptography Implementation ---

  Uint8List _generateRandomIv() {
    final random = Random.secure();
    final iv = Uint8List(12);
    for (int i = 0; i < 12; i++) {
      iv[i] = random.nextInt(256);
    }
    return iv;
  }

  @override
  Future<void> lockNote(String noteId, Uint8List vaultKey, {int? expectedUpdatedAt}) async {
    final note = await getNoteById(noteId);
    if (note == null || note.isLocked) return;

    if (expectedUpdatedAt != null && note.updatedAt != expectedUpdatedAt) {
      throw StateError('Note was modified concurrently while locking. Please reload and try again.');
    }

    final payload = jsonEncode({
      'title': note.title,
      'body': note.body,
      'checklist_json': note.checklistJson,
      'is_checklist_mode': note.isChecklistMode,
    });
    final payloadBytes = utf8.encode(payload);
    final iv = _generateRandomIv();
    final aad = utf8.encode('$noteId:v${note.payloadFormatVersion}');

    final aesGcm = AesGcm.with256bits();
    final secretBox = await aesGcm.encrypt(
      payloadBytes,
      secretKey: SecretKey(vaultKey),
      nonce: iv,
      aad: aad,
    );

    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction((txn) async {
      final rowsUpdated = await txn.update(
        'notes',
        {
          'encrypted_payload': secretBox.cipherText,
          'payload_iv': iv,
          'payload_tag': secretBox.mac.bytes,
          'is_locked': 1,
          'title': '',
          'body': '',
          'checklist_json': null,
          'word_count': 0,
          'folder_id': null,
          'is_pinned': 0,
          'is_archived': 0,
          'color_label': 0,
          'updated_at': now,
        },
        where: 'id = ? AND updated_at = ? AND is_locked = 0',
        whereArgs: [noteId, note.updatedAt],
      );
      if (rowsUpdated == 0) {
        throw StateError('Note was modified concurrently while locking. Please reload and try again.');
      }
    });
  }

  @override
  Future<void> unlockNote(String noteId, Uint8List vaultKey) async {
    final row = (await _db.query('notes', where: 'id = ?', whereArgs: [noteId])).firstOrNull;
    if (row == null || row['is_locked'] != 1) return;

    final cipherText = row['encrypted_payload'] as Uint8List;
    final iv = row['payload_iv'] as Uint8List;
    final tag = row['payload_tag'] as Uint8List;
    final version = row['payload_format_version'] as int? ?? 1;
    final aad = utf8.encode('$noteId:v$version');

    final aesGcm = AesGcm.with256bits();
    final decryptedBytes = await aesGcm.decrypt(
      SecretBox(cipherText, nonce: iv, mac: Mac(tag)),
      secretKey: SecretKey(vaultKey),
      aad: aad,
    );

    final map = jsonDecode(utf8.decode(decryptedBytes)) as Map<String, dynamic>;
    final title = map['title'] as String? ?? '';
    final body = map['body'] as String? ?? '';
    final checklistJson = map['checklist_json'] as String?;
    final isChecklistMode = (map['is_checklist_mode'] as bool?) ?? false;

    int count;
    if (isChecklistMode && checklistJson != null) {
      count = ChecklistItem.calculateWordCount(ChecklistItem.parseList(checklistJson));
    } else {
      count = Note.calculateWordCount(body);
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    await _db.transaction((txn) async {
      await txn.update(
        'notes',
        {
          'title': title,
          'body': body,
          'checklist_json': checklistJson,
          'is_checklist_mode': isChecklistMode ? 1 : 0,
          'word_count': count,
          'is_locked': 0,
          'encrypted_payload': null,
          'payload_iv': null,
          'payload_tag': null,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [noteId],
      );
    });
  }

  @override
  Future<void> updateLockedNoteContent({
    required String id,
    required String title,
    required String body,
    String? checklistJson,
    bool? isChecklistMode,
    required Uint8List vaultKey,
    int? updatedAt,
  }) async {
    final row = (await _db.query('notes', where: 'id = ?', whereArgs: [id])).firstOrNull;
    if (row == null || row['is_locked'] != 1) {
      throw StateError('Note with id $id does not exist or is not locked.');
    }

    final version = row['payload_format_version'] as int? ?? 1;
    final payload = jsonEncode({
      'title': title,
      'body': body,
      'checklist_json': checklistJson,
      'is_checklist_mode': isChecklistMode ?? false,
    });
    final payloadBytes = utf8.encode(payload);
    final iv = _generateRandomIv();
    final aad = utf8.encode('$id:v$version');

    final aesGcm = AesGcm.with256bits();
    final secretBox = await aesGcm.encrypt(
      payloadBytes,
      secretKey: SecretKey(vaultKey),
      nonce: iv,
      aad: aad,
    );

    final now = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

    await _db.update(
      'notes',
      {
        'encrypted_payload': secretBox.cipherText,
        'payload_iv': iv,
        'payload_tag': secretBox.mac.bytes,
        'updated_at': now,
        'title': '',
        'body': '',
        'checklist_json': null,
        'word_count': 0,
      },
      where: 'id = ? AND is_locked = 1',
      whereArgs: [id],
    );
  }

  @override
  Future<List<Note>> getLockedNotes(Uint8List vaultKey) async {
    final rows = await _db.query(
      'notes',
      where: 'is_locked = 1',
      orderBy: 'updated_at DESC',
    );

    final aesGcm = AesGcm.with256bits();
    final notes = <Note>[];

    for (final row in rows) {
      try {
        final id = row['id'] as String;
        final cipherText = row['encrypted_payload'] as Uint8List;
        final iv = row['payload_iv'] as Uint8List;
        final tag = row['payload_tag'] as Uint8List;
        final version = row['payload_format_version'] as int? ?? 1;
        final aad = utf8.encode('$id:v$version');

        final decryptedBytes = await aesGcm.decrypt(
          SecretBox(cipherText, nonce: iv, mac: Mac(tag)),
          secretKey: SecretKey(vaultKey),
          aad: aad,
        );

        final map = jsonDecode(utf8.decode(decryptedBytes)) as Map<String, dynamic>;
        final title = map['title'] as String? ?? '';
        final body = map['body'] as String? ?? '';
        final checklistJson = map['checklist_json'] as String?;
        final isChecklistMode = (map['is_checklist_mode'] as bool?) ?? false;

        int count;
        if (isChecklistMode && checklistJson != null) {
          count = ChecklistItem.calculateWordCount(ChecklistItem.parseList(checklistJson));
        } else {
          count = Note.calculateWordCount(body);
        }

        notes.add(Note(
          id: id,
          title: title,
          body: body,
          checklistJson: checklistJson,
          isChecklistMode: isChecklistMode,
          folderId: null,
          colorLabel: 0,
          isPinned: false,
          isArchived: false,
          isLocked: true,
          trashedAt: null,
          encryptedPayload: cipherText,
          payloadIv: iv,
          payloadTag: tag,
          payloadFormatVersion: version,
          createdAt: row['created_at'] as int,
          updatedAt: row['updated_at'] as int,
          wordCount: count,
        ));
      } catch (_) {
        // If single note decryption fails, omit it or keep list intact
      }
    }

    return notes;
  }

  @override
  Future<Note?> getLockedNoteById(String id, Uint8List vaultKey) async {
    final rows = await _db.query('notes', where: 'id = ? AND is_locked = 1', whereArgs: [id]);
    if (rows.isEmpty) return null;

    final row = rows.first;
    final cipherText = row['encrypted_payload'] as Uint8List;
    final iv = row['payload_iv'] as Uint8List;
    final tag = row['payload_tag'] as Uint8List;
    final version = row['payload_format_version'] as int? ?? 1;
    final aad = utf8.encode('$id:v$version');

    final aesGcm = AesGcm.with256bits();
    final decryptedBytes = await aesGcm.decrypt(
      SecretBox(cipherText, nonce: iv, mac: Mac(tag)),
      secretKey: SecretKey(vaultKey),
      aad: aad,
    );

    final map = jsonDecode(utf8.decode(decryptedBytes)) as Map<String, dynamic>;
    final title = map['title'] as String? ?? '';
    final body = map['body'] as String? ?? '';
    final checklistJson = map['checklist_json'] as String?;
    final isChecklistMode = (map['is_checklist_mode'] as bool?) ?? false;

    int count;
    if (isChecklistMode && checklistJson != null) {
      count = ChecklistItem.calculateWordCount(ChecklistItem.parseList(checklistJson));
    } else {
      count = Note.calculateWordCount(body);
    }

    return Note(
      id: id,
      title: title,
      body: body,
      checklistJson: checklistJson,
      isChecklistMode: isChecklistMode,
      folderId: null,
      colorLabel: 0,
      isPinned: false,
      isArchived: false,
      isLocked: true,
      trashedAt: null,
      encryptedPayload: cipherText,
      payloadIv: iv,
      payloadTag: tag,
      payloadFormatVersion: version,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
      wordCount: count,
    );
  }

  @override
  Future<void> deleteLockedNotePermanently(String id) async {
    await _db.delete('notes', where: 'id = ? AND is_locked = 1', whereArgs: [id]);
  }
}
