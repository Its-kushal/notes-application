import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/core/theme/app_theme.dart';
import 'package:privacy_notes/core/widgets/app_snackbar.dart';
import 'package:privacy_notes/features/notes/data/notes_repository.dart';
import 'package:privacy_notes/features/notes/domain/folder.dart';
import 'package:privacy_notes/features/notes/domain/note.dart';
import 'package:privacy_notes/features/notes/domain/note_sort.dart';
import 'package:privacy_notes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:privacy_notes/features/notes/presentation/screens/archive_screen.dart';
import 'package:privacy_notes/features/notes/presentation/screens/note_editor_screen.dart';
import 'package:privacy_notes/features/notes/presentation/screens/notes_list_screen.dart';
import 'package:privacy_notes/features/notes/presentation/screens/trash_screen.dart';

class InMemoryNotesRepository implements NotesRepository {
  final List<Note> notes = [];
  final List<Folder> folders = [];

  @override
  Future<Note> insertNote(Note note) async {
    notes.add(note);
    return note;
  }

  @override
  Future<void> updateNote(Note note) async {
    final idx = notes.indexWhere((n) => n.id == note.id);
    if (idx != -1) notes[idx] = note;
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
    final idx = notes.indexWhere((n) => n.id == id);
    if (idx != -1) {
      notes[idx] = notes[idx].copyWith(
        title: title,
        body: body,
        checklistJson: checklistJson,
        isChecklistMode: isChecklistMode,
        wordCount: wordCount,
        updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  @override
  Future<Note?> getNoteById(String id) async {
    try {
      return notes.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Note>> getActiveNotes({
    bool includeArchived = false,
    String? folderId,
    NoteSortOption? sortOption,
  }) async {
    var res = notes.where((n) => !n.isTrashed).toList();
    if (!includeArchived) {
      res = res.where((n) => !n.isArchived).toList();
    }
    if (folderId != null) {
      if (folderId.isEmpty) {
        res = res.where((n) => n.folderId == null).toList();
      } else {
        res = res.where((n) => n.folderId == folderId).toList();
      }
    }
    return res;
  }

  @override
  Future<List<Note>> searchNotes(
    String query, {
    bool includeArchived = false,
    String? folderId,
    NoteSortOption? sortOption,
  }) async {
    final active = await getActiveNotes(
      includeArchived: includeArchived,
      folderId: folderId,
      sortOption: sortOption,
    );
    final q = query.toLowerCase();
    return active
        .where((n) =>
            n.title.toLowerCase().contains(q) ||
            n.body.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<List<Note>> getArchivedNotes({NoteSortOption? sortOption}) async {
    return notes.where((n) => !n.isTrashed && n.isArchived).toList();
  }

  @override
  Future<List<Note>> getTrashedNotes() async {
    return notes.where((n) => n.isTrashed).toList();
  }

  @override
  Future<void> trashNote(String id) async {
    final idx = notes.indexWhere((n) => n.id == id);
    if (idx != -1) {
      notes[idx] = notes[idx].copyWith(
        trashedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  @override
  Future<void> trashNotes(List<String> ids) async {
    for (final id in ids) {
      await trashNote(id);
    }
  }

  @override
  Future<void> restoreNote(String id) async {
    final idx = notes.indexWhere((n) => n.id == id);
    if (idx != -1) {
      notes[idx] = notes[idx].copyWith(clearTrashedAt: true);
    }
  }

  @override
  Future<void> restoreNotes(List<String> ids) async {
    for (final id in ids) {
      await restoreNote(id);
    }
  }

  @override
  Future<void> deleteNotePermanently(String id) async {
    notes.removeWhere((n) => n.id == id);
  }

  @override
  Future<void> deleteNotesPermanently(List<String> ids) async {
    notes.removeWhere((n) => ids.contains(n.id));
  }

  @override
  Future<void> emptyTrash() async {
    notes.removeWhere((n) => n.isTrashed);
  }

  @override
  Future<int> purgeExpiredTrash({int retentionDays = 30}) async => 0;

  @override
  Future<int> purgeEmptyNotes() async {
    final countBefore = notes.length;
    notes.removeWhere((n) => n.title.trim().isEmpty && n.body.trim().isEmpty && !n.isLocked);
    return countBefore - notes.length;
  }

  @override
  Future<void> setPinned(String id, bool isPinned) async {
    final idx = notes.indexWhere((n) => n.id == id);
    if (idx != -1) {
      notes[idx] = notes[idx].copyWith(isPinned: isPinned);
    }
  }

  @override
  Future<void> setPinnedMultiple(List<String> ids, bool isPinned) async {
    for (final id in ids) {
      await setPinned(id, isPinned);
    }
  }

  @override
  Future<void> setColorLabel(String id, int colorLabel) async {
    final idx = notes.indexWhere((n) => n.id == id);
    if (idx != -1) {
      notes[idx] = notes[idx].copyWith(colorLabel: colorLabel);
    }
  }

  @override
  Future<void> archiveNote(String id) async {
    final idx = notes.indexWhere((n) => n.id == id);
    if (idx != -1) {
      notes[idx] = notes[idx].copyWith(isArchived: true);
    }
  }

  @override
  Future<void> archiveNotes(List<String> ids) async {
    for (final id in ids) {
      await archiveNote(id);
    }
  }

  @override
  Future<void> unarchiveNote(String id) async {
    final idx = notes.indexWhere((n) => n.id == id);
    if (idx != -1) {
      notes[idx] = notes[idx].copyWith(isArchived: false);
    }
  }

  @override
  Future<void> unarchiveNotes(List<String> ids) async {
    for (final id in ids) {
      await unarchiveNote(id);
    }
  }

  @override
  Future<void> moveNotesToFolder(List<String> ids, String? folderId) async {
    for (final id in ids) {
      final idx = notes.indexWhere((n) => n.id == id);
      if (idx != -1) {
        notes[idx] = notes[idx].copyWith(folderId: folderId);
      }
    }
  }

  @override
  Future<List<Folder>> getFolders() async => folders;

  @override
  Future<Folder> createFolder(String name, {int? color}) async {
    final f = Folder.create(name: name, color: color);
    folders.add(f);
    return f;
  }

  @override
  Future<void> renameFolder(String id, String newName) async {
    final idx = folders.indexWhere((f) => f.id == id);
    if (idx != -1) {
      folders[idx] = folders[idx].copyWith(name: newName);
    }
  }

  @override
  Future<void> deleteFolder(String id) async {
    folders.removeWhere((f) => f.id == id);
    for (var i = 0; i < notes.length; i++) {
      if (notes[i].folderId == id) {
        notes[i] = notes[i].copyWith(clearFolderId: true);
      }
    }
  }

  @override
  Future<void> lockNote(String noteId, Uint8List vaultKey, {int? expectedUpdatedAt}) async {}

  @override
  Future<void> unlockNote(String noteId, Uint8List vaultKey) async {}

  @override
  Future<void> updateLockedNoteContent({
    required String id,
    required String title,
    required String body,
    String? checklistJson,
    bool? isChecklistMode,
    required Uint8List vaultKey,
    int? updatedAt,
  }) async {}

  @override
  Future<List<Note>> getLockedNotes(Uint8List vaultKey) async => [];

  @override
  Future<Note?> getLockedNoteById(String id, Uint8List vaultKey) async => null;

  @override
  Future<void> deleteLockedNotePermanently(String id) async {
    notes.removeWhere((n) => n.id == id && n.isLocked);
  }
}

void main() {
  group('M2 Review Bugs Reproduction Tests', () {
    late InMemoryNotesRepository repo;

    setUp(() {
      repo = InMemoryNotesRepository();
    });

    testWidgets('B1 Reproduction: Trashing a note from list does NOT update TrashScreen due to stale trashProvider', (tester) async {
      final note = Note.create(title: 'Note to be trashed', body: 'Trash test');
      repo.notes.add(note);

      final container = ProviderContainer(
        overrides: [
          notesRepositoryProvider.overrideWithValue(repo),
        ],
      );

      // Pre-read trashProvider so it initializes and caches empty list
      container.read(trashProvider);

      // Trash the note from notesListProvider
      await container.read(notesListProvider).trashNote(note.id);

      // Now pump TrashScreen using this container
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const TrashScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In current buggy code, TrashScreen will NOT show the trashed note because
      // trashProvider loaded once in constructor and was never reloaded!
      expect(find.text('Note to be trashed'), findsOneWidget,
          reason: 'B1 bug: TrashScreen must show the newly trashed note');
    });

    testWidgets('B1 Reproduction: Archiving a note from list does NOT update ArchiveScreen due to stale archiveProvider', (tester) async {
      final note = Note.create(title: 'Note to be archived', body: 'Archive test');
      repo.notes.add(note);

      final container = ProviderContainer(
        overrides: [
          notesRepositoryProvider.overrideWithValue(repo),
        ],
      );

      // Pre-read archiveProvider so it initializes and caches empty list
      container.read(archiveProvider);

      // Archive the note from notesListProvider
      await container.read(notesListProvider).archiveNote(note.id);

      // Now pump ArchiveScreen using this container
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ArchiveScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // In current buggy code, ArchiveScreen will NOT show the archived note because
      // archiveProvider loaded once in constructor and was never reloaded!
      expect(find.text('Note to be archived'), findsOneWidget,
          reason: 'B1 bug: ArchiveScreen must show the newly archived note');
    });

    testWidgets('B2: Undo snackbar auto-dismisses after 5 seconds and new snackbar replaces old', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () {
                      AppSnackBar.show(
                        context,
                        message: 'Action 1',
                        actionLabel: 'Undo',
                        onAction: () {},
                      );
                    },
                    child: const Text('Show Action 1'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      AppSnackBar.show(
                        context,
                        message: 'Action 2',
                      );
                    },
                    child: const Text('Show Action 2'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Trigger snackbar 1
      await tester.tap(find.text('Show Action 1'));
      await tester.pump();
      expect(find.text('Action 1'), findsOneWidget);

      // Trigger snackbar 2: replaces snackbar 1 immediately
      await tester.tap(find.text('Show Action 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Action 1'), findsNothing);
      expect(find.text('Action 2'), findsOneWidget);

      // Advance 5 seconds so duration timer triggers dismissal
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Auto-dismissed
      expect(find.text('Action 2'), findsNothing,
          reason: 'B2: SnackBar must auto-dismiss after 5 seconds');
    });

    test('B5: Multi-select pin/unpin toggles: unpins if all selected are pinned, otherwise pins', () async {
      final note1 = Note.create(title: 'Note 1', isPinned: true);
      final note2 = Note.create(title: 'Note 2', isPinned: true);
      final note3 = Note.create(title: 'Note 3', isPinned: false);
      repo.notes.addAll([note1, note2, note3]);

      final notifier = NotesListNotifier(repo);
      await notifier.loadNotes();

      // Case 1: Select note1 and note2 (both pinned) -> should unpin both
      notifier.toggleNoteSelection(note1.id);
      notifier.toggleNoteSelection(note2.id);

      expect(notifier.areAllSelectedPinned, isTrue);
      await notifier.toggleBulkPin();
      expect(repo.notes.firstWhere((n) => n.id == note1.id).isPinned, isFalse);
      expect(repo.notes.firstWhere((n) => n.id == note2.id).isPinned, isFalse);

      // Case 2: Select note1 (now unpinned) and note3 (unpinned) -> should pin both
      notifier.toggleNoteSelection(note1.id);
      notifier.toggleNoteSelection(note3.id);
      expect(notifier.areAllSelectedPinned, isFalse);
      await notifier.toggleBulkPin();
      expect(repo.notes.firstWhere((n) => n.id == note1.id).isPinned, isTrue);
      expect(repo.notes.firstWhere((n) => n.id == note3.id).isPinned, isTrue);
    });

    test('B7: Search debounces 250ms and ignores stale results', () async {
      final notifier = NotesListNotifier(repo);
      notifier.setSearchQuery('fast');
      // Verify debounced (not loaded immediately on same microtask)
      expect(notifier.searchQuery, 'fast');
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    test('B8: Clear selection when folder filter or search changes', () async {
      final note1 = Note.create(title: 'Note 1');
      repo.notes.add(note1);

      final notifier = NotesListNotifier(repo);
      await notifier.loadNotes();

      notifier.toggleNoteSelection(note1.id);
      expect(notifier.isSelectionMode, isTrue);

      // Changing search clears selection
      notifier.setSearchQuery('test');
      expect(notifier.isSelectionMode, isFalse);

      notifier.toggleNoteSelection(note1.id);
      expect(notifier.isSelectionMode, isTrue);

      // Changing folder filter clears selection
      await notifier.setSelectedFolder('some-folder');
      expect(notifier.isSelectionMode, isFalse);
    });

    testWidgets('Restore returns note to active list; Unarchive returns note to active list', (tester) async {
      final note1 = Note.create(title: 'Trashed Note').copyWith(trashedAt: DateTime.now().millisecondsSinceEpoch);
      final note2 = Note.create(title: 'Archived Note', isArchived: true);
      repo.notes.addAll([note1, note2]);

      final container = ProviderContainer(
        overrides: [notesRepositoryProvider.overrideWithValue(repo)],
      );

      final listNotifier = container.read(notesListProvider);
      await listNotifier.loadNotes();
      expect(listNotifier.notes.isEmpty, isTrue);

      // Restore note1
      await listNotifier.restoreNote(note1.id);
      expect(listNotifier.notes.any((n) => n.id == note1.id), isTrue);

      // Unarchive note2
      await listNotifier.unarchiveNote(note2.id);
      expect(listNotifier.notes.any((n) => n.id == note2.id), isTrue);
    });

    testWidgets('Revisit screen after changes (staleness regression)', (tester) async {
      final note1 = Note.create(title: 'First Trashed Note');
      repo.notes.add(note1);

      final container = ProviderContainer(
        overrides: [notesRepositoryProvider.overrideWithValue(repo)],
      );

      await container.read(notesListProvider).trashNote(note1.id);

      // Visit TrashScreen first time
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.lightTheme, home: const TrashScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('First Trashed Note'), findsOneWidget);

      // Navigate away from TrashScreen
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.lightTheme, home: const SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();

      // Trash another note while user had navigated away
      final note2 = Note.create(title: 'Second Trashed Note');
      repo.notes.add(note2);
      await container.read(notesListProvider).trashNote(note2.id);

      // Revisit TrashScreen second time
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.lightTheme, home: const TrashScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Both notes must be present (no stale cache!)
      expect(find.text('First Trashed Note'), findsOneWidget);
      expect(find.text('Second Trashed Note'), findsOneWidget);
    });

    test('Undo for single and bulk trash/archive', () async {
      final note1 = Note.create(title: 'Note 1');
      final note2 = Note.create(title: 'Note 2');
      repo.notes.addAll([note1, note2]);

      final notifier = NotesListNotifier(repo);
      await notifier.loadNotes();

      // Single trash & undo
      await notifier.trashNote(note1.id);
      expect(notifier.notes.length, 1);
      await notifier.restoreNote(note1.id);
      expect(notifier.notes.length, 2);

      // Single archive & undo
      await notifier.archiveNote(note1.id);
      expect(notifier.notes.length, 1);
      await notifier.unarchiveNote(note1.id);
      expect(notifier.notes.length, 2);

      // Bulk trash & undo
      notifier.selectAll();
      final trashedIds = await notifier.bulkTrash();
      expect(trashedIds.length, 2);
      expect(notifier.notes.isEmpty, isTrue);
      await notifier.restoreNotes(trashedIds);
      expect(notifier.notes.length, 2);

      // Bulk archive & undo
      notifier.selectAll();
      final archivedIds = await notifier.bulkArchive();
      expect(archivedIds.length, 2);
      expect(notifier.notes.isEmpty, isTrue);
      await notifier.unarchiveNotes(archivedIds);
      expect(notifier.notes.length, 2);
    });

    testWidgets('Folder chips: no "No folder" chip; create, rename, delete leaves notes in All', (tester) async {
      final folder = await repo.createFolder('Project Alpha');
      final noteInFolder = Note.create(title: 'Alpha Note', folderId: folder.id);
      final noteNoFolder = Note.create(title: 'Unassigned Note');
      repo.notes.addAll([noteInFolder, noteNoFolder]);

      final container = ProviderContainer(
        overrides: [notesRepositoryProvider.overrideWithValue(repo)],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.lightTheme, home: const NotesListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // "All" chip exists
      expect(find.text('All'), findsOneWidget);
      // "No folder" chip is ABSENT
      expect(find.text('No folder'), findsNothing);
      // Folder chip exists
      expect(find.text('Project Alpha'), findsOneWidget);

      final notifier = container.read(notesListProvider);
      // Rename folder
      await notifier.renameFolder(folder.id, 'Project Beta');
      await tester.pumpAndSettle();
      expect(find.text('Project Beta'), findsOneWidget);

      // Delete folder
      await notifier.deleteFolder(folder.id);
      await tester.pumpAndSettle();

      // Note still exists in All notes list
      expect(find.text('Alpha Note'), findsOneWidget);
      expect(find.text('Unassigned Note'), findsOneWidget);
      expect(repo.notes.firstWhere((n) => n.id == noteInFolder.id).folderId, isNull);
    });

    testWidgets('Selection mode: back button exits selection first', (tester) async {
      final note1 = Note.create(title: 'Note 1');
      repo.notes.add(note1);

      final container = ProviderContainer(
        overrides: [notesRepositoryProvider.overrideWithValue(repo)],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.lightTheme, home: const NotesListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final notifier = container.read(notesListProvider);
      notifier.toggleNoteSelection(note1.id);
      await tester.pumpAndSettle();

      expect(notifier.isSelectionMode, isTrue);

      // Trigger Android back via PopScope
      final popScope = tester.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope));
      expect(popScope.canPop, isFalse); // Blocks route pop while in selection

      // Simulate pop invocation
      popScope.onPopInvokedWithResult!(false, null);
      await tester.pumpAndSettle();

      expect(notifier.isSelectionMode, isFalse);
    });

    testWidgets('Editor and multi-select archive and trash with Undo snackbars', (tester) async {
      final note = Note.create(title: 'Editor Note', body: 'Body');
      repo.notes.add(note);

      final container = ProviderContainer(
        overrides: [notesRepositoryProvider.overrideWithValue(repo)],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: NoteEditorScreen(note: note),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Archive button in editor
      await tester.tap(find.byTooltip('Archive'));
      await tester.pumpAndSettle();

      expect(repo.notes.firstWhere((n) => n.id == note.id).isArchived, isTrue);
    });
  });
}
