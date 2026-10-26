import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/theme/theme_cache_service.dart';
import 'features/export/export_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    ThemeCacheService.loadCachedTheme(),
    ExportService.cleanExportCache(),
  ]);
  runApp(
    const ProviderScope(
      child: PrivacyNotesApp(),
    ),
  );
}

