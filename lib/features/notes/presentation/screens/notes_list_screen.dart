import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/shared_widgets.dart';
import '../../domain/folder.dart';
import '../../domain/note.dart';
import '../../domain/note_sort.dart';
import '../controllers/notes_providers.dart';
import '../widgets/note_card.dart';
import '../widgets/notes_empty_view.dart';
import '../widgets/notes_search_bar.dart';

class NotesListScreen extends ConsumerStatefulWidget {
  const NotesListScreen({super.key});

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _navigateToNewNote() {
    final notifier = ref.read(notesListProvider);
    final newNote = Note.create(
      folderId: notifier.selectedFolderId,
    );
    context.push('/note/${newNote.id}', extra: newNote);
  }

  void _navigateToEditNote(Note note) {
    context.push('/note/${note.id}', extra: note);
  }

  void _showSortDialog(BuildContext context, NotesListNotifier notifier) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sort by',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                AppSpacing.vGapSm,
                ...NoteSortField.values.map((field) {
                  final isSelected = notifier.sortOption.field == field;
                  return ListTile(
                    dense: true,
                    title: Text(field.name[0].toUpperCase() + field.name.substring(1)),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    selected: isSelected,
                    onTap: () {
                      notifier.setSortOption(
                        notifier.sortOption.copyWith(field: field),
                      );
                      Navigator.of(ctx).pop();
                    },
                  );
                }),
                const Divider(),
                Text(
                  'Order',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                AppSpacing.vGapXs,
                ...NoteSortOrder.values.map((order) {
                  final isSelected = notifier.sortOption.order == order;
                  final label = order == NoteSortOrder.ascending ? 'Ascending' : 'Descending';
                  return ListTile(
                    dense: true,
                    title: Text(label),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    selected: isSelected,
                    onTap: () {
                      notifier.setSortOption(
                        notifier.sortOption.copyWith(order: order),
                      );
                      Navigator.of(ctx).pop();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreateFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusMd,
        ),
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await ref.read(notesListProvider).createFolder(name);
                if (ctx.mounted) Navigator.of(ctx).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showFolderOptions(BuildContext context, Folder folder) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename folder'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showRenameFolderDialog(context, folder);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text(
                  'Delete folder',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final confirm = await ConfirmDialog.show(
                    context,
                    title: 'Delete folder?',
                    message:
                        'Notes inside "${folder.name}" will not be deleted; they will stay in All notes.',
                    confirmText: 'Delete',
                    isDestructive: true,
                  );
                  if (confirm == true) {
                    await ref.read(notesListProvider).deleteFolder(folder.id);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRenameFolderDialog(BuildContext context, Folder folder) {
    final controller = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusMd,
        ),
        title: const Text('Rename Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                await ref
                    .read(notesListProvider)
                    .renameFolder(folder.id, newName);
                if (ctx.mounted) Navigator.of(ctx).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showBulkMoveFolderPicker(BuildContext context) {
    final notifier = ref.read(notesListProvider);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Move ${notifier.selectedCount} notes to...',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              if (notifier.folders.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    'No folders created yet',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                )
              else
                ...notifier.folders.map(
                  (f) => ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(f.name),
                    onTap: () async {
                      await notifier.bulkMoveToFolder(f.id);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final notifier = ref.watch(notesListProvider);

    final pinnedNotes = notifier.notes.where((n) => n.isPinned).toList();
    final otherNotes = notifier.notes.where((n) => !n.isPinned).toList();

    // Android back button: exits selection mode first!
    return PopScope(
      canPop: !notifier.isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && notifier.isSelectionMode) {
          notifier.clearSelection();
        }
      },
      child: Scaffold(
        drawer: notifier.isSelectionMode
            ? null
            : Drawer(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    DrawerHeader(
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            size: 36,
                            color: AppColors.white,
                          ),
                          AppSpacing.vGapSm,
                          Text(
                            'Privacy Notes',
                            style: textTheme.titleLarge?.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Encrypted Vault (AES-256)',
                            style: textTheme.bodySmall?.copyWith(
                              color: AppColors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.notes_outlined),
                      title: const Text('All Notes'),
                      selected: notifier.selectedFolderId == null,
                      onTap: () {
                        notifier.setSelectedFolder(null);
                        Navigator.of(context).pop();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.archive_outlined),
                      title: const Text('Archive'),
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push('/archive');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('Trash'),
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push('/trash');
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: const Text('Settings'),
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push('/settings');
                      },
                    ),
                  ],
                ),
              ),
        appBar: notifier.isSelectionMode
            ? AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Exit selection',
                  onPressed: () => notifier.clearSelection(),
                ),
                title: Text('${notifier.selectedCount} selected'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.select_all),
                    tooltip: 'Select all',
                    onPressed: () => notifier.selectAll(),
                  ),
                  IconButton(
                    icon: Icon(
                      notifier.areAllSelectedPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                    ),
                    tooltip: notifier.areAllSelectedPinned ? 'Unpin' : 'Pin',
                    onPressed: () async {
                      await notifier.toggleBulkPin();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_outlined),
                    tooltip: 'Move to folder',
                    onPressed: () => _showBulkMoveFolderPicker(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.archive_outlined),
                    tooltip: 'Archive',
                    onPressed: () async {
                      final archivedIds = await notifier.bulkArchive();
                      if (context.mounted && archivedIds.isNotEmpty) {
                        AppSnackBar.show(
                          context,
                          message: '${archivedIds.length} notes archived',
                          actionLabel: 'Undo',
                          onAction: () =>
                              notifier.unarchiveNotes(archivedIds),
                        );
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Move to trash',
                    onPressed: () async {
                      final trashedIds = await notifier.bulkTrash();
                      if (context.mounted && trashedIds.isNotEmpty) {
                        AppSnackBar.show(
                          context,
                          message: '${trashedIds.length} notes moved to trash',
                          actionLabel: 'Undo',
                          onAction: () =>
                              notifier.restoreNotes(trashedIds),
                        );
                      }
                    },
                  ),
                ],
              )
            : AppBar(
                title: Text('Privacy Notes', style: textTheme.headlineSmall),
                actions: [
                  IconButton(
                    icon: Icon(
                      notifier.isGridView
                          ? Icons.view_agenda_outlined
                          : Icons.grid_view_outlined,
                    ),
                    tooltip: notifier.isGridView
                        ? 'Switch to list'
                        : 'Switch to grid',
                    onPressed: () => notifier.toggleViewMode(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.sort_outlined),
                    tooltip: 'Sort notes',
                    onPressed: () => _showSortDialog(context, notifier),
                  ),
                ],
              ),
        body: Column(
          children: [
            if (!notifier.isSelectionMode) ...[
              NotesSearchBar(
                controller: _searchController,
                onChanged: (query) => notifier.setSearchQuery(query),
                onClear: () {
                  _searchController.clear();
                  notifier.setSearchQuery('');
                },
              ),
              // Folder Filter Chips
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  children: [
                    FilterChip(
                      selected: notifier.selectedFolderId == null,
                      label: const Text('All'),
                      onSelected: (_) => notifier.setSelectedFolder(null),
                    ),
                    ...notifier.folders.map(
                      (folder) => Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sm),
                        child: InputChip(
                          selected: notifier.selectedFolderId == folder.id,
                          label: Text(folder.name),
                          onSelected: (_) =>
                              notifier.setSelectedFolder(folder.id),
                          onDeleted: () => _showFolderOptions(context, folder),
                          deleteIcon: const Icon(Icons.more_vert, size: 16),
                          deleteButtonTooltipMessage: 'Folder options',
                        ),
                      ),
                    ),
                    AppSpacing.hGapSm,
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text('New Folder'),
                      onPressed: () => _showCreateFolderDialog(context),
                    ),
                  ],
                ),
              ),
              AppSpacing.vGapSm,
            ],
            Expanded(
              child: notifier.isLoading
                  ? const LoadingState()
                  : notifier.errorMessage != null
                      ? ErrorState(
                          message: notifier.errorMessage!,
                          onRetry: () => notifier.loadNotes(),
                        )
                      : notifier.notes.isEmpty
                          ? NotesEmptyView(
                              isSearch: notifier.searchQuery.isNotEmpty,
                            )
                          : RefreshIndicator(
                              onRefresh: () => notifier.loadNotes(),
                              child: CustomScrollView(
                                slivers: [
                                  if (pinnedNotes.isNotEmpty) ...[
                                    const SliverToBoxAdapter(
                                      child: SectionHeader(title: 'Pinned'),
                                    ),
                                    if (notifier.isGridView)
                                      SliverPadding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.sm,
                                        ),
                                        sliver: SliverGrid(
                                          gridDelegate:
                                              const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: 2,
                                            childAspectRatio: 0.9,
                                          ),
                                          delegate:
                                              SliverChildBuilderDelegate(
                                            (context, index) {
                                              final note = pinnedNotes[index];
                                              return _buildNoteCard(
                                                note,
                                                notifier,
                                              );
                                            },
                                            childCount: pinnedNotes.length,
                                          ),
                                        ),
                                      )
                                    else
                                      SliverList(
                                        delegate:
                                            SliverChildBuilderDelegate(
                                          (context, index) {
                                            final note = pinnedNotes[index];
                                            return _buildNoteCard(
                                              note,
                                              notifier,
                                            );
                                          },
                                          childCount: pinnedNotes.length,
                                        ),
                                      ),
                                  ],
                                  if (otherNotes.isNotEmpty) ...[
                                    SliverToBoxAdapter(
                                      child: SectionHeader(
                                        title: pinnedNotes.isNotEmpty
                                            ? 'Recent'
                                            : 'Notes',
                                      ),
                                    ),
                                    if (notifier.isGridView)
                                      SliverPadding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.sm,
                                        ),
                                        sliver: SliverGrid(
                                          gridDelegate:
                                              const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: 2,
                                            childAspectRatio: 0.9,
                                          ),
                                          delegate:
                                              SliverChildBuilderDelegate(
                                            (context, index) {
                                              final note = otherNotes[index];
                                              return _buildNoteCard(
                                                note,
                                                notifier,
                                              );
                                            },
                                            childCount: otherNotes.length,
                                          ),
                                        ),
                                      )
                                    else
                                      SliverList(
                                        delegate:
                                            SliverChildBuilderDelegate(
                                          (context, index) {
                                            final note = otherNotes[index];
                                            return _buildNoteCard(
                                              note,
                                              notifier,
                                            );
                                          },
                                          childCount: otherNotes.length,
                                        ),
                                      ),
                                  ],
                                  const SliverToBoxAdapter(
                                    child: SizedBox(height: 80),
                                  ),
                                ],
                              ),
                            ),
            ),
          ],
        ),
        floatingActionButton: notifier.isSelectionMode
            ? null
            : FloatingActionButton(
                onPressed: _navigateToNewNote,
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                tooltip: 'New note',
                child: const Icon(Icons.add, size: 28),
              ),
      ),
    );
  }

  Widget _buildNoteCard(Note note, NotesListNotifier notifier) {
    final isSelected = notifier.selectedNoteIds.contains(note.id);

    return NoteCard(
      note: note,
      isSelected: isSelected,
      isSelectionMode: notifier.isSelectionMode,
      onTap: () {
        if (notifier.isSelectionMode) {
          notifier.toggleNoteSelection(note.id);
        } else {
          _navigateToEditNote(note);
        }
      },
      onLongPress: () {
        notifier.toggleNoteSelection(note.id);
      },
      onTogglePin: () => notifier.togglePin(note),
      onArchive: () async {
        await notifier.archiveNote(note.id);
        if (mounted) {
          AppSnackBar.show(
            context,
            message: 'Note archived',
            actionLabel: 'Undo',
            onAction: () => notifier.unarchiveNote(note.id),
          );
        }
      },
      onDelete: () async {
        await notifier.trashNote(note.id);
        if (mounted) {
          AppSnackBar.show(
            context,
            message: 'Note moved to trash',
            actionLabel: 'Undo',
            onAction: () => notifier.restoreNote(note.id),
          );
        }
      },
    );
  }
}
