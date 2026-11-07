import 'package:flutter/material.dart';
import '../../notes/domain/note_sort.dart';

/// Domain entity representing persistent user preferences and app settings.
class AppSettings {
  final ThemeMode themeMode;
  final double fontSizeMultiplier;
  final NoteSortField defaultSortField;
  final NoteSortOrder defaultSortOrder;
  final bool showTimestamps;
  final bool showWordCount;
  final int trashRetentionDays;
  final bool firstRunDone;
  final int? firstRunAt;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.fontSizeMultiplier = 1.0,
    this.defaultSortField = NoteSortField.modified,
    this.defaultSortOrder = NoteSortOrder.descending,
    this.showTimestamps = true,
    this.showWordCount = true,
    this.trashRetentionDays = 30,
    this.firstRunDone = false,
    this.firstRunAt,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    double? fontSizeMultiplier,
    NoteSortField? defaultSortField,
    NoteSortOrder? defaultSortOrder,
    bool? showTimestamps,
    bool? showWordCount,
    int? trashRetentionDays,
    bool? firstRunDone,
    int? firstRunAt,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      fontSizeMultiplier: fontSizeMultiplier ?? this.fontSizeMultiplier,
      defaultSortField: defaultSortField ?? this.defaultSortField,
      defaultSortOrder: defaultSortOrder ?? this.defaultSortOrder,
      showTimestamps: showTimestamps ?? this.showTimestamps,
      showWordCount: showWordCount ?? this.showWordCount,
      trashRetentionDays: trashRetentionDays ?? this.trashRetentionDays,
      firstRunDone: firstRunDone ?? this.firstRunDone,
      firstRunAt: firstRunAt ?? this.firstRunAt,
    );
  }

  // Key constants for SQLite app_settings key-value storage
  static const String keyThemeMode = 'theme_mode';
  static const String keyFontSizeMultiplier = 'font_size_multiplier';
  static const String keyDefaultSortField = 'default_sort_field';
  static const String keyDefaultSortOrder = 'default_sort_order';
  static const String keyShowTimestamps = 'show_timestamps';
  static const String keyShowWordCount = 'show_word_count';
  static const String keyTrashRetentionDays = 'trash_retention_days';
  static const String keyFirstRunDone = 'first_run_done';
  static const String keyFirstRunAt = 'first_run_at';

  Map<String, String> toMap() {
    final map = {
      keyThemeMode: themeMode.name,
      keyFontSizeMultiplier: fontSizeMultiplier.toString(),
      keyDefaultSortField: defaultSortField.name,
      keyDefaultSortOrder: defaultSortOrder.name,
      keyShowTimestamps: showTimestamps ? '1' : '0',
      keyShowWordCount: showWordCount ? '1' : '0',
      keyTrashRetentionDays: trashRetentionDays.toString(),
      keyFirstRunDone: firstRunDone ? '1' : '0',
    };
    if (firstRunAt != null) {
      map[keyFirstRunAt] = firstRunAt.toString();
    }
    return map;
  }

  factory AppSettings.fromMap(Map<String, String> map) {
    ThemeMode theme = ThemeMode.system;
    final themeStr = map[keyThemeMode];
    if (themeStr == 'light') {
      theme = ThemeMode.light;
    } else if (themeStr == 'dark') {
      theme = ThemeMode.dark;
    }

    double fontScale = 1.0;
    if (map[keyFontSizeMultiplier] != null) {
      fontScale = double.tryParse(map[keyFontSizeMultiplier]!) ?? 1.0;
    }

    NoteSortField sortField = NoteSortField.modified;
    if (map[keyDefaultSortField] != null) {
      sortField = NoteSortField.values.firstWhere(
        (e) => e.name == map[keyDefaultSortField],
        orElse: () => NoteSortField.modified,
      );
    }

    NoteSortOrder sortOrder = NoteSortOrder.descending;
    if (map[keyDefaultSortOrder] != null) {
      sortOrder = NoteSortOrder.values.firstWhere(
        (e) => e.name == map[keyDefaultSortOrder],
        orElse: () => NoteSortOrder.descending,
      );
    }

    final showTimes = (map[keyShowTimestamps] ?? '1') == '1';
    final showWords = (map[keyShowWordCount] ?? '1') == '1';
    final retention = int.tryParse(map[keyTrashRetentionDays] ?? '30') ?? 30;
    final firstDone = (map[keyFirstRunDone] ?? '0') == '1';
    final firstAt = map[keyFirstRunAt] != null ? int.tryParse(map[keyFirstRunAt]!) : null;

    return AppSettings(
      themeMode: theme,
      fontSizeMultiplier: fontScale,
      defaultSortField: sortField,
      defaultSortOrder: sortOrder,
      showTimestamps: showTimes,
      showWordCount: showWords,
      trashRetentionDays: retention,
      firstRunDone: firstDone,
      firstRunAt: firstAt,
    );
  }
}
