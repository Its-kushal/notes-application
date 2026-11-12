import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/core/theme/app_theme.dart';
import 'package:privacy_notes/core/widgets/section_header.dart';
import 'package:privacy_notes/features/notes/data/notes_repository.dart';
import 'package:privacy_notes/features/notes/domain/folder.dart';
import 'package:privacy_notes/features/notes/domain/note.dart';
import 'package:privacy_notes/features/notes/domain/note_sort.dart';
import 'package:privacy_notes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:privacy_notes/features/notes/presentation/screens/notes_list_screen.dart';
import 'package:privacy_notes/l10n/app_localizations.dart';

class _FakeNotesRepository implements NotesRepository {
  List<Note> notes = [];
  List<Folder> folders = [];

  @override
  Future<List<Note>> getActiveNotes({
    bool includeArchived = false,
    String? folderId,
    NoteSortOption? sortOption,
  }) async {
    var result = notes.where((n) => !n.isTrashed && (includeArchived || !n.isArchived)).toList();
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
  Future<Note> insertNote(Note note) async {
    notes.add(note);
    return note;
  }

  @override
  Future<void> updateNote(Note note) async {}

  @override
  Future<void> updateNoteContent({
    required String id,
    required String title,
    required String body,
    String? checklistJson,
    bool? isChecklistMode,
    required int wordCount,
    int? updatedAt,
  }) async {}

  @override
  Future<Note?> getNoteById(String id) async {
    try {
      return notes.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Note>> searchNotes(
    String query, {
    bool includeArchived = false,
    String? folderId,
    NoteSortOption? sortOption,
  }) async => [];

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
  Future<int> purgeEmptyNotes() async => 0;

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
  Future<Folder> createFolder(String name, {int? color}) async => Folder.create(name: name);

  @override
  Future<void> renameFolder(String id, String newName) async {}

  @override
  Future<void> deleteFolder(String id) async {}

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
  Future<void> deleteLockedNotePermanently(String id) async {}
}

void _assertNoException(WidgetTester tester) {
  final exc = tester.takeException();
  if (exc != null) {
    for (final element in tester.allElements) {
      if (element.renderObject is RenderFlex) {
        final rf = element.renderObject as RenderFlex;
        if (rf.hasSize && rf.size.height > 0) {
          // ignore: avoid_print
          print('WIDGET: ${element.widget.runtimeType}, PARENT: ${element.depth}, SIZE: ${rf.size}');
        }
      }
    }
  }
  expect(exc, isNull);
}

Widget _buildTestApp({
  required Widget child,
  required double fontScale,
  required Size screenSize,
  required _FakeNotesRepository repo,
}) {
  return ProviderScope(
    overrides: [
      notesRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: screenSize,
          textScaler: TextScaler.linear(fontScale),
        ),
        child: child,
      ),
    ),
  );
}

void main() {
  setUp(() {
    FlutterError.onError = (details) {
      // ignore: avoid_print
      print('=== OVERFLOW DEBUG ===');
      // ignore: avoid_print
      print(details.toString());
      // ignore: avoid_print
      print(details.informationCollector?.call().map((d) => d.toString()).join('\n'));
      FlutterError.presentError(details);
    };
  });
  group('Select All Header Layout & Responsive Scale Tests', () {
    final fontScales = [1.0, 1.3, 1.5];
    final viewports = [
      {'name': 'Portrait (412x915)', 'size': const Size(412, 915)},
      {'name': 'Landscape (915x412)', 'size': const Size(915, 412)},
    ];

    for (final scale in fontScales) {
      for (final vp in viewports) {
        final vpName = vp['name'] as String;
        final vpSize = vp['size'] as Size;

        testWidgets('Selection mode header at scale $scale in $vpName does not overflow', (tester) async {
          tester.view.physicalSize = vpSize;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final repo = _FakeNotesRepository()
            ..notes = [
              Note.create(title: 'Note 1', body: 'Body 1'),
              Note.create(title: 'Note 2', body: 'Body 2'),
            ];

          await tester.pumpWidget(
            _buildTestApp(
              child: const NotesListScreen(),
              fontScale: scale,
              screenSize: vpSize,
              repo: repo,
            ),
          );
          await tester.pumpAndSettle();
          tester.takeException(); // Pre-selection render

          // Enter selection mode by long-pressing Note 1
          final noteCard = find.text('Note 1');
          expect(noteCard, findsOneWidget);
          await tester.longPress(noteCard);
          await tester.pumpAndSettle();

          // Verify no layout exceptions
          _assertNoException(tester);

          // Verify SectionHeader exists and shows "Select all" button
          expect(find.byType(SectionHeader), findsOneWidget);
          final selectAllBtn = find.text('Select all');
          expect(selectAllBtn, findsOneWidget);

          // Check minimum tap target size (>= 48 dp height and width)
          final btnSize = tester.getSize(find.ancestor(
            of: selectAllBtn,
            matching: find.byType(TextButton),
          ));
          expect(btnSize.height, greaterThanOrEqualTo(48.0));
          expect(btnSize.width, greaterThanOrEqualTo(48.0));

          // Check TalkBack semantics label
          expect(
            find.bySemanticsLabel('Select all'),
            findsWidgets,
          );

          // Tap "Select all" to select all notes
          await tester.tap(selectAllBtn);
          await tester.pumpAndSettle();
          _assertNoException(tester);

          // Heading now shows "Deselect all"
          final deselectAllBtn = find.text('Deselect all');
          expect(deselectAllBtn, findsOneWidget);
          expect(
            find.bySemanticsLabel('Deselect all'),
            findsWidgets,
          );

          // Tap "Deselect all" to clear selection
          await tester.tap(deselectAllBtn);
          await tester.pumpAndSettle();
          _assertNoException(tester);
        });

        testWidgets('Pinned + Unpinned notes in selection mode at scale $scale in $vpName: button on top header', (tester) async {
          tester.view.physicalSize = vpSize;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final repo = _FakeNotesRepository()
            ..notes = [
              Note.create(title: 'Pinned Note', body: 'Pinned Body', isPinned: true),
              Note.create(title: 'Recent Note', body: 'Recent Body', isPinned: false),
            ];

          await tester.pumpWidget(
            _buildTestApp(
              child: const NotesListScreen(),
              fontScale: scale,
              screenSize: vpSize,
              repo: repo,
            ),
          );
          await tester.pumpAndSettle();
          tester.takeException(); // Pre-selection render

          // Long press to enter selection mode
          await tester.longPress(find.text('Pinned Note'));
          await tester.pumpAndSettle();

          _assertNoException(tester);

          // There are two section headers: PINNED and RECENT
          expect(find.text('PINNED'), findsOneWidget);
          expect(find.text('RECENT'), findsOneWidget);

          // "Select all" should appear on the top PINNED header
          expect(find.text('Select all'), findsOneWidget);

          // Tap "Select all"
          await tester.tap(find.text('Select all'));
          await tester.pumpAndSettle();
          _assertNoException(tester);
          expect(find.text('Deselect all'), findsOneWidget);
        });
      }
    }
  });
}
