import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaflock/core/constants/app_info.dart';
import 'package:leaflock/core/theme/app_theme.dart';
import 'package:leaflock/features/backup/domain/backup_manifest.dart';
import 'package:leaflock/features/notes/data/notes_repository.dart';
import 'package:leaflock/features/notes/presentation/controllers/notes_providers.dart';
import 'package:leaflock/features/settings/data/settings_repository.dart';
import 'package:leaflock/features/settings/domain/app_settings.dart';
import 'package:leaflock/features/settings/presentation/controllers/settings_provider.dart';
import 'package:leaflock/features/settings/presentation/screens/about_screen.dart';
import 'package:leaflock/features/settings/presentation/screens/settings_screen.dart';
import 'package:leaflock/l10n/app_localizations.dart';

class _FakeSettingsRepository implements SettingsRepository {
  AppSettings _settings = const AppSettings();

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }

  @override
  Future<void> updateSetting(String key, String value) async {}
}

class _FakeNotesRepository implements NotesRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _readPubspecVersionName() {
  final pubspec = File('pubspec.yaml');
  expect(pubspec.existsSync(), isTrue);
  final match = RegExp(
    r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  expect(match, isNotNull, reason: 'pubspec.yaml must declare version: X.Y.Z+N');
  return match!.group(1)!;
}

void main() {
  group('M7 Version Sync & Release Identity Tests', () {
    test('AppInfo and BackupManifest.currentAppVersion match pubspec.yaml versionName', () {
      final expectedVersionName = _readPubspecVersionName();
      expect(AppInfo.appVersion, equals(expectedVersionName));
      expect(BackupManifest.currentAppVersion, equals(expectedVersionName));
    });

    testWidgets('AboutScreen displays exact pubspec.yaml versionName', (tester) async {
      final expectedVersionName = _readPubspecVersionName();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AboutScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Version $expectedVersionName'), findsOneWidget);
    });

    testWidgets('SettingsScreen displays exact pubspec.yaml versionName in About tile', (tester) async {
      final expectedVersionName = _readPubspecVersionName();
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
            notesRepositoryProvider.overrideWithValue(_FakeNotesRepository()),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Version $expectedVersionName'),
        findsOneWidget,
      );
    });

    test('Release identity uses com.leaflock.app across Android, Kotlin, and Dart', () {
      final gradleFile = File('android/app/build.gradle.kts');
      expect(gradleFile.existsSync(), isTrue);
      final gradleText = gradleFile.readAsStringSync();
      expect(gradleText.contains('namespace = "com.leaflock.app"'), isTrue);
      expect(gradleText.contains('applicationId = "com.leaflock.app"'), isTrue);

      final mainActivity = File('android/app/src/main/kotlin/com/leaflock/app/MainActivity.kt');
      expect(mainActivity.existsSync(), isTrue);
      final kotlinText = mainActivity.readAsStringSync();
      expect(kotlinText.contains('package com.leaflock.app'), isTrue);
      expect(kotlinText.contains('CHANNEL = "com.leaflock.app/security"'), isTrue);

      final oldKotlinDir = Directory('android/app/src/main/kotlin/com/privacynotes');
      expect(oldKotlinDir.existsSync(), isFalse);
    });
  });
}
