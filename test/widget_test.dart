import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/core/theme/app_theme.dart';
import 'package:privacy_notes/core/widgets/error_state.dart';
import 'package:privacy_notes/core/widgets/loading_state.dart';
import 'package:privacy_notes/core/widgets/section_header.dart';
import 'package:privacy_notes/features/notes/data/notes_repository.dart';
import 'package:privacy_notes/features/notes/domain/folder.dart';
import 'package:privacy_notes/features/notes/domain/note.dart';
import 'package:privacy_notes/features/notes/domain/note_sort.dart';
import 'package:privacy_notes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:privacy_notes/features/notes/presentation/screens/notes_list_screen.dart';
import 'package:privacy_notes/features/notes/presentation/widgets/note_card.dart';
import 'package:privacy_notes/features/notes/presentation/widgets/notes_empty_view.dart';

class FakeNotesRepository implements NotesRepository {
  List<Note> notes = [];
  List<Folder> folders = [];
  bool shouldFail = false;
  Completer<void>? pendingDelayCompleter;

  @override
  Future<List<Note>> getActiveNotes({
    bool includeArchived = false,
    String? folderId,
    NoteSortOption? sortOption,
  }) async {
    if (pendingDelayCompleter != null) {
      await pendingDelayCompleter!.future;
    }
    if (shouldFail) {
      throw Exception('Simulated repository failure');
    }
    var result = notes.where((n) => !n.isTrashed).toList();
    if (!includeArchived) {
      result = result.where((n) => !n.isArchived).toList();
    }
    if (folderId != null) {
      if (folderId.isEmpty) {
        result = result.where((n) => n.folderId == null).toList();
      } else {
        result = result.where((n) => n.folderId == folderId).toList();
      }
    }
    return result;
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
  Future<Note> insertNote(Note note) async {
    notes.add(note);
    return note;
  }

  @override
  Future<void> updateNote(Note note) async {
    final index = notes.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      notes[index] = note;
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
    final index = notes.indexWhere((n) => n.id == id);
    if (index != -1) {
      final existing = notes[index];
      notes[index] = existing.copyWith(
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
  Future<List<Note>> getArchivedNotes({NoteSortOption? sortOption}) async {
    return notes.where((n) => !n.isTrashed && n.isArchived).toList();
  }

  @override
  Future<List<Note>> getTrashedNotes() async {
    return notes.where((n) => n.isTrashed).toList();
  }

  @override
  Future<void> trashNote(String id) async {
    final note = await getNoteById(id);
    if (note != null) {
      final index = notes.indexOf(note);
      notes[index] = note.copyWith(
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
    final note = await getNoteById(id);
    if (note != null) {
      final index = notes.indexOf(note);
      notes[index] = note.copyWith(clearTrashedAt: true);
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
  Future<void> setPinned(String id, bool isPinned) async {
    final note = await getNoteById(id);
    if (note != null) {
      final index = notes.indexOf(note);
      notes[index] = note.copyWith(isPinned: isPinned);
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
    final note = await getNoteById(id);
    if (note != null) {
      final index = notes.indexOf(note);
      notes[index] = note.copyWith(colorLabel: colorLabel);
    }
  }

  @override
  Future<void> archiveNote(String id) async {
    final note = await getNoteById(id);
    if (note != null) {
      final index = notes.indexOf(note);
      notes[index] = note.copyWith(isArchived: true);
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
    final note = await getNoteById(id);
    if (note != null) {
      final index = notes.indexOf(note);
      notes[index] = note.copyWith(isArchived: false);
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
      final note = await getNoteById(id);
      if (note != null) {
        final index = notes.indexOf(note);
        notes[index] = note.copyWith(folderId: folderId);
      }
    }
  }

  @override
  Future<List<Folder>> getFolders() async => folders;

  @override
  Future<Folder> createFolder(String name, {int? color}) async {
    final folder = Folder.create(name: name, color: color);
    folders.add(folder);
    return folder;
  }

  @override
  Future<void> renameFolder(String id, String newName) async {
    final index = folders.indexWhere((f) => f.id == id);
    if (index != -1) {
      folders[index] = folders[index].copyWith(name: newName);
    }
  }

  @override
  Future<void> deleteFolder(String id) async {
    folders.removeWhere((f) => f.id == id);
    for (var i = 0; i < notes.length; i++) {
      if (notes[i].folderId == id) {
        notes[i] = notes[i].copyWith(folderId: null);
      }
    }
  }
}

Widget createTestWidget(FakeNotesRepository fakeRepo) {
  return ProviderScope(
    overrides: [
      notesRepositoryProvider.overrideWithValue(fakeRepo),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: const NotesListScreen(),
    ),
  );
}

void main() {
  group('NotesListScreen Widget Tests (Empty, Loading, Error, Populated)', () {
    late FakeNotesRepository fakeRepo;

    setUp(() {
      fakeRepo = FakeNotesRepository();
    });

    testWidgets('1. Empty State: renders NotesEmptyView when no notes exist', (tester) async {
      fakeRepo.notes = [];

      await tester.pumpWidget(createTestWidget(fakeRepo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Privacy Notes'), findsOneWidget);
      expect(find.byType(NotesEmptyView), findsOneWidget);
      expect(find.text('No notes yet'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('2. Loading State: renders LoadingState while repository is fetching notes', (tester) async {
      fakeRepo.pendingDelayCompleter = Completer<void>();

      await tester.pumpWidget(createTestWidget(fakeRepo));
      await tester.pump(); // Render first frame before future completes

      expect(find.byType(LoadingState), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Finish pending delay and pump remaining frames
      fakeRepo.pendingDelayCompleter!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('3. Error State: renders ErrorState with retry button and recovers on retry', (tester) async {
      fakeRepo.shouldFail = true;

      await tester.pumpWidget(createTestWidget(fakeRepo));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Failed to load notes. Please retry.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);

      // Recover on Retry
      fakeRepo.shouldFail = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsNothing);
      expect(find.byType(NotesEmptyView), findsOneWidget);
    });

    testWidgets('4. Populated State: renders SectionHeaders and NoteCards for pinned and recent notes', (tester) async {
      fakeRepo.notes = [
        Note.create(
          title: 'Pinned Note Alpha',
          body: 'Content for pinned note',
          isPinned: true,
        ),
        Note.create(
          title: 'Recent Note Beta',
          body: 'Content for regular note',
          isPinned: false,
        ),
      ];

      await tester.pumpWidget(createTestWidget(fakeRepo));
      await tester.pumpAndSettle();

      expect(find.byType(NotesEmptyView), findsNothing);
      expect(find.byType(NoteCard), findsNWidgets(2));
      expect(find.text('Pinned Note Alpha'), findsOneWidget);
      expect(find.text('Recent Note Beta'), findsOneWidget);
      expect(find.byType(SectionHeader), findsNWidgets(2));
      expect(find.text('PINNED'), findsOneWidget);
      expect(find.text('RECENT'), findsOneWidget);
    });
  });
}
