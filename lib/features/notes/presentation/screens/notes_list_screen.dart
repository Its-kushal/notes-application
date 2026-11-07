import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/shared_widgets.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/folder.dart';
import '../../domain/note.dart';
import '../../domain/note_sort.dart';
import '../controllers/notes_providers.dart';
import '../widgets/note_card.dart';
import '../widgets/notes_empty_view.dart';
import '../widgets/notes_search_bar.dart';
import '../../../locked_notes/presentation/controllers/vault_providers.dart';

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
    final l10n = contextL10n(context);
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
                  l10n.sortBy,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                AppSpacing.vGapSm,
                ...NoteSortField.values.map((field) {
                  final isSelected = notifier.sortOption.field == field;
                  final label = switch (field) {
                    NoteSortField.title => l10n.sortFieldTitle,
                    NoteSortField.modified => l10n.sortFieldUpdated,
                    NoteSortField.created => l10n.sortFieldCreated,
                  };
                  return ListTile(
                    dense: true,
                    title: Text(label),
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
                  l10n.order,
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
                AppSpacing.vGapXs,
                ...NoteSortOrder.values.map((order) {
                  final isSelected = notifier.sortOption.order == order;
                  final label = order == NoteSortOrder.ascending ? l10n.ascending : l10n.descending;
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
    final l10n = contextL10n(context);
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusMd,
        ),
        title: Text(l10n.newFolder),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.folderName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await ref.read(notesListProvider).createFolder(name);
                if (ctx.mounted) Navigator.of(ctx).pop();
              }
            },
            child: Text(l10n.create),
          ),
        ],
      ),
    );
  }

  void _showFolderOptions(BuildContext context, Folder folder) {
    final l10n = contextL10n(context);
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
                title: Text(l10n.renameFolder),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showRenameFolderDialog(context, folder);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: Text(
                  l10n.deleteFolder,
                  style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(color: AppColors.error),
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final confirm = await ConfirmDialog.show(
                    context,
                    title: l10n.deleteFolderConfirmTitle,
                    message: l10n.deleteFolderConfirmMessage(folder.name),
                    confirmText: l10n.delete,
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
    final l10n = contextL10n(context);
    final controller = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusMd,
        ),
        title: Text(l10n.renameFolder),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.folderName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
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
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _showBulkMoveFolderPicker(BuildContext context) {
    final l10n = contextL10n(context);
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
                  l10n.moveNotesToFolderTitle(notifier.selectedCount),
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              if (notifier.folders.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    l10n.noFoldersYet,
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
    final l10n = contextL10n(context);
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
                            l10n.appTitle,
                            style: textTheme.titleLarge?.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            l10n.encryptedVaultSubtitle,
                            style: textTheme.bodySmall?.copyWith(
                              color: AppColors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.notes_outlined),
                      title: Text(l10n.allNotes),
                      selected: notifier.selectedFolderId == null,
                      onTap: () {
                        notifier.setSelectedFolder(null);
                        Navigator.of(context).pop();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.lock_outline),
                      title: Text(l10n.lockedNotes),
                      onTap: () async {
                        Navigator.of(context).pop();
                        final vaultNotifier = ref.read(vaultProvider);
                        await vaultNotifier.loadVaultState();
                        if (!context.mounted) return;
                        final vault = vaultNotifier.state;
                        if (!vault.hasVault) {
                          final ok = await context.push<bool>('/setup');
                          if (ok == true && context.mounted) {
                            context.push('/locked');
                          }
                        } else if (!vault.isUnlocked) {
                          final ok = await context.push<bool>('/unlock');
                          if (ok == true && context.mounted) {
                            context.push('/locked');
                          }
                        } else {
                          context.push('/locked');
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.archive_outlined),
                      title: Text(l10n.archive),
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push('/archive');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: Text(l10n.trash),
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push('/trash');
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.settings_outlined),
                      title: Text(l10n.settings),
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
                  tooltip: l10n.exitSelection,
                  onPressed: () => notifier.clearSelection(),
                ),
                title: Text(l10n.selectedNotesCount(notifier.selectedCount)),
                actions: [
                  IconButton(
                    icon: Icon(
                      notifier.areAllSelectedPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                    ),
                    tooltip: notifier.areAllSelectedPinned ? l10n.unpin : l10n.pin,
                    onPressed: () async {
                      await notifier.toggleBulkPin();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_outlined),
                    tooltip: l10n.moveToFolder,
                    onPressed: () => _showBulkMoveFolderPicker(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.archive_outlined),
                    tooltip: l10n.archive,
                    onPressed: () async {
                      final archivedIds = await notifier.bulkArchive();
                      if (context.mounted && archivedIds.isNotEmpty) {
                        AppSnackBar.show(
                          context,
                          message: l10n.notesArchived(archivedIds.length),
                          actionLabel: l10n.undo,
                          onAction: () =>
                              notifier.unarchiveNotes(archivedIds),
                        );
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l10n.moveToTrash,
                    onPressed: () async {
                      final trashedIds = await notifier.bulkTrash();
                      if (context.mounted && trashedIds.isNotEmpty) {
                        AppSnackBar.show(
                          context,
                          message: l10n.notesMovedToTrash(trashedIds.length),
                          actionLabel: l10n.undo,
                          onAction: () =>
                              notifier.restoreNotes(trashedIds),
                        );
                      }
                    },
                  ),
                ],
              )
            : AppBar(
                title: Text(l10n.appTitle, style: textTheme.headlineSmall),
                actions: [
                  IconButton(
                    icon: Icon(
                      notifier.isGridView
                          ? Icons.view_agenda_outlined
                          : Icons.grid_view_outlined,
                    ),
                    tooltip: notifier.isGridView
                        ? l10n.switchToList
                        : l10n.switchToGrid,
                    onPressed: () => notifier.toggleViewMode(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.sort_outlined),
                    tooltip: l10n.sortNotes,
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
                      label: Text(l10n.allNotes),
                      onSelected: (_) => notifier.setSelectedFolder(null),
                    ),
                    ...notifier.folders.map(
                      (folder) => Padding(
                        padding: const EdgeInsetsDirectional.only(start: AppSpacing.sm),
                        child: InputChip(
                          selected: notifier.selectedFolderId == folder.id,
                          label: Text(folder.name),
                          onSelected: (_) =>
                              notifier.setSelectedFolder(folder.id),
                          onDeleted: () => _showFolderOptions(context, folder),
                          deleteIcon: const Icon(Icons.more_vert, size: 16),
                          deleteButtonTooltipMessage: l10n.folderOptions,
                        ),
                      ),
                    ),
                    AppSpacing.hGapSm,
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(l10n.newFolder),
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
                                    SliverToBoxAdapter(
                                      child: SectionHeader(
                                        title: l10n.pinnedSectionHeader,
                                        trailing: (notifier.isSelectionMode && otherNotes.isEmpty)
                                            ? _buildSelectAllAction(context, notifier, l10n)
                                            : null,
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
                                            ? l10n.recentSectionHeader
                                            : l10n.notesSectionHeader,
                                        trailing: notifier.isSelectionMode
                                            ? _buildSelectAllAction(context, notifier, l10n)
                                            : null,
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
                tooltip: l10n.newNote,
                child: const Icon(Icons.add, size: 28),
              ),
      ),
    );
  }

  Widget _buildSelectAllAction(
    BuildContext context,
    NotesListNotifier notifier,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final allSelected =
        notifier.selectedCount == notifier.notes.length && notifier.notes.isNotEmpty;

    return TextButton(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        minimumSize: const Size(48, 48),
        foregroundColor: AppColors.primary,
      ),
      onPressed: () {
        if (allSelected) {
          notifier.clearSelection();
        } else {
          notifier.selectAll();
        }
      },
      child: Text(
        allSelected ? l10n.deselectAll : l10n.selectAll,
        style: theme.textTheme.labelLarge?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildNoteCard(Note note, NotesListNotifier notifier) {
    final isSelected = notifier.selectedNoteIds.contains(note.id);
    final l10n = contextL10n(context);

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
            message: l10n.noteArchived,
            actionLabel: l10n.undo,
            onAction: () => notifier.unarchiveNote(note.id),
          );
        }
      },
      onDelete: () async {
        await notifier.trashNote(note.id);
        if (mounted) {
          AppSnackBar.show(
            context,
            message: l10n.noteMovedToTrash,
            actionLabel: l10n.undo,
            onAction: () => notifier.restoreNote(note.id),
          );
        }
      },
    );
  }
}
