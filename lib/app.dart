import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/database/app_database.dart';
import 'core/database/database_recovery_screen.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_cache_service.dart';
import 'core/widgets/shared_widgets.dart';
import 'features/locked_notes/presentation/controllers/vault_providers.dart';
import 'features/locked_notes/presentation/screens/locked_notes_list_screen.dart';
import 'features/locked_notes/presentation/screens/vault_setup_screen.dart';
import 'features/locked_notes/presentation/screens/vault_unlock_screen.dart';
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
  final status = await appDb.initialize();
  if (status == DatabaseStatus.ready) {
    try {
      final repo = ref.read(notesRepositoryProvider);
      await repo.purgeEmptyNotes();
      final settings = ref.read(settingsProvider).settings;
      await repo.purgeExpiredTrash(retentionDays: settings.trashRetentionDays);
    } catch (_) {}
    try {
      await ref.read(vaultProvider).loadVaultState();
    } catch (_) {}
  }
  return status;
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
        path: '/setup',
        builder: (context, state) {
          final isChangingSecret = state.extra == true;
          return VaultSetupScreen(isChangingSecret: isChangingSecret);
        },
      ),
      GoRoute(
        path: '/unlock',
        builder: (context, state) {
          final onUnlocked = state.extra as VoidCallback?;
          return VaultUnlockScreen(onUnlocked: onUnlocked);
        },
      ),
      GoRoute(
        path: '/locked',
        builder: (context, state) => const LockedNotesListScreen(),
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

class PrivacyNotesApp extends ConsumerStatefulWidget {
  const PrivacyNotesApp({super.key});

  @override
  ConsumerState<PrivacyNotesApp> createState() => _PrivacyNotesAppState();
}

class _PrivacyNotesAppState extends ConsumerState<PrivacyNotesApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final vaultNotifier = ref.read(vaultProvider);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      vaultNotifier.onAppPaused();
    } else if (state == AppLifecycleState.resumed) {
      vaultNotifier.onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dbInitAsync = ref.watch(databaseInitProvider);

    return dbInitAsync.when(
      data: (status) {
        if (status == DatabaseStatus.recoveryNeeded) {
          return MaterialApp(
            title: 'Privacy Notes',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: ThemeCacheService.cachedTheme,
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
            final systemScaler = MediaQuery.textScalerOf(context);
            final effectiveScale = systemScaler.scale(1.0) * settings.fontSizeMultiplier;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(effectiveScale),
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
        themeMode: ThemeCacheService.cachedTheme,
        home: const Scaffold(
          body: LoadingState(),
        ),
      ),
      error: (error, stack) => MaterialApp(
        title: 'Privacy Notes',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeCacheService.cachedTheme,
        home: DatabaseRecoveryScreen(
          onRetry: () => ref.refresh(databaseInitProvider),
        ),
      ),
    );
  }
}

