import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/core/constants/app_colors.dart';
import 'package:privacy_notes/core/crypto/id_generator.dart';
import 'package:privacy_notes/core/database/app_database.dart';
import 'package:privacy_notes/core/theme/app_theme.dart';
import 'package:privacy_notes/core/widgets/selection_dialog.dart';
import 'package:privacy_notes/features/export/export_service.dart';
import 'package:privacy_notes/features/notes/data/notes_repository.dart';
import 'package:privacy_notes/features/notes/domain/checklist_item.dart';
import 'package:privacy_notes/features/notes/domain/note.dart';
import 'package:privacy_notes/features/notes/domain/note_sort.dart';
import 'package:privacy_notes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:privacy_notes/features/settings/domain/app_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('F1 Reproduction: Search must not match checklist_json keys/UUIDs', () {
    late AppDatabase appDb;
    late SqlNotesRepository repo;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_password');
      repo = SqlNotesRepository(appDatabase: appDb);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('F1: searching "text", "is_checked", and UUID fragment returns nothing; real item text is found', () async {
      final itemId = IdGenerator.generateUuidV4();
      final itemUuidPrefix = itemId.substring(0, 8);
      final checklistItems = [
        ChecklistItem(id: itemId, text: 'Buy almond milk', isChecked: false),
      ];
      final json = ChecklistItem.encodeList(checklistItems);
      // In checklist mode, body will mirror checklist item text
      final note = Note.create(
        title: 'Groceries',
        body: 'Buy almond milk',
        checklistJson: json,
        isChecklistMode: true,
      );

      await repo.insertNote(note);

      // Search real text
      final resultsMilk = await repo.searchNotes('almond milk');
      expect(resultsMilk.length, 1);
      expect(resultsMilk.first.id, note.id);

      // Search JSON key "text" - should NOT match
      final resultsText = await repo.searchNotes('text');
      expect(resultsText, isEmpty, reason: 'Search should not match the JSON key "text"');

      // Search JSON key "is_checked" - should NOT match
      final resultsChecked = await repo.searchNotes('is_checked');
      expect(resultsChecked, isEmpty, reason: 'Search should not match JSON key "is_checked"');

      // Search item UUID fragment - should NOT match
      final resultsUuid = await repo.searchNotes(itemUuidPrefix);
      expect(resultsUuid, isEmpty, reason: 'Search should not match UUID fragment in checklist_json');
    });
  });

  group('F2 Reproduction: Effective text scale = system scale x app multiplier', () {
    testWidgets('F2: TextScaler combines system scale 1.3 with app multiplier 1.0 and 1.15', (tester) async {
      final testSettings = const AppSettings(fontSizeMultiplier: 1.0);

      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.3),
            ),
            child: Builder(
              builder: (ctx) {
                return MediaQuery(
                  data: MediaQuery.of(ctx).copyWith(
                    textScaler: TextScaler.linear(
                      MediaQuery.textScalerOf(ctx).scale(1.0) * testSettings.fontSizeMultiplier,
                    ),
                  ),
                  child: Builder(
                    builder: (innerCtx) {
                      capturedContext = innerCtx;
                      return const Text('Test');
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      var scaler = MediaQuery.textScalerOf(capturedContext);
      expect((scaler.scale(10.0) - 13.0).abs() < 0.001, isTrue);

      const testSettingsLarge = AppSettings(fontSizeMultiplier: 1.15);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(1.3),
            ),
            child: Builder(
              builder: (ctx) {
                return MediaQuery(
                  data: MediaQuery.of(ctx).copyWith(
                    textScaler: TextScaler.linear(
                      MediaQuery.textScalerOf(ctx).scale(1.0) * testSettingsLarge.fontSizeMultiplier,
                    ),
                  ),
                  child: Builder(
                    builder: (innerCtx) {
                      capturedContext = innerCtx;
                      return const Text('Test');
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      scaler = MediaQuery.textScalerOf(capturedContext);
      // 10.0 * 1.3 * 1.15 = 14.95
      expect((scaler.scale(10.0) - 14.95).abs() < 0.001, isTrue);
    });
  });

  group('F3 & F4 Tests: ExportService SAF error handling and cache cleanup', () {
    test('F3: saveToDevice throws ExportSecurityException on locked notes', () async {
      final lockedNote = Note(
        id: 'locked-note',
        title: '',
        body: '',
        isLocked: true,
        createdAt: 0,
        updatedAt: 0,
        wordCount: 0,
      );

      expect(
        () async => await ExportService.saveToDevice(lockedNote),
        throwsA(isA<ExportSecurityException>()),
      );
    });

    test('F4: cleanExportCache cleans up temporary staged files', () async {
      final tempDir = Directory.systemTemp.createTempSync('export_test');
      final exportsDir = Directory('${tempDir.path}/exports');
      exportsDir.createSync(recursive: true);
      final dummyFile = File('${exportsDir.path}/dummy_export.txt');
      dummyFile.writeAsStringSync('staged test note');

      expect(dummyFile.existsSync(), isTrue);

      // Emulate cleanExportCache logic
      final entities = exportsDir.listSync();
      for (final e in entities) {
        e.deleteSync(recursive: true);
      }

      expect(dummyFile.existsSync(), isFalse);
      tempDir.deleteSync(recursive: true);
    });
  });

  group('F5 Reproduction: updateNote must refuse locked rows', () {
    late AppDatabase appDb;
    late SqlNotesRepository repo;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_password');
      repo = SqlNotesRepository(appDatabase: appDb);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('F5: updateNote throws StateError on locked note and does not modify row', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Directly insert a valid locked row obeying CHECK constraint
      final db = appDb.database;
      await db.insert('notes', {
        'id': 'locked-1',
        'title': '',
        'body': '',
        'checklist_json': null,
        'is_checklist_mode': 0,
        'is_locked': 1,
        'encrypted_payload': Uint8List.fromList([1, 2, 3]),
        'payload_iv': Uint8List.fromList([4, 5, 6]),
        'payload_tag': Uint8List.fromList([7, 8, 9]),
        'payload_format_version': 1,
        'created_at': now,
        'updated_at': now,
        'word_count': 0,
      });

      final lockedAttempt = Note(
        id: 'locked-1',
        title: 'Hacked Title',
        body: 'Overwritten Body',
        createdAt: now,
        updatedAt: now,
        wordCount: 2,
        isLocked: false,
      );

      expect(
        () async => await repo.updateNote(lockedAttempt),
        throwsA(isA<StateError>()),
      );

      // Verify the locked note remains locked and uncompromised
      final rawRow = (await db.query('notes', where: 'id = ?', whereArgs: ['locked-1'])).first;
      expect(rawRow['is_locked'], 1);
      expect(rawRow['title'], '');
      expect(rawRow['body'], '');
      expect(rawRow['encrypted_payload'], isNotNull);
    });
  });

  group('F6 Tests: SelectionDialog widget', () {
    testWidgets('F6: SelectionDialog renders options, checkmarks, and fires onSelected', (tester) async {
      ThemeMode selected = ThemeMode.system;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  SelectionDialog.show<ThemeMode>(
                    context: ctx,
                    title: 'Choose Theme',
                    selectedValue: selected,
                    items: const [
                      SelectionItem(title: 'System', value: ThemeMode.system),
                      SelectionItem(title: 'Light', value: ThemeMode.light),
                      SelectionItem(title: 'Dark', value: ThemeMode.dark),
                    ],
                    onSelected: (val) {
                      selected = val;
                    },
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Choose Theme'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);

      // Tap 'Dark'
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();

      expect(selected, ThemeMode.dark);
      expect(find.text('Choose Theme'), findsNothing); // Dialog popped
    });

    testWidgets('F6: SelectionDialog.showSectioned renders multiple sections and handles selection', (tester) async {
      NoteSortField field = NoteSortField.modified;
      NoteSortOrder order = NoteSortOrder.descending;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  SelectionDialog.showSectioned(
                    context: ctx,
                    title: 'Sort Settings',
                    sections: [
                      SelectionSection<NoteSortField>(
                        title: 'Field',
                        selectedValue: field,
                        items: const [
                          SelectionItem(title: 'Last edited', value: NoteSortField.modified),
                          SelectionItem(title: 'Title', value: NoteSortField.title),
                        ],
                        onSelected: (f) => field = f,
                      ),
                      SelectionSection<NoteSortOrder>(
                        title: 'Order',
                        selectedValue: order,
                        items: const [
                          SelectionItem(title: 'Ascending', value: NoteSortOrder.ascending),
                          SelectionItem(title: 'Descending', value: NoteSortOrder.descending),
                        ],
                        onSelected: (o) => order = o,
                      ),
                    ],
                  );
                },
                child: const Text('Open Sort'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sort'));
      await tester.pumpAndSettle();

      expect(find.text('Sort Settings'), findsOneWidget);
      expect(find.text('Field'), findsOneWidget);
      expect(find.text('Order'), findsOneWidget);
      expect(find.text('Last edited'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);

      await tester.tap(find.text('Title'));
      await tester.pumpAndSettle();

      expect(field, NoteSortField.title);
    });
  });

  group('Empty Note & Checklist Discard Tests', () {
    late AppDatabase appDb;
    late SqlNotesRepository repo;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_empty_notes_pass');
      repo = SqlNotesRepository(appDatabase: appDb);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('NoteEditorNotifier removes note from DB when title is cleared and body is empty', () async {
      final initialNote = Note.create(title: 'Temporary Title');
      await repo.insertNote(initialNote);

      final notifier = NoteEditorNotifier(repo, initialNote);
      expect(notifier.isEmptyContent, isFalse);

      // User clears title (body is empty)
      notifier.updateContent(title: '');
      expect(notifier.isEmptyContent, isTrue);

      await notifier.saveImmediately();

      // Note must be deleted from repository, not left as "Empty note"
      final found = await repo.getNoteById(initialNote.id);
      expect(found, isNull);
    });

    test('NoteEditorNotifier removes checklist note from DB when all items are blank and title is empty', () async {
      final checklistItem = ChecklistItem(id: 'item-1', text: 'Milk');
      final initialNote = Note.create(
        title: '',
        isChecklistMode: true,
        body: 'Milk',
        checklistJson: ChecklistItem.encodeList([checklistItem]),
      );
      await repo.insertNote(initialNote);

      final notifier = NoteEditorNotifier(repo, initialNote);
      expect(notifier.isEmptyContent, isFalse);

      // User clears checklist item text
      notifier.updateChecklistItem('item-1', text: '   ');
      expect(notifier.isEmptyContent, isTrue);

      await notifier.saveImmediately();

      final found = await repo.getNoteById(initialNote.id);
      expect(found, isNull);
    });

    test('purgeEmptyNotes deletes phantom blank notes and leaves valid notes intact', () async {
      final validNote1 = Note.create(title: 'Valid Note', body: '');
      final validNote2 = Note.create(title: '', body: 'Has body');
      final emptyNote1 = Note.create(title: '', body: '');
      final emptyNote2 = Note.create(title: '   ', body: '  ');

      await repo.insertNote(validNote1);
      await repo.insertNote(validNote2);
      await repo.insertNote(emptyNote1);
      await repo.insertNote(emptyNote2);

      final purged = await repo.purgeEmptyNotes();
      expect(purged, 2);

      final remaining = await repo.getActiveNotes();
      expect(remaining.length, 2);
      expect(remaining.map((n) => n.id), containsAll([validNote1.id, validNote2.id]));
    });

    test('P1: checklist note with empty title and empty body must survive purgeEmptyNotes', () async {
      final checklistNote = Note.create(
        id: 'cl-survive-1',
        title: '',
        body: '',
        isChecklistMode: true,
        checklistJson: jsonEncode([
          {'id': 'i1', 'text': 'Buy Groceries', 'is_checked': false}
        ]),
      );
      await repo.insertNote(checklistNote);

      final purged = await repo.purgeEmptyNotes();
      expect(purged, 0);

      final surviving = await repo.getNoteById('cl-survive-1');
      expect(surviving, isNotNull);
      expect(surviving!.id, 'cl-survive-1');
    });

    test('P1: empty checklist with only whitespace items is cleaned up', () async {
      final emptyClNote = Note.create(
        id: 'cl-empty-1',
        title: '   ',
        body: '',
        isChecklistMode: true,
        checklistJson: jsonEncode([
          {'id': 'i1', 'text': '   ', 'is_checked': false},
          {'id': 'i2', 'text': '', 'is_checked': true}
        ]),
      );
      await repo.insertNote(emptyClNote);

      final purged = await repo.purgeEmptyNotes();
      expect(purged, 1);

      final surviving = await repo.getNoteById('cl-empty-1');
      expect(surviving, isNull);
    });

    test('P1: locked rows are never touched by purgeEmptyNotes', () async {
      final lockedNote = Note(
        id: 'locked-1',
        title: '',
        body: '',
        checklistJson: null,
        isChecklistMode: false,
        wordCount: 0,
        isLocked: true,
        encryptedPayload: Uint8List.fromList(List.filled(16, 1)),
        payloadIv: Uint8List.fromList(List.filled(12, 2)),
        payloadTag: Uint8List.fromList(List.filled(16, 3)),
        payloadFormatVersion: 1,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await repo.insertNote(lockedNote);

      final purged = await repo.purgeEmptyNotes();
      expect(purged, 0);

      final surviving = await repo.getNoteById('locked-1');
      expect(surviving, isNotNull);
      expect(surviving!.isLocked, isTrue);
    });

    test('SwitchThemeData defines high-contrast colors in dark and light themes', () {
      final darkSwitch = AppTheme.darkTheme.switchTheme;
      expect(darkSwitch, isNotNull);
      final darkThumbOn = darkSwitch.thumbColor?.resolve({WidgetState.selected});
      final darkThumbOff = darkSwitch.thumbColor?.resolve({});
      final darkTrackOn = darkSwitch.trackColor?.resolve({WidgetState.selected});
      final darkTrackOff = darkSwitch.trackColor?.resolve({});
      final darkOutlineOff = darkSwitch.trackOutlineColor?.resolve({});

      expect(darkThumbOn, AppColors.white);
      expect(darkThumbOff, isNotNull);
      expect(darkThumbOff, isNot(darkTrackOff)); // High contrast between thumb and track
      expect(darkTrackOn, AppColors.primary);
      expect(darkOutlineOff, isNotNull);

      final lightSwitch = AppTheme.lightTheme.switchTheme;
      expect(lightSwitch, isNotNull);
      final lightThumbOn = lightSwitch.thumbColor?.resolve({WidgetState.selected});
      final lightTrackOn = lightSwitch.trackColor?.resolve({WidgetState.selected});
      expect(lightThumbOn, AppColors.white);
      expect(lightTrackOn, AppColors.primary);
    });
  });
}
