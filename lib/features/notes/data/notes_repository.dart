import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../../core/database/app_database.dart';
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
      where: 'id = ?',
      whereArgs: [note.id],
    );
    if (count == 0) {
      throw StateError('Note with id ${note.id} does not exist to update.');
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
        "trashed_at IS NULL AND is_locked = 0 AND (title LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\' OR checklist_json LIKE ? ESCAPE '\\')";
    final List<dynamic> whereArgs = [matchPattern, matchPattern, matchPattern];

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
}
