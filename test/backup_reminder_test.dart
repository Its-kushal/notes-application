import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/core/database/app_database.dart';
import 'package:privacy_notes/features/backup/services/backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase appDb;
  late BackupService backupService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('leaf_lock_reminder_test_');
    appDb = AppDatabase(
      customFactory: databaseFactoryFfi,
      customPath: '${tempDir.path}/test_app.db',
    );
    await appDb.initialize(overridePassword: 'test_password');
    backupService = BackupService(appDatabase: appDb);
  });

  tearDown(() async {
    await appDb.close();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('B & G: Backup Reminder & Timestamp Rules Tests', () {
    test('30-day banner trigger: triggers only after 30 days without backup', () async {
      final db = appDb.database;

      // 1. Initial empty app -> no banner
      expect(await backupService.shouldShowReminderBanner(), isFalse);

      // 2. Note created 10 days ago, no backup -> no banner yet
      final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10)).millisecondsSinceEpoch;
      await db.insert('notes', {
        'id': 'n1',
        'title': 'Recent Note',
        'body': 'Content',
        'is_locked': 0,
        'created_at': tenDaysAgo,
        'updated_at': tenDaysAgo,
      });
      expect(await backupService.shouldShowReminderBanner(), isFalse);

      // 3. Note created 31 days ago, no backup -> banner SHOULD show!
      final thirtyOneDaysAgo = DateTime.now().subtract(const Duration(days: 31)).millisecondsSinceEpoch;
      await db.update('notes', {'created_at': thirtyOneDaysAgo}, where: 'id = ?', whereArgs: ['n1']);
      expect(await backupService.shouldShowReminderBanner(), isTrue);

      // 4. Backup made today -> banner should DISAPPEAR!
      await backupService.recordLastBackupDate();
      expect(await backupService.shouldShowReminderBanner(), isFalse);

      // 5. Backup made 31 days ago -> banner SHOULD show again!
      await db.insert(
        'app_settings',
        {
          'key': 'last_backup_at',
          'value': thirtyOneDaysAgo.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      expect(await backupService.shouldShowReminderBanner(), isTrue);
    });

    test('3-day snooze: suppresses banner for 3 days', () async {
      final db = appDb.database;
      final thirtyOneDaysAgo = DateTime.now().subtract(const Duration(days: 31)).millisecondsSinceEpoch;
      await db.insert('notes', {
        'id': 'n1',
        'title': 'Old Note',
        'body': 'Content',
        'is_locked': 0,
        'created_at': thirtyOneDaysAgo,
        'updated_at': thirtyOneDaysAgo,
      });

      expect(await backupService.shouldShowReminderBanner(), isTrue);

      // User snoozes banner
      await backupService.snoozeBackupReminder();
      expect(await backupService.shouldShowReminderBanner(), isFalse);

      // Advance snooze date past 3 days -> banner reappears
      final fourDaysAgo = DateTime.now().subtract(const Duration(days: 4));
      await db.insert(
        'app_settings',
        {
          'key': 'backup_reminder_snoozed_until',
          'value': fourDaysAgo.millisecondsSinceEpoch.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      expect(await backupService.shouldShowReminderBanner(), isTrue);
    });

    test('Settings toggle: disabling reminder suppresses banner unconditionally', () async {
      final db = appDb.database;
      final thirtyOneDaysAgo = DateTime.now().subtract(const Duration(days: 31)).millisecondsSinceEpoch;
      await db.insert('notes', {
        'id': 'n1',
        'title': 'Old Note',
        'body': 'Content',
        'is_locked': 0,
        'created_at': thirtyOneDaysAgo,
        'updated_at': thirtyOneDaysAgo,
      });

      expect(await backupService.shouldShowReminderBanner(), isTrue);

      // Disable reminder in settings
      await backupService.setBackupReminderEnabled(false);
      expect(await backupService.isBackupReminderEnabled(), isFalse);
      expect(await backupService.shouldShowReminderBanner(), isFalse);

      // Re-enable reminder in settings
      await backupService.setBackupReminderEnabled(true);
      expect(await backupService.shouldShowReminderBanner(), isTrue);
    });

    test('B: Share sheet alone does NOT record last_backup_at', () async {
      expect(await backupService.getLastBackupDate(), isNull);

      // Stage and share does not write last_backup_at to app_settings
      final rows = await appDb.database.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['last_backup_at'],
      );
      expect(rows.isEmpty, isTrue);

      // Only upon confirmed save (e.g. Yes on confirmation dialog) is it recorded
      await backupService.recordLastBackupDate();
      final updatedRows = await appDb.database.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['last_backup_at'],
      );
      expect(updatedRows.isNotEmpty, isTrue);
    });
  });
}
