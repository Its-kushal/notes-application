import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:privacy_notes/core/database/app_database.dart';
import 'package:privacy_notes/features/notes/data/notes_repository.dart';
import 'package:privacy_notes/features/notes/domain/note.dart';
import 'package:privacy_notes/features/notes/presentation/controllers/notes_providers.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Autosave Unit Tests', () {
    late AppDatabase appDb;
    late SqlNotesRepository repository;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test');
      repository = SqlNotesRepository(appDatabase: appDb);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('Autosave debounces 500ms and saves to database', () async {
      final initialNote = Note.create(title: 'Initial', body: 'Draft text');
      await repository.insertNote(initialNote);

      final notifier = NoteEditorNotifier(repository, initialNote);

      // Edit content
      notifier.updateContent(body: 'Draft text edited');
      expect(notifier.isDirty, isTrue);

      // Verify not saved immediately before debounce expires
      final beforeTimer = await repository.getNoteById(initialNote.id);
      expect(beforeTimer!.body, 'Draft text');

      // Wait 550ms for debounce timer to fire
      await Future.delayed(const Duration(milliseconds: 550));

      // Verify note is saved
      final afterTimer = await repository.getNoteById(initialNote.id);
      expect(afterTimer!.body, 'Draft text edited');
      expect(notifier.isDirty, isFalse);

      notifier.dispose();
    });

    test('Autosave flushes immediately on saveImmediately() without waiting for debounce (pause / back press)', () async {
      final initialNote = Note.create(title: 'Pause Test', body: 'Original content');
      await repository.insertNote(initialNote);

      final notifier = NoteEditorNotifier(repository, initialNote);

      // Edit content
      notifier.updateContent(body: 'Changes made just before backgrounding');
      expect(notifier.isDirty, isTrue);

      // Simulate AppLifecycleState.paused / back press flushing immediately
      await notifier.saveImmediately();

      // Verify database updated instantly (zero milliseconds wait)
      final savedNote = await repository.getNoteById(initialNote.id);
      expect(savedNote!.body, 'Changes made just before backgrounding');
      expect(notifier.isDirty, isFalse);

      notifier.dispose();
    });

    test('M1 Fix 2: Partial UPDATE saves only title/body/checklist/word_count/updated_at and does NOT overwrite list-level changes (pin, color, folder, trash, archive)', () async {
      // Create referenced folders first to satisfy FOREIGN KEY constraint
      final folderWork = await repository.createFolder('Work');
      final folderPersonal = await repository.createFolder('Personal');

      // 1. Create a note with initial list-level metadata
      final initialNote = Note.create(
        title: 'Initial Title',
        body: 'Initial Body',
        folderId: folderWork.id,
        colorLabel: 1, // Red
        isPinned: false,
        isArchived: false,
      );
      await repository.insertNote(initialNote);

      // 2. Open note in editor
      final notifier = NoteEditorNotifier(repository, initialNote);

      // 3. User edits title and body in editor (editor now has dirty state)
      notifier.updateContent(
        title: 'Updated Content Title',
        body: 'Updated Content Body',
      );
      expect(notifier.isDirty, isTrue);

      // 4. Meanwhile, list-level changes happen externally (e.g. from list screen or notification):
      //    User pins note, changes color label to 4 (Emerald), moves to 'folder-personal',
      //    or archives note.
      await repository.setPinned(initialNote.id, true);
      await repository.setColorLabel(initialNote.id, 4);
      await repository.moveNotesToFolder([initialNote.id], folderPersonal.id);
      await repository.archiveNote(initialNote.id);

      // Verify that list-level changes were applied to DB
      final dbBeforeAutosave = await repository.getNoteById(initialNote.id);
      expect(dbBeforeAutosave!.isPinned, isTrue);
      expect(dbBeforeAutosave.colorLabel, 4);
      expect(dbBeforeAutosave.folderId, folderPersonal.id);
      expect(dbBeforeAutosave.isArchived, isTrue);
      expect(dbBeforeAutosave.title, 'Initial Title'); // Content not yet flushed

      // 5. Stale autosave fires from editor!
      await notifier.saveImmediately();
      expect(notifier.isDirty, isFalse);

      // 6. Verify that editor content is saved, BUT NONE of the list-level changes were overwritten!
      final dbAfterAutosave = await repository.getNoteById(initialNote.id);
      expect(dbAfterAutosave, isNotNull);
      // Content updated
      expect(dbAfterAutosave!.title, 'Updated Content Title');
      expect(dbAfterAutosave.body, 'Updated Content Body');
      expect(dbAfterAutosave.wordCount, 3);
      // List-level fields PRESERVED and not overwritten by stale editor state:
      expect(dbAfterAutosave.isPinned, isTrue, reason: 'isPinned was preserved');
      expect(dbAfterAutosave.colorLabel, 4, reason: 'colorLabel was preserved');
      expect(dbAfterAutosave.folderId, folderPersonal.id, reason: 'folderId was preserved');
      expect(dbAfterAutosave.isArchived, isTrue, reason: 'isArchived was preserved');

      notifier.dispose();
    });

    test('Partial UPDATE updates checklistJson & isChecklistMode and never clobbers isLocked or folder/pin', () async {
      // 1. Create a note with isLocked = false, folder, pin
      final note = Note.create(
        title: 'Checklist Note',
        body: '- [ ] Item 1\n- [ ] Item 2',
        isPinned: true,
      );
      await repository.insertNote(note);

      // 2. Open in editor and toggle to checklist mode
      final notifier = NoteEditorNotifier(repository, note);
      notifier.toggleChecklistMode();
      expect(notifier.note.isChecklistMode, isTrue);

      // Check an item
      final items = notifier.checklistItems;
      notifier.updateChecklistItem(items.first.id, isChecked: true);

      // 3. Flush partial update
      await notifier.saveImmediately();

      // 4. Verify DB state: checklist mode & JSON updated, but isPinned, isArchived, isLocked preserved
      final saved = await repository.getNoteById(note.id);
      expect(saved, isNotNull);
      expect(saved!.isChecklistMode, isTrue);
      expect(saved.checklistJson, isNotNull);
      expect(saved.isPinned, isTrue);
      expect(saved.isArchived, isFalse);
      expect(saved.isLocked, isFalse);

      notifier.dispose();
    });
  });
}
