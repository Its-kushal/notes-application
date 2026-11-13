import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Lightweight service to cache theme preference in a plain text file.
/// This enables instant, synchronous-like theme resolution at startup before the
/// hardware-backed encrypted SQLCipher database is initialized and decrypted,
/// completely avoiding the startup system-theme flash.
class ThemeCacheService {
  static File? _cacheFile;
  static ThemeMode _cachedTheme = ThemeMode.system;
  static Directory? overrideDirectory;

  static ThemeMode get cachedTheme => _cachedTheme;

  /// Loads the cached ThemeMode from the plaintext file.
  static Future<ThemeMode> loadCachedTheme() async {
    try {
      final dir = overrideDirectory ?? await getApplicationSupportDirectory();
      _cacheFile = File('${dir.path}/theme_mode_cache.txt');
      if (await _cacheFile!.exists()) {
        final content = await _cacheFile!.readAsString();
        final trimmed = content.trim();
        if (trimmed == ThemeMode.light.name) {
          _cachedTheme = ThemeMode.light;
        } else if (trimmed == ThemeMode.dark.name) {
          _cachedTheme = ThemeMode.dark;
        } else {
          _cachedTheme = ThemeMode.system;
        }
      }
    } catch (_) {
      // Fallback to system default if read fails
      _cachedTheme = ThemeMode.system;
    }
    return _cachedTheme;
  }

  /// Persists the selected ThemeMode to the plaintext cache file.
  static Future<void> saveCachedTheme(ThemeMode mode) async {
    _cachedTheme = mode;
    try {
      if (_cacheFile == null) {
        final dir = overrideDirectory ?? await getApplicationSupportDirectory();
        _cacheFile = File('${dir.path}/theme_mode_cache.txt');
      }
      await _cacheFile!.writeAsString(mode.name, flush: true);
    } catch (_) {
      // Non-critical cache write failure
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    _cacheFile = null;
    _cachedTheme = ThemeMode.system;
    overrideDirectory = null;
  }
}
