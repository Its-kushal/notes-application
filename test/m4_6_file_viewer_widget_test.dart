import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/app.dart';
import 'package:privacy_notes/core/database/app_database.dart';
import 'package:privacy_notes/core/database/database_recovery_screen.dart';
import 'package:privacy_notes/core/widgets/error_state.dart';
import 'package:privacy_notes/features/file_viewer/domain/opened_file.dart';
import 'package:privacy_notes/features/file_viewer/presentation/screens/file_viewer_screen.dart';
import 'package:privacy_notes/features/notes/data/notes_repository.dart';
import 'package:privacy_notes/features/notes/domain/note.dart';
import 'package:privacy_notes/features/notes/presentation/controllers/notes_providers.dart';

class FakeNotesRepository implements NotesRepository {
  final List<Note> notes = [];

  @override
  Future<Note> insertNote(Note note) async {
    notes.add(note);
    return note;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget buildTestWidget({
    required OpenedFile file,
    FakeNotesRepository? repository,
    DatabaseStatus dbStatus = DatabaseStatus.ready,
  }) {
    final repo = repository ?? FakeNotesRepository();
    return ProviderScope(
      overrides: [
        notesRepositoryProvider.overrideWithValue(repo),
        databaseInitProvider.overrideWith((ref) => Future.value(dbStatus)),
      ],
      child: MaterialApp(
        home: FileViewerScreen(file: file),
      ),
    );
  }

  group('FileViewerScreen - Loaded State', () {
    testWidgets('renders file name, lines lazily, and action buttons', (tester) async {
      const file = OpenedFile(
        name: 'meeting_notes.txt',
        text: 'Line 1: Project kickoff\nLine 2: Milestones\nLine 3: Wrap up',
      );

      await tester.pumpWidget(buildTestWidget(file: file));
      await tester.pumpAndSettle();

      expect(find.text('meeting_notes.txt'), findsOneWidget);
      expect(find.text('Line 1: Project kickoff'), findsOneWidget);
      expect(find.text('Line 2: Milestones'), findsOneWidget);
      expect(find.text('Line 3: Wrap up'), findsOneWidget);
      expect(find.text('Save as note'), findsOneWidget);
      expect(find.byTooltip('Monospace font'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('toggles monospace font when icon tapped', (tester) async {
      const file = OpenedFile(
        name: 'code.txt',
        text: 'function test() {}',
      );

      await tester.pumpWidget(buildTestWidget(file: file));
      await tester.pumpAndSettle();

      final textFinder = find.text('function test() {}');
      Text textWidget = tester.widget(textFinder);
      expect(textWidget.style?.fontFamily, isNot(equals('monospace')));

      // Tap monospace toggle
      await tester.tap(find.byTooltip('Monospace font'));
      await tester.pumpAndSettle();

      textWidget = tester.widget(textFinder);
      expect(textWidget.style?.fontFamily, equals('monospace'));
      expect(find.byTooltip('Variable width font'), findsOneWidget);
    });

    testWidgets('displays warning banner when invalid bytes were replaced', (tester) async {
      const file = OpenedFile(
        name: 'corrupted.txt',
        text: 'Hello \uFFFD world',
        hasInvalidBytes: true,
      );

      await tester.pumpWidget(buildTestWidget(file: file));
      await tester.pumpAndSettle();

      expect(
        find.text('Some characters could not be decoded and were replaced with \uFFFD.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text('Save as note'), findsOneWidget);
    });
  });

  group('FileViewerScreen - Error States', () {
    testWidgets('renders friendly error state for EMPTY file', (tester) async {
      const file = OpenedFile(
        name: 'blank.txt',
        text: '',
        error: 'EMPTY',
      );

      await tester.pumpWidget(buildTestWidget(file: file));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.textContaining('File is empty'), findsOneWidget);
      expect(find.text('Save as note'), findsNothing);
    });

    testWidgets('renders friendly error state for TOO_LARGE file', (tester) async {
      const file = OpenedFile(
        name: 'huge.txt',
        text: '',
        error: 'TOO_LARGE',
      );

      await tester.pumpWidget(buildTestWidget(file: file));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.textContaining('File exceeds 2 MB limit'), findsOneWidget);
      expect(find.text('Save as note'), findsNothing);
    });

    testWidgets('renders friendly error state for BINARY file', (tester) async {
      const file = OpenedFile(
        name: 'app.zip',
        text: '',
        error: 'BINARY',
      );

      await tester.pumpWidget(buildTestWidget(file: file));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.textContaining('Not a text file'), findsOneWidget);
      expect(find.text('Save as note'), findsNothing);
    });

    testWidgets('renders friendly error state for UNREADABLE file', (tester) async {
      const file = OpenedFile(
        name: 'missing.txt',
        text: '',
        error: 'UNREADABLE',
      );

      await tester.pumpWidget(buildTestWidget(file: file));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.textContaining('Unable to read file'), findsOneWidget);
      expect(find.text('Save as note'), findsNothing);
    });
  });

  group('FileViewerScreen - Save As Note', () {
    testWidgets('tapping Save as note inserts note with extracted title and body', (tester) async {
      final fakeRepo = FakeNotesRepository();
      const file = OpenedFile(
        name: 'project_notes.md',
        text: '# Project Spec\nEverything looks great.',
      );

      await tester.pumpWidget(buildTestWidget(file: file, repository: fakeRepo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save as note'));
      await tester.pumpAndSettle();

      expect(fakeRepo.notes.length, equals(1));
      final inserted = fakeRepo.notes.first;
      expect(inserted.title, equals('project_notes'));
      expect(inserted.body, equals('# Project Spec\nEverything looks great.'));
      expect(inserted.isLocked, isFalse);
      expect(inserted.isChecklistMode, isFalse);
    });

    testWidgets('renders DatabaseRecoveryScreen first if database is in recovery needed state', (tester) async {
      const file = OpenedFile(
        name: 'notes.txt',
        text: 'Important note',
      );

      await tester.pumpWidget(buildTestWidget(
        file: file,
        dbStatus: DatabaseStatus.recoveryNeeded,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(DatabaseRecoveryScreen), findsOneWidget);
      expect(find.text('Database Recovery'), findsOneWidget);
      expect(find.text('Important note'), findsNothing);
    });
  });
}
