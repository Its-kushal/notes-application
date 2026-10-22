import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/database/app_database.dart';
import 'core/database/database_recovery_screen.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/shared_widgets.dart';
import 'features/notes/domain/note.dart';
import 'features/notes/presentation/controllers/notes_providers.dart';
import 'features/notes/presentation/screens/archive_screen.dart';
import 'features/notes/presentation/screens/note_editor_screen.dart';
import 'features/notes/presentation/screens/notes_list_screen.dart';
import 'features/notes/presentation/screens/trash_screen.dart';
import 'features/settings/presentation/controllers/settings_provider.dart';
import 'features/settings/presentation/screens/about_screen.dart';
import 'features/settings/presentation/screens/settings_screen.dart';

final databaseInitProvider = FutureProvider<DatabaseStatus>((ref) async {
  final appDb = ref.watch(appDatabaseProvider);
  return await appDb.initialize();
});

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const NotesListScreen(),
        routes: [
          GoRoute(
            path: 'note/:id',
            builder: (context, state) {
              final note = state.extra as Note? ??
                  Note.create(id: state.pathParameters['id']);
              return NoteEditorScreen(note: note);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/archive',
        builder: (context, state) => const ArchiveScreen(),
      ),
      GoRoute(
        path: '/trash',
        builder: (context, state) => const TrashScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/about',
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        path: '/recovery',
        builder: (context, state) => DatabaseRecoveryScreen(
          onRetry: () => ref.refresh(databaseInitProvider),
        ),
      ),
    ],
  );
});

class PrivacyNotesApp extends ConsumerWidget {
  const PrivacyNotesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dbInitAsync = ref.watch(databaseInitProvider);

    return dbInitAsync.when(
      data: (status) {
        if (status == DatabaseStatus.recoveryNeeded) {
          return MaterialApp(
            title: 'Privacy Notes',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeMode.system,
            home: DatabaseRecoveryScreen(
              onRetry: () => ref.refresh(databaseInitProvider),
            ),
          );
        }
        final router = ref.watch(appRouterProvider);
        final settings = ref.watch(settingsProvider).settings;

        return MaterialApp.router(
          title: 'Privacy Notes',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: settings.themeMode,
          routerConfig: router,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(settings.fontSizeMultiplier),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
      loading: () => MaterialApp(
        title: 'Privacy Notes',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const Scaffold(
          body: LoadingState(),
        ),
      ),
      error: (error, stack) => MaterialApp(
        title: 'Privacy Notes',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: DatabaseRecoveryScreen(
          onRetry: () => ref.refresh(databaseInitProvider),
        ),
      ),
    );
  }
}
