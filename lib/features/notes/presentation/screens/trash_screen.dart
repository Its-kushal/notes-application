import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/shared_widgets.dart';
import '../../../settings/presentation/controllers/settings_provider.dart';
import '../controllers/notes_providers.dart';
import '../widgets/notes_empty_view.dart';

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(trashProvider.notifier).loadTrash();
    });
  }

  String _formatTrashedDate(int? timestamp) {
    if (timestamp == null) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('MMM d, yyyy h:mm a').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trashNotifier = ref.watch(trashProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          if (trashNotifier.trashedNotes.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                final confirm = await ConfirmDialog.show(
                  context,
                  title: 'Empty trash?',
                  message:
                      'All notes in trash will be permanently deleted. This action cannot be undone.',
                  confirmText: 'Empty trash',
                  isDestructive: true,
                );

                if (confirm == true) {
                  await trashNotifier.emptyTrash();
                  await ref.read(notesListProvider).loadNotes();
                  if (context.mounted) {
                    AppSnackBar.show(
                      context,
                      message: 'Trash emptied',
                    );
                  }
                }
              },
              icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.error),
              label: const Text(
                'Empty',
                style: TextStyle(color: AppColors.error),
              ),
            ),
        ],
      ),
      body: trashNotifier.isLoading
          ? const LoadingState()
          : trashNotifier.errorMessage != null
              ? ErrorState(
                  message: trashNotifier.errorMessage!,
                  onRetry: () => trashNotifier.loadTrash(),
                )
              : trashNotifier.trashedNotes.isEmpty
                  ? const NotesEmptyView(
                      icon: Icons.delete_outline,
                      customTitle: 'Trash is empty',
                      customSubtitle: 'Notes moved to trash will appear here.',
                    )
                  : Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.md,
                          ),
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              AppSpacing.hGapSm,
                              Expanded(
                                child: Text(
                                  'Items in trash are automatically purged after ${ref.watch(settingsProvider).settings.trashRetentionDays} days.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: () => trashNotifier.loadTrash(),
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.sm,
                              ),
                              itemCount: trashNotifier.trashedNotes.length,
                              itemBuilder: (context, index) {
                                final note = trashNotifier.trashedNotes[index];
                                final displayTitle = note.title.trim().isNotEmpty
                                    ? note.title
                                    : (note.body.trim().isNotEmpty
                                        ? 'Untitled'
                                        : 'Empty note');

                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.lg,
                                    vertical: AppSpacing.xs + 2,
                                  ),
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: AppSpacing.borderRadiusMd,
                                  ),
                                  child: Padding(
                                    padding: AppSpacing.paddingLg,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                displayTitle,
                                                style: theme
                                                    .textTheme.titleMedium
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.restore_outlined),
                                              tooltip: 'Restore note',
                                              onPressed: () async {
                                                await trashNotifier
                                                    .restoreNote(note.id);
                                                await ref
                                                    .read(notesListProvider)
                                                    .loadNotes();
                                                if (context.mounted) {
                                                  AppSnackBar.show(
                                                    context,
                                                    message: 'Note restored',
                                                    actionLabel: 'Undo',
                                                    onAction: () async {
                                                      await ref
                                                          .read(notesListProvider)
                                                          .trashNote(note.id);
                                                      await trashNotifier
                                                          .loadTrash();
                                                    },
                                                  );
                                                }
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete_forever_outlined,
                                                color: AppColors.error,
                                              ),
                                              tooltip: 'Delete permanently',
                                              onPressed: () async {
                                                final confirm =
                                                    await ConfirmDialog.show(
                                                  context,
                                                  title:
                                                      'Delete permanently?',
                                                  message:
                                                      'This note will be permanently erased from your encrypted database.',
                                                  confirmText: 'Delete',
                                                  isDestructive: true,
                                                );

                                                if (confirm == true) {
                                                  await trashNotifier
                                                      .deletePermanently(note.id);
                                                  await ref
                                                      .read(notesListProvider)
                                                      .loadNotes();
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                        if (note.body.trim().isNotEmpty) ...[
                                          AppSpacing.vGapSm,
                                          Text(
                                            note.body,
                                            style: theme.textTheme.bodyMedium,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        AppSpacing.vGapMd,
                                        Text(
                                          'Deleted on ${_formatTrashedDate(note.trashedAt)}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: AppColors.lightTextHint,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}
