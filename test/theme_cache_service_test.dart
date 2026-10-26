import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/core/theme/theme_cache_service.dart';

void main() {
  group('ThemeCacheService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('theme_cache_test_');
      ThemeCacheService.overrideDirectory = tempDir;
    });

    tearDown(() async {
      ThemeCacheService.resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('saves and loads theme mode from injectable directory without FLUTTER_TEST check', () async {
      expect(ThemeCacheService.cachedTheme, ThemeMode.system);

      await ThemeCacheService.saveCachedTheme(ThemeMode.dark);
      expect(ThemeCacheService.cachedTheme, ThemeMode.dark);

      // Verify file was written to the injected directory
      final cacheFile = File('${tempDir.path}/theme_mode_cache.txt');
      expect(await cacheFile.exists(), isTrue);
      expect(await cacheFile.readAsString(), 'dark');

      // Reset in-memory cache and reload from disk
      ThemeCacheService.resetForTesting();
      ThemeCacheService.overrideDirectory = tempDir;
      final loaded = await ThemeCacheService.loadCachedTheme();
      expect(loaded, ThemeMode.dark);
    });

    test('gracefully falls back to system theme on corrupted cache file', () async {
      final cacheFile = File('${tempDir.path}/theme_mode_cache.txt');
      await cacheFile.writeAsString('corrupted_content');

      final loaded = await ThemeCacheService.loadCachedTheme();
      expect(loaded, ThemeMode.system);
    });
  });
}
