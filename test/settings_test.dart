import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:privacy_notes/core/database/app_database.dart';
import 'package:privacy_notes/core/theme/app_theme.dart';
import 'package:privacy_notes/features/notes/data/notes_repository.dart';
import 'package:privacy_notes/features/notes/domain/note.dart';
import 'package:privacy_notes/features/notes/domain/note_sort.dart';
import 'package:privacy_notes/features/notes/presentation/controllers/notes_providers.dart';
import 'package:privacy_notes/features/notes/presentation/screens/trash_screen.dart';
import 'package:privacy_notes/features/settings/data/settings_repository.dart';
import 'package:privacy_notes/features/settings/domain/app_settings.dart';
import 'package:privacy_notes/features/settings/presentation/controllers/settings_provider.dart';
import 'package:privacy_notes/features/settings/presentation/screens/settings_screen.dart';

class FakeSettingsRepository implements SettingsRepository {
  AppSettings _settings;
  FakeSettingsRepository([this._settings = const AppSettings()]);

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

class FakeNotesRepo implements NotesRepository {
  final List<Note> notes = [];

  @override
  Future<Note> insertNote(Note note) async {
    notes.add(note);
    return note;
  }

  @override
  Future<List<Note>> getTrashedNotes() async {
    return notes.where((n) => n.isTrashed).toList();
  }

  @override
  Future<int> purgeEmptyNotes() async {
    final before = notes.length;
    notes.removeWhere((n) => n.title.trim().isEmpty && n.body.trim().isEmpty);
    return before - notes.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Settings Persistence & Repository Tests', () {
    late AppDatabase appDb;
    late SqlSettingsRepository settingsRepo;
    late SqlNotesRepository notesRepo;

    setUp(() async {
      appDb = AppDatabase(
        customFactory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath,
      );
      await appDb.initialize(overridePassword: 'test_settings_pass');
      settingsRepo = SqlSettingsRepository(appDatabase: appDb);
      notesRepo = SqlNotesRepository(appDatabase: appDb);
    });

    tearDown(() async {
      await appDb.close();
    });

    test('Default settings load correctly when table is empty', () async {
      final settings = await settingsRepo.loadSettings();
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.fontSizeMultiplier, 1.0);
      expect(settings.defaultSortField, NoteSortField.modified);
      expect(settings.defaultSortOrder, NoteSortOrder.descending);
      expect(settings.showTimestamps, isTrue);
      expect(settings.showWordCount, isTrue);
      expect(settings.trashRetentionDays, 30);
    });

    test('Settings persist and survive reload across all fields', () async {
      const customSettings = AppSettings(
        themeMode: ThemeMode.dark,
        fontSizeMultiplier: 1.3,
        defaultSortField: NoteSortField.title,
        defaultSortOrder: NoteSortOrder.ascending,
        showTimestamps: false,
        showWordCount: false,
        trashRetentionDays: 14,
      );

      await settingsRepo.saveSettings(customSettings);

      // Reload from database
      final loaded = await settingsRepo.loadSettings();
      expect(loaded.themeMode, ThemeMode.dark);
      expect(loaded.fontSizeMultiplier, 1.3);
      expect(loaded.defaultSortField, NoteSortField.title);
      expect(loaded.defaultSortOrder, NoteSortOrder.ascending);
      expect(loaded.showTimestamps, isFalse);
      expect(loaded.showWordCount, isFalse);
      expect(loaded.trashRetentionDays, 14);
    });

    test('Retention setting changes trash purge behavior', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final twentyDaysAgo = now - (20 * 24 * 60 * 60 * 1000);
      final tenDaysAgo = now - (10 * 24 * 60 * 60 * 1000);

      // Note 1: 20 days old in trash
      final note20d = Note.create(title: 'Note 20d').copyWith(trashedAt: twentyDaysAgo);
      // Note 2: 10 days old in trash
      final note10d = Note.create(title: 'Note 10d').copyWith(trashedAt: tenDaysAgo);

      await notesRepo.insertNote(note20d);
      await notesRepo.insertNote(note10d);

      // With default 30 days retention, neither note is purged
      var purged = await notesRepo.purgeExpiredTrash(retentionDays: 30);
      expect(purged, 0);

      // Change retention to 14 days
      await settingsRepo.updateSetting(AppSettings.keyTrashRetentionDays, '14');
      final settings = await settingsRepo.loadSettings();
      expect(settings.trashRetentionDays, 14);

      // Now purging with 14 days purges note20d (20 > 14) but keeps note10d (10 < 14)
      purged = await notesRepo.purgeExpiredTrash(retentionDays: settings.trashRetentionDays);
      expect(purged, 1);

      expect(await notesRepo.getNoteById(note20d.id), isNull);
      expect(await notesRepo.getNoteById(note10d.id), isNotNull);
    });
  });

  group('SettingsScreen & TrashScreen Retention UI Widget Tests', () {
    late FakeSettingsRepository fakeSettingsRepo;
    late FakeNotesRepo notesRepo;

    setUp(() {
      fakeSettingsRepo = FakeSettingsRepository();
      notesRepo = FakeNotesRepo();
    });

    testWidgets('SettingsScreen renders sections, controls, and M4 auto-lock placeholder', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(fakeSettingsRepo),
            notesRepositoryProvider.overrideWithValue(notesRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check section headers (SectionHeader formats uppercase)
      expect(find.text('APPEARANCE'), findsOneWidget);
      expect(find.text('NOTES & DISPLAY'), findsOneWidget);
      expect(find.text('TRASH & STORAGE'), findsOneWidget);
      expect(find.text('SECURITY'), findsOneWidget);
      expect(find.text('INFORMATION'), findsOneWidget);

      // Check Security section: Set up locked notes tile (M4)
      expect(find.text('Set up locked notes'), findsOneWidget);
      expect(find.text('Protect sensitive notes with a PIN or pattern'), findsOneWidget);

      // Open Theme dialog
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('System default')), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Light')), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('Dark')), findsOneWidget);

      // Select Dark in dialog
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Dark')));
      await tester.pumpAndSettle();
      expect(find.text('Dark'), findsOneWidget);

      // Open Retention Dialog
      await tester.tap(find.text('Trash retention'));
      await tester.pumpAndSettle();
      expect(find.text('Trash retention period'), findsOneWidget);
      expect(find.text('7 days'), findsOneWidget);
      expect(find.text('14 days'), findsOneWidget);
      expect(find.text('30 days (Default)'), findsOneWidget);

      // Select 14 days
      await tester.tap(find.text('14 days'));
      await tester.pumpAndSettle();
      expect(find.text('14 days (auto-purge expired notes)'), findsOneWidget);
    });

    testWidgets('TrashScreen shows empty view when trash is empty', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(fakeSettingsRepo),
            notesRepositoryProvider.overrideWithValue(notesRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const TrashScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trash is empty'), findsOneWidget);
    });

    testWidgets('TrashScreen info banner shows configured retention days from settings', (tester) async {
      // Set retention to 14 days in settings
      await fakeSettingsRepo.updateSetting(AppSettings.keyTrashRetentionDays, '14');

      // Add a trashed note so the banner is visible
      await notesRepo.insertNote(Note.create(title: 'Trash Item').copyWith(
        trashedAt: DateTime.now().millisecondsSinceEpoch,
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(fakeSettingsRepo),
            notesRepositoryProvider.overrideWithValue(notesRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const TrashScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Banner text must explicitly reflect the 14 days setting!
      expect(
        find.text('Items in trash are automatically purged after 14 days.'),
        findsOneWidget,
      );
    });
  });
}
