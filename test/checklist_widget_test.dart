import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/core/theme/app_theme.dart';
import 'package:privacy_notes/features/notes/data/notes_repository.dart';
import 'package:privacy_notes/features/notes/domain/checklist_item.dart';
import 'package:privacy_notes/features/notes/domain/folder.dart';
import 'package:privacy_notes/features/notes/domain/note.dart';
import 'package:privacy_notes/features/notes/domain/note_sort.dart';
import 'package:privacy_notes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:privacy_notes/features/notes/presentation/screens/note_editor_screen.dart';
import 'package:privacy_notes/features/notes/presentation/widgets/note_card.dart';
import 'package:privacy_notes/features/settings/data/settings_repository.dart';
import 'package:privacy_notes/features/settings/domain/app_settings.dart';
import 'package:privacy_notes/features/settings/presentation/controllers/settings_provider.dart';
import 'package:privacy_notes/features/settings/presentation/screens/about_screen.dart';

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
    return notes.where((n) => !n.isTrashed && (!n.isArchived || includeArchived)).toList();
  }

  @override
  Future<List<Note>> searchNotes(
    String query, {
    bool includeArchived = false,
    String? folderId,
    NoteSortOption? sortOption,
  }) async => notes;

  @override
  Future<List<Note>> getArchivedNotes({NoteSortOption? sortOption}) async => [];

  @override
  Future<List<Note>> getTrashedNotes() async => [];

  @override
  Future<void> trashNote(String id) async {}

  @override
  Future<void> trashNotes(List<String> ids) async {}

  @override
  Future<void> restoreNote(String id) async {}

  @override
  Future<void> restoreNotes(List<String> ids) async {}

  @override
  Future<void> deleteNotePermanently(String id) async {}

  @override
  Future<void> deleteNotesPermanently(List<String> ids) async {}

  @override
  Future<void> emptyTrash() async {}

  @override
  Future<int> purgeExpiredTrash({int retentionDays = 30}) async => 0;

  @override
  Future<void> setPinned(String id, bool isPinned) async {}

  @override
  Future<void> setPinnedMultiple(List<String> ids, bool isPinned) async {}

  @override
  Future<void> setColorLabel(String id, int colorLabel) async {}

  @override
  Future<void> archiveNote(String id) async {}

  @override
  Future<void> archiveNotes(List<String> ids) async {}

  @override
  Future<void> unarchiveNote(String id) async {}

  @override
  Future<void> unarchiveNotes(List<String> ids) async {}

  @override
  Future<void> moveNotesToFolder(List<String> ids, String? folderId) async {}

  @override
  Future<List<Folder>> getFolders() async => folders;

  @override
  Future<Folder> createFolder(String name, {int? color}) async {
    final f = Folder.create(name: name, color: color);
    folders.add(f);
    return f;
  }

  @override
  Future<void> renameFolder(String id, String newName) async {}

  @override
  Future<void> deleteFolder(String id) async {}

  @override
  Future<int> purgeEmptyNotes() async {
    final countBefore = notes.length;
    notes.removeWhere((n) => n.title.trim().isEmpty && n.body.trim().isEmpty && !n.isLocked);
    return countBefore - notes.length;
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

class InMemorySettingsRepository implements SettingsRepository {
  AppSettings _settings;
  InMemorySettingsRepository([this._settings = const AppSettings()]);

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> updateSetting(String key, String value) async {
    final map = _settings.toMap();
    map[key] = value;
    _settings = AppSettings.fromMap(map);
  }
}

void main() {
  group('Checklist Editor & NoteCard UI Widget Tests', () {
    late InMemoryNotesRepository notesRepo;
    late InMemorySettingsRepository settingsRepo;

    setUp(() {
      notesRepo = InMemoryNotesRepository();
      settingsRepo = InMemorySettingsRepository();
    });

    testWidgets('Toggle mode converts text to checklist with progress bar and back to text without loss', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Note with 2 items in markdown body
      final initialNote = Note.create(
        title: 'Groceries',
        body: '- [ ] Apples\n- [x] Bananas',
      );
      await notesRepo.insertNote(initialNote);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notesRepositoryProvider.overrideWithValue(notesRepo),
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: NoteEditorScreen(note: initialNote),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially in text mode
      expect(find.byTooltip('Switch to checklist mode'), findsOneWidget);
      expect(find.text('- [ ] Apples\n- [x] Bananas'), findsOneWidget);

      // Tap checklist mode toggle
      await tester.tap(find.byTooltip('Switch to checklist mode'));
      await tester.pumpAndSettle();

      // Now in checklist mode
      expect(find.byTooltip('Switch to text mode'), findsOneWidget);
      // Progress indicator: 1 of 2 completed
      expect(find.text('1/2 completed'), findsOneWidget);
      expect(find.text('Apples'), findsOneWidget);
      expect(find.text('Bananas'), findsOneWidget);

      // Check "Apples"
      final checkboxes = find.byType(Checkbox);
      expect(checkboxes, findsNWidgets(2));
      await tester.tap(checkboxes.first);
      await tester.pumpAndSettle();

      // Progress now 2/2 completed
      expect(find.text('2/2 completed'), findsOneWidget);

      // Tap add icon to add a new item
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Progress now 2/3 completed
      expect(find.text('2/3 completed'), findsOneWidget);

      // Toggle back to text mode
      await tester.tap(find.byTooltip('Switch to text mode'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Switch to checklist mode'), findsOneWidget);
      // Verify body text contains the items as markdown without data loss
      final bodyField = find.byType(TextField).last;
      final controller = (tester.widget(bodyField) as TextField).controller;
      expect(controller!.text.contains('- [x] Apples'), isTrue);
      expect(controller.text.contains('- [x] Bananas'), isTrue);
    });

    testWidgets('NoteCard renders checklist preview with checkboxes, items, and completed count', (tester) async {
      final items = [
        const ChecklistItem(id: '1', text: 'First task', isChecked: true),
        const ChecklistItem(id: '2', text: 'Second task', isChecked: false),
        const ChecklistItem(id: '3', text: 'Third task', isChecked: false),
        const ChecklistItem(id: '4', text: 'Fourth task', isChecked: false),
      ];

      final checklistNote = Note.create(
        title: 'Project Roadmap',
        checklistJson: ChecklistItem.encodeList(items),
        isChecklistMode: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: NoteCard(
                note: checklistNote,
                onTap: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify title & checklist indicator icon
      expect(find.text('Project Roadmap'), findsOneWidget);
      expect(find.byIcon(Icons.checklist), findsOneWidget);

      // Verify preview shows top 3 items
      expect(find.text('First task'), findsOneWidget);
      expect(find.text('Second task'), findsOneWidget);
      expect(find.text('Third task'), findsOneWidget);

      // Verify "+ 1 more items" is rendered because there are 4 items
      expect(find.text('+ 1 more items'), findsOneWidget);

      // Verify completed count indicator
      expect(find.text('1/4 completed'), findsOneWidget);
    });

    testWidgets('NoteEditorScreen overflow menu opens Export Note modal bottom sheet', (tester) async {
      final note = Note.create(
        title: 'Exportable Note',
        body: 'Confidential thoughts.',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            notesRepositoryProvider.overrideWithValue(notesRepo),
            settingsRepositoryProvider.overrideWithValue(settingsRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: NoteEditorScreen(note: note),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open 3-dots overflow menu
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();

      // Tap "Export note"
      expect(find.text('Export note'), findsOneWidget);
      await tester.tap(find.text('Export note'));
      await tester.pumpAndSettle();

      // Bottom sheet modal should appear with Share and Save options
      expect(find.text('Export Note'), findsOneWidget);
      expect(find.text('Share text file'), findsOneWidget);
      expect(find.text('Save to device'), findsOneWidget);
    });

    testWidgets('AboutScreen renders app identity, version, and privacy commitments', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const AboutScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('About'), findsOneWidget);
      expect(find.text('Privacy Notes'), findsOneWidget);
      expect(find.text('Version 1.0.0'), findsOneWidget);
      expect(find.text('Our Privacy Guarantee'), findsOneWidget);
      expect(find.text('Hardware-Backed SQLCipher'), findsOneWidget);
      expect(find.text('No Internet Permission'), findsOneWidget);
      expect(find.text('Storage Access Framework'), findsOneWidget);
      expect(find.text('Open Source & Transparent'), findsOneWidget);
    });
  });
}
