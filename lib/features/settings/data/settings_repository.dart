import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../../core/database/app_database.dart';
import '../domain/app_settings.dart';

abstract class SettingsRepository {
  Future<AppSettings> loadSettings();
  Future<void> saveSettings(AppSettings settings);
  Future<void> updateSetting(String key, String value);
}

class SqlSettingsRepository implements SettingsRepository {
  final AppDatabase appDatabase;

  SqlSettingsRepository({required this.appDatabase});

  Database get _db => appDatabase.database;

  @override
  Future<AppSettings> loadSettings() async {
    final rows = await _db.query('app_settings');
    final Map<String, String> map = {};
    for (final row in rows) {
      final key = row['key'] as String?;
      final value = row['value'] as String?;
      if (key != null && value != null) {
        map[key] = value;
      }
    }
    return AppSettings.fromMap(map);
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    final map = settings.toMap();
    await _db.transaction((txn) async {
      for (final entry in map.entries) {
        await txn.insert(
          'app_settings',
          {'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> updateSetting(String key, String value) async {
    await _db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
