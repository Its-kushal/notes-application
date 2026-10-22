import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/shared_widgets.dart';
import '../controllers/notes_providers.dart';
import '../widgets/note_card.dart';
import '../widgets/notes_empty_view.dart';

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(archiveProvider.notifier).loadArchive();
    });
  }

  @override
  Widget build(BuildContext context) {
    final archiveNotifier = ref.watch(archiveProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Archive'),
      ),
      body: archiveNotifier.isLoading
          ? const LoadingState()
          : archiveNotifier.errorMessage != null
              ? ErrorState(
                  message: archiveNotifier.errorMessage!,
                  onRetry: () => archiveNotifier.loadArchive(),
                )
              : archiveNotifier.archivedNotes.isEmpty
                  ? const NotesEmptyView(
                      icon: Icons.archive_outlined,
                      customTitle: 'Archive is empty',
                      customSubtitle: 'Notes you archive will appear here.',
                    )
                  : RefreshIndicator(
                      onRefresh: () => archiveNotifier.loadArchive(),
                      child: ListView.builder(
                        padding: const EdgeInsets.only(
                          top: AppSpacing.sm,
                          bottom: AppSpacing.xxl * 2,
                        ),
                        itemCount: archiveNotifier.archivedNotes.length,
                        itemBuilder: (context, index) {
                          final note = archiveNotifier.archivedNotes[index];
                          return NoteCard(
                            note: note,
                            onTap: () {
                              context.push('/note/${note.id}', extra: note);
                            },
                            // B6: Pin button hidden on Archive screen
                            onTogglePin: null,
                            onArchive: () async {
                              await archiveNotifier.unarchiveNote(note.id);
                              await ref.read(notesListProvider).loadNotes();
                              if (context.mounted) {
                                AppSnackBar.show(
                                  context,
                                  message: 'Note unarchived',
                                  actionLabel: 'Undo',
                                  onAction: () async {
                                    await ref
                                        .read(notesListProvider)
                                        .archiveNote(note.id);
                                    await archiveNotifier.loadArchive();
                                  },
                                );
                              }
                            },
                            onDelete: () async {
                              await archiveNotifier.trashNote(note.id);
                              await ref.read(notesListProvider).loadNotes();
                              if (context.mounted) {
                                AppSnackBar.show(
                                  context,
                                  message: 'Note moved to trash',
                                  actionLabel: 'Undo',
                                  onAction: () async {
                                    await ref
                                        .read(notesListProvider)
                                        .restoreNote(note.id);
                                    await archiveNotifier.loadArchive();
                                  },
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}
