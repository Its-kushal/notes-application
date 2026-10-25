import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../core/theme/theme_cache_service.dart';
import '../../../notes/domain/note_sort.dart';
import '../../../notes/presentation/controllers/notes_providers.dart';
import '../../data/settings_repository.dart';
import '../../domain/app_settings.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final appDb = ref.watch(appDatabaseProvider);
  return SqlSettingsRepository(appDatabase: appDb);
});

class AppSettingsNotifier extends ChangeNotifier {
  final SettingsRepository _repository;
  AppSettings _settings = AppSettings(themeMode: ThemeCacheService.cachedTheme);
  bool _isLoaded = false;
  bool _isDisposed = false;

  AppSettingsNotifier(this._repository) {
    loadSettings();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  AppSettings get settings => _settings;
  bool get isLoaded => _isLoaded;

  Future<void> loadSettings() async {
    try {
      _settings = await _repository.loadSettings();
    } catch (_) {
      // Keep defaults if uninitialized/error
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
    // Update theme cache asynchronously without blocking settings notification
    ThemeCacheService.saveCachedTheme(_settings.themeMode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _settings = _settings.copyWith(themeMode: mode);
    notifyListeners();
    await _repository.updateSetting(AppSettings.keyThemeMode, mode.name);
    await ThemeCacheService.saveCachedTheme(mode);
  }

  Future<void> setFontSizeMultiplier(double multiplier) async {
    _settings = _settings.copyWith(fontSizeMultiplier: multiplier);
    notifyListeners();
    await _repository.updateSetting(
      AppSettings.keyFontSizeMultiplier,
      multiplier.toString(),
    );
  }

  Future<void> setDefaultSortField(NoteSortField field) async {
    _settings = _settings.copyWith(defaultSortField: field);
    notifyListeners();
    await _repository.updateSetting(AppSettings.keyDefaultSortField, field.name);
  }

  Future<void> setDefaultSortOrder(NoteSortOrder order) async {
    _settings = _settings.copyWith(defaultSortOrder: order);
    notifyListeners();
    await _repository.updateSetting(AppSettings.keyDefaultSortOrder, order.name);
  }

  Future<void> setShowTimestamps(bool show) async {
    _settings = _settings.copyWith(showTimestamps: show);
    notifyListeners();
    await _repository.updateSetting(AppSettings.keyShowTimestamps, show ? '1' : '0');
  }

  Future<void> setShowWordCount(bool show) async {
    _settings = _settings.copyWith(showWordCount: show);
    notifyListeners();
    await _repository.updateSetting(AppSettings.keyShowWordCount, show ? '1' : '0');
  }

  Future<void> setTrashRetentionDays(int days) async {
    _settings = _settings.copyWith(trashRetentionDays: days);
    notifyListeners();
    await _repository.updateSetting(
      AppSettings.keyTrashRetentionDays,
      days.toString(),
    );
  }
}

final settingsProvider = ChangeNotifierProvider<AppSettingsNotifier>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return AppSettingsNotifier(repo);
});
