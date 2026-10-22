import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:privacy_notes/core/database/app_database.dart';
import 'package:privacy_notes/features/notes/data/notes_repository.dart';
import 'package:privacy_notes/features/notes/domain/note.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Database Schema & Repository CRUD Tests', () {
    late AppDatabase appDb;
    late SqlNotesRepository repository;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      final status = await appDb.initialize(overridePassword: 'test_password');
      expect(status, DatabaseStatus.ready);
      repository = SqlNotesRepository(appDatabase: appDb);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('Insert, read, update, and active notes query', () async {
      final note1 = Note.create(title: 'Grocery List', body: 'Milk, Eggs, Bread');
      await repository.insertNote(note1);

      final fetched = await repository.getNoteById(note1.id);
      expect(fetched, isNotNull);
      expect(fetched!.title, 'Grocery List');
      expect(fetched.body, 'Milk, Eggs, Bread');
      expect(fetched.wordCount, 3);
      expect(fetched.isTrashed, isFalse);

      // Update
      final updatedNote = fetched.copyWith(body: 'Milk, Eggs, Bread, Butter');
      await repository.updateNote(updatedNote);

      final refetched = await repository.getNoteById(note1.id);
      expect(refetched!.body, 'Milk, Eggs, Bread, Butter');
      expect(refetched.wordCount, 4);

      // List active
      final activeNotes = await repository.getActiveNotes();
      expect(activeNotes.length, 1);
      expect(activeNotes.first.id, note1.id);
    });

    test('Trash, restore, and permanent deletion with trashed_at', () async {
      final note = Note.create(title: 'Trash Me', body: 'Temporary content');
      await repository.insertNote(note);

      expect((await repository.getActiveNotes()).length, 1);

      // Move to trash
      await repository.trashNote(note.id);
      final trashedNote = await repository.getNoteById(note.id);
      expect(trashedNote!.isTrashed, isTrue);
      expect(trashedNote.trashedAt, isNotNull);
      expect((await repository.getActiveNotes()).isEmpty, isTrue);

      // Restore
      await repository.restoreNote(note.id);
      final restored = await repository.getNoteById(note.id);
      expect(restored!.isTrashed, isFalse);
      expect(restored.trashedAt, isNull);
      expect((await repository.getActiveNotes()).length, 1);

      // Permanent delete
      await repository.deleteNotePermanently(note.id);
      expect(await repository.getNoteById(note.id), isNull);
    });

    test('CHECK constraint: locked notes MUST have empty title/body and non-null payload', () async {
      final db = appDb.database;

      // 1. Valid unlocked note succeeds
      await db.insert('notes', {
        'id': 'unlocked-valid-1',
        'title': 'Normal Note',
        'body': 'Normal Body',
        'is_locked': 0,
        'encrypted_payload': null,
        'payload_iv': null,
        'payload_tag': null,
        'created_at': 1000,
        'updated_at': 1000,
        'word_count': 2,
      });

      // 2. Unlocked note with encrypted_payload violates CHECK constraint
      expect(
        () async => await db.insert('notes', {
          'id': 'unlocked-invalid-payload',
          'title': 'Normal Note',
          'body': 'Normal Body',
          'is_locked': 0,
          'encrypted_payload': Uint8List.fromList([1, 2, 3]),
          'payload_iv': null,
          'payload_tag': null,
          'created_at': 1000,
          'updated_at': 1000,
          'word_count': 2,
        }),
        throwsA(isA<DatabaseException>()),
      );

      // 3. Locked note with non-empty title violates CHECK constraint
      expect(
        () async => await db.insert('notes', {
          'id': 'locked-invalid-title',
          'title': 'Leaked Title',
          'body': '',
          'is_locked': 1,
          'encrypted_payload': Uint8List.fromList([1, 2, 3]),
          'payload_iv': Uint8List.fromList([1, 2, 3]),
          'payload_tag': Uint8List.fromList([1, 2, 3]),
          'created_at': 1000,
          'updated_at': 1000,
          'word_count': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );

      // 4. Locked note with non-empty body violates CHECK constraint
      expect(
        () async => await db.insert('notes', {
          'id': 'locked-invalid-body',
          'title': '',
          'body': 'Leaked Body',
          'is_locked': 1,
          'encrypted_payload': Uint8List.fromList([1, 2, 3]),
          'payload_iv': Uint8List.fromList([1, 2, 3]),
          'payload_tag': Uint8List.fromList([1, 2, 3]),
          'created_at': 1000,
          'updated_at': 1000,
          'word_count': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );

      // 5. Locked note with null payload violates CHECK constraint
      expect(
        () async => await db.insert('notes', {
          'id': 'locked-invalid-null-payload',
          'title': '',
          'body': '',
          'is_locked': 1,
          'encrypted_payload': null,
          'payload_iv': Uint8List.fromList([1, 2, 3]),
          'payload_tag': Uint8List.fromList([1, 2, 3]),
          'created_at': 1000,
          'updated_at': 1000,
          'word_count': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );

      // 6. Valid locked note succeeds
      await db.insert('notes', {
        'id': 'locked-valid-1',
        'title': '',
        'body': '',
        'checklist_json': null,
        'is_locked': 1,
        'encrypted_payload': Uint8List.fromList([1, 2, 3, 4]),
        'payload_iv': Uint8List.fromList([10, 11, 12]),
        'payload_tag': Uint8List.fromList([20, 21, 22]),
        'created_at': 1000,
        'updated_at': 1000,
        'word_count': 0,
      });

      final locked = await repository.getNoteById('locked-valid-1');
      expect(locked, isNotNull);
      expect(locked!.isLocked, isTrue);
      expect(locked.title, '');
      expect(locked.body, '');
    });

    test('Foreign Keys: ON DELETE SET NULL triggers when folder is deleted', () async {
      final db = appDb.database;

      // Create folder
      await db.insert('folders', {
        'id': 'folder-work',
        'name': 'Work Projects',
        'color': 0xFF0D9488,
        'created_at': 1000,
        'updated_at': 1000,
      });

      // Create note in folder
      final noteInFolder = Note.create(
        title: 'Project Roadmap',
        body: 'Q4 deliverables',
        folderId: 'folder-work',
      );
      await repository.insertNote(noteInFolder);

      final fetchedBefore = await repository.getNoteById(noteInFolder.id);
      expect(fetchedBefore!.folderId, 'folder-work');

      // Delete the folder
      await db.delete('folders', where: 'id = ?', whereArgs: ['folder-work']);

      // Note still exists, but folder_id was cleanly set to NULL
      final fetchedAfter = await repository.getNoteById(noteInFolder.id);
      expect(fetchedAfter, isNotNull);
      expect(fetchedAfter!.folderId, isNull);
    });

    test('Search LIKE Scan: ASCII case-insensitivity vs Non-Latin case-sensitivity', () async {
      // Insert ASCII note
      final asciiNote = Note.create(title: 'Weekly Standup Meeting', body: 'Discuss architecture');
      await repository.insertNote(asciiNote);

      // ASCII search is case-insensitive
      final lowerSearch = await repository.searchNotes('meeting');
      expect(lowerSearch.length, 1);
      final upperSearch = await repository.searchNotes('MEETING');
      expect(upperSearch.length, 1);

      // Insert Non-Latin Cyrillic note: 'Заметка' (Uppercase 3)
      final cyrillicNote = Note.create(title: 'Заметка по проекту', body: 'Конфиденциальная информация');
      await repository.insertNote(cyrillicNote);

      // Exact case matches
      final exactCyrillic = await repository.searchNotes('Заметка');
      expect(exactCyrillic.length, 1);

      // SQLite standard LIKE is case-sensitive for non-ASCII characters
      final lowerCyrillic = await repository.searchNotes('заметка');
      expect(lowerCyrillic.isEmpty, isTrue, reason: 'SQLite LIKE is case-sensitive for non-Latin characters');
    });

    test('M1 Fix 1: Search escapes % and _ in LIKE pattern and excludes archived notes by default', () async {
      // 1. Test % escaping
      final percentNote = Note.create(title: 'Get 50% discount now', body: 'Coupon code inside');
      final nonPercentNote = Note.create(title: 'Get 500 discount now', body: 'Coupon code inside');
      await repository.insertNote(percentNote);
      await repository.insertNote(nonPercentNote);

      final percentSearch = await repository.searchNotes('50%');
      expect(percentSearch.length, 1);
      expect(percentSearch.first.id, percentNote.id);

      // 2. Test _ escaping
      final underscoreNote = Note.create(title: 'file_v1.dart', body: 'Source file');
      final nonUnderscoreNote = Note.create(title: 'fileXv1.dart', body: 'Source file');
      await repository.insertNote(underscoreNote);
      await repository.insertNote(nonUnderscoreNote);

      final underscoreSearch = await repository.searchNotes('file_v1');
      expect(underscoreSearch.length, 1);
      expect(underscoreSearch.first.id, underscoreNote.id);

      // 3. Test archived exclusion unless includeArchived is true
      final archivedNote = Note.create(
        title: 'Archived Confidential Plans',
        body: 'Top secret content',
        isArchived: true,
      );
      await repository.insertNote(archivedNote);

      // Search default: excludes archived
      final searchWithoutArchived = await repository.searchNotes('Confidential');
      expect(searchWithoutArchived.isEmpty, isTrue);

      // Search with includeArchived: true: returns archived note
      final searchWithArchived = await repository.searchNotes('Confidential', includeArchived: true);
      expect(searchWithArchived.length, 1);
      expect(searchWithArchived.first.id, archivedNote.id);
    });

    test('M1 Fix 3: Database migration steps use the transaction object (txn)', () async {
      final db = appDb.database;

      await db.transaction((txn) async {
        // Verify txn DatabaseExecutor executes commands within transaction
        await AppDatabase.migrateVersion(txn, 1);
        await txn.execute('CREATE TABLE IF NOT EXISTS _test_migration (id INTEGER PRIMARY KEY);');
        await txn.insert('_test_migration', {'id': 42});
      });

      final result = await db.query('_test_migration');
      expect(result.length, 1);
      expect(result.first['id'], 42);
    });

    test('M2: Folder management and notes filtering', () async {
      final folder1 = await repository.createFolder('Work');
      final folder2 = await repository.createFolder('Personal');

      expect((await repository.getFolders()).length, 2);

      // Create note in folder1
      final note1 = Note.create(title: 'Work Task', body: 'Deliverable 1', folderId: folder1.id);
      final note2 = Note.create(title: 'Gym Routine', body: 'Leg day', folderId: folder2.id);
      final noteNoFolder = Note.create(title: 'Random thought', body: 'Idea');

      await repository.insertNote(note1);
      await repository.insertNote(note2);
      await repository.insertNote(noteNoFolder);

      // Filter by folder1
      final workNotes = await repository.getActiveNotes(folderId: folder1.id);
      expect(workNotes.length, 1);
      expect(workNotes.first.id, note1.id);

      // Notes without folder exist in All notes (folderId: null)
      final allNotes = await repository.getActiveNotes(folderId: null);
      expect(allNotes.length, 3);

      // Rename folder
      await repository.renameFolder(folder1.id, 'Work & Career');
      final renamedFolders = await repository.getFolders();
      expect(renamedFolders.firstWhere((f) => f.id == folder1.id).name, 'Work & Career');

      // Delete folder - note moves to "No folder"
      await repository.deleteFolder(folder1.id);
      final noteAfterDelete = await repository.getNoteById(note1.id);
      expect(noteAfterDelete!.folderId, isNull);
    });

    test('M2: Trash screen retention purge (default 30 days) and empty trash', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final fortyDaysAgo = now - (40 * 24 * 60 * 60 * 1000);
      final tenDaysAgo = now - (10 * 24 * 60 * 60 * 1000);

      // Expired note (40 days old in trash)
      final expired = Note.create(title: 'Old Trashed').copyWith(trashedAt: fortyDaysAgo);
      // Recent note in trash (10 days old)
      final recent = Note.create(title: 'Recent Trashed').copyWith(trashedAt: tenDaysAgo);

      await repository.insertNote(expired);
      await repository.insertNote(recent);

      // Purge 30 days retention
      final purgedCount = await repository.purgeExpiredTrash(retentionDays: 30);
      expect(purgedCount, 1);

      expect(await repository.getNoteById(expired.id), isNull);
      expect(await repository.getNoteById(recent.id), isNotNull);

      // Empty trash deletes all remaining
      await repository.emptyTrash();
      expect((await repository.getTrashedNotes()).isEmpty, isTrue);
    });

    test('P2: Locked note isolation: never appears in active/search/archive/trash queries, immune to bulk actions, empty trash, and retention purge', () async {
      final db = appDb.database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final fiftyDaysAgo = now - (50 * 24 * 60 * 60 * 1000);

      // Create a folder
      final folder = await repository.createFolder('Private Work');

      // Insert valid unlocked note
      final unlockedNote = Note.create(title: 'Unlocked Note', body: 'Normal text', folderId: folder.id);
      await repository.insertNote(unlockedNote);

      // Insert valid locked note per CHECK constraint
      final lockedNoteId = 'locked-note-secret-1';
      await db.insert('notes', {
        'id': lockedNoteId,
        'title': '',
        'body': '',
        'checklist_json': null,
        'is_checklist_mode': 0,
        'folder_id': folder.id,
        'color_label': 0,
        'is_pinned': 0,
        'is_archived': 0,
        'is_locked': 1,
        'trashed_at': fiftyDaysAgo, // Even if it has an old trashed_at timestamp
        'encrypted_payload': Uint8List.fromList([1, 2, 3, 4, 5]),
        'payload_iv': Uint8List.fromList([10, 11, 12]),
        'payload_tag': Uint8List.fromList([20, 21, 22]),
        'payload_format_version': 1,
        'created_at': fiftyDaysAgo,
        'updated_at': fiftyDaysAgo,
        'word_count': 0,
      });

      // 1. Never appears in getActiveNotes (both all and filtered by folder)
      final activeAll = await repository.getActiveNotes();
      expect(activeAll.any((n) => n.id == lockedNoteId), isFalse);
      expect(activeAll.length, 1);
      expect(activeAll.first.id, unlockedNote.id);

      final activeFolder = await repository.getActiveNotes(folderId: folder.id);
      expect(activeFolder.any((n) => n.id == lockedNoteId), isFalse);

      // 2. Never appears in searchNotes (empty query or keyword)
      final searchEmpty = await repository.searchNotes('');
      expect(searchEmpty.any((n) => n.id == lockedNoteId), isFalse);

      final searchWord = await repository.searchNotes('secret');
      expect(searchWord.any((n) => n.id == lockedNoteId), isFalse);

      // 3. Never appears in getArchivedNotes
      final archivedNotes = await repository.getArchivedNotes();
      expect(archivedNotes.any((n) => n.id == lockedNoteId), isFalse);

      // 4. Never appears in getTrashedNotes
      final trashedNotes = await repository.getTrashedNotes();
      expect(trashedNotes.any((n) => n.id == lockedNoteId), isFalse);

      // 5. Bulk actions must NEVER touch locked rows:
      // 5a. Bulk pin
      await repository.setPinnedMultiple([lockedNoteId, unlockedNote.id], true);
      var rawLocked = (await db.query('notes', where: 'id = ?', whereArgs: [lockedNoteId])).first;
      expect(rawLocked['is_pinned'], 0, reason: 'Bulk pin must not touch locked row');

      // 5b. Bulk move to folder
      await repository.moveNotesToFolder([lockedNoteId, unlockedNote.id], null);
      rawLocked = (await db.query('notes', where: 'id = ?', whereArgs: [lockedNoteId])).first;
      expect(rawLocked['folder_id'], folder.id, reason: 'Bulk move must not touch locked row');

      // 5c. Bulk archive
      await repository.archiveNotes([lockedNoteId, unlockedNote.id]);
      rawLocked = (await db.query('notes', where: 'id = ?', whereArgs: [lockedNoteId])).first;
      expect(rawLocked['is_archived'], 0, reason: 'Bulk archive must not touch locked row');

      // 5d. Bulk trash
      await repository.trashNotes([lockedNoteId]);
      rawLocked = (await db.query('notes', where: 'id = ?', whereArgs: [lockedNoteId])).first;
      expect(rawLocked['trashed_at'], fiftyDaysAgo, reason: 'Bulk trash must not update locked row');

      // 5e. Bulk restore
      await repository.restoreNotes([lockedNoteId]);
      rawLocked = (await db.query('notes', where: 'id = ?', whereArgs: [lockedNoteId])).first;
      expect(rawLocked['trashed_at'], fiftyDaysAgo, reason: 'Bulk restore must not clear locked row trashed_at');

      // 5f. Bulk permanent delete
      await repository.deleteNotesPermanently([lockedNoteId]);
      var exists = (await db.query('notes', where: 'id = ?', whereArgs: [lockedNoteId])).isNotEmpty;
      expect(exists, isTrue, reason: 'Bulk delete must not delete locked row');

      // 6. Retention purge must NEVER delete locked row
      final purged = await repository.purgeExpiredTrash(retentionDays: 30);
      expect(purged, 0, reason: 'Retention purge must ignore locked row');
      exists = (await db.query('notes', where: 'id = ?', whereArgs: [lockedNoteId])).isNotEmpty;
      expect(exists, isTrue, reason: 'Retention purge must not delete locked row');

      // 7. Empty trash must NEVER delete locked row
      await repository.emptyTrash();
      exists = (await db.query('notes', where: 'id = ?', whereArgs: [lockedNoteId])).isNotEmpty;
      expect(exists, isTrue, reason: 'Empty trash must not delete locked row');
    });
  });
}
