import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/crypto/security_window_service.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/shared_widgets.dart';
import '../../../export/export_service.dart';
import '../../../locked_notes/presentation/controllers/vault_providers.dart';
import '../../../settings/presentation/controllers/settings_provider.dart';
import '../../domain/note.dart';
import '../controllers/notes_providers.dart';
import '../widgets/checklist_editor_view.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final Note note;

  const NoteEditorScreen({
    super.key,
    required this.note,
  });

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _titleController = TextEditingController(text: widget.note.title);
    _bodyController = TextEditingController(text: widget.note.body);
    if (widget.note.isLocked) {
      SecurityWindowService.enableSecure();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // Flush autosave immediately when app loses focus or backgrounds
      ref.read(noteEditorProvider(widget.note)).saveImmediately();
      ref.read(notesListProvider).loadNotes();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleController.dispose();
    _bodyController.dispose();
    if (widget.note.isLocked) {
      SecurityWindowService.disableSecure();
    }
    super.dispose();
  }

  void _onBack(BuildContext context) async {
    // Flush autosave before navigating back
    await ref.read(noteEditorProvider(widget.note)).saveImmediately();
    await ref.read(notesListProvider).loadNotes();
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  String _formatLastEdited(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('MMM d, h:mm a').format(date);
  }

  void _showFolderPicker(BuildContext context, NoteEditorNotifier notifier) {
    final folders = ref.read(notesListProvider).folders;
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
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    'Move to folder',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                if (folders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      'No folders created yet',
                      style: Theme.of(ctx).textTheme.bodyMedium,
                    ),
                  )
                else
                  ...folders.map(
                    (folder) => ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(folder.name),
                      selected: notifier.note.folderId == folder.id,
                      onTap: () {
                        notifier.setFolder(folder.id);
                        Navigator.of(ctx).pop();
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showExportModal(BuildContext context, Note note) {
    final settings = ref.read(settingsProvider).settings;
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
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Text(
                    'Export Note',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('Share text file'),
                  subtitle: const Text('Send note via Android share sheet'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    try {
                      await ExportService.shareNote(
                        note,
                        showTimestamps: settings.showTimestamps,
                      );
                    } catch (e) {
                      if (context.mounted) {
                        AppSnackBar.show(context, message: 'Failed to share note: $e');
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.save_alt_outlined),
                  title: const Text('Save to device'),
                  subtitle: const Text('Choose folder via Storage Access Framework'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    try {
                      final path = await ExportService.saveToDevice(
                        note,
                        showTimestamps: settings.showTimestamps,
                      );
                      if (context.mounted && path != null) {
                        AppSnackBar.show(context, message: 'Note saved successfully');
                      }
                    } catch (e) {
                      if (context.mounted) {
                        AppSnackBar.show(context, message: 'Failed to save note: $e');
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final vaultNotifier = ref.watch(vaultProvider);
    if (widget.note.isLocked && !vaultNotifier.isUnlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/unlock');
      });
      return const Scaffold(
        body: Center(child: LoadingState(message: 'Vault locked')),
      );
    }

    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final notifier = ref.watch(noteEditorProvider(widget.note));
    final settings = ref.watch(settingsProvider).settings;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onBack(context);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _onBack(context),
            tooltip: 'Back',
          ),
          actions: [
            // Mode toggle: Checklist <-> Plain text
            IconButton(
              icon: Icon(
                notifier.note.isChecklistMode
                    ? Icons.notes_outlined
                    : Icons.checklist_outlined,
              ),
              tooltip: notifier.note.isChecklistMode
                  ? 'Switch to text mode'
                  : 'Switch to checklist mode',
              onPressed: () {
                notifier.toggleChecklistMode();
                if (!notifier.note.isChecklistMode) {
                  _bodyController.text = notifier.note.body;
                }
              },
            ),
              if (!notifier.note.isLocked) ...[
                IconButton(
                  icon: Icon(
                    notifier.note.isPinned
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                  ),
                  color: notifier.note.isPinned ? AppColors.primary : null,
                  tooltip: notifier.note.isPinned ? 'Unpin' : 'Pin',
                  onPressed: () => notifier.togglePin(),
                ),
                IconButton(
                  icon: const Icon(Icons.folder_outlined),
                  tooltip: 'Move to folder',
                  onPressed: () => _showFolderPicker(context, notifier),
                ),
                IconButton(
                  icon: Icon(
                    notifier.note.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                  tooltip: notifier.note.isArchived ? 'Unarchive' : 'Archive',
                  onPressed: () async {
                    if (notifier.note.isArchived) {
                      await ref.read(notesListProvider).unarchiveNote(widget.note.id);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        AppSnackBar.show(
                          context,
                          message: 'Note unarchived',
                          actionLabel: 'Undo',
                          onAction: () => ref.read(notesListProvider).archiveNote(widget.note.id),
                        );
                      }
                    } else {
                      await ref.read(notesListProvider).archiveNote(widget.note.id);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        AppSnackBar.show(
                          context,
                          message: 'Note archived',
                          actionLabel: 'Undo',
                          onAction: () => ref.read(notesListProvider).unarchiveNote(widget.note.id),
                        );
                      }
                    }
                  },
                ),
                PopupMenuButton<int>(
                  icon: const Icon(Icons.palette_outlined),
                  tooltip: 'Color label',
                  onSelected: (colorIndex) => notifier.setColorLabel(colorIndex),
                  itemBuilder: (context) {
                    return List.generate(AppColors.noteLabelColors.length, (i) {
                      final color = AppColors.noteLabelColors[i];
                      final labelName = AppColors.noteLabelNames[i];
                      return PopupMenuItem<int>(
                        value: i,
                        child: Semantics(
                          label: 'Color label: $labelName',
                          child: Row(
                            children: [
                              Container(
                                width: AppSpacing.xl,
                                height: AppSpacing.xl,
                                decoration: BoxDecoration(
                                  color: i == 0 ? AppColors.transparent : color,
                                  border: Border.all(
                                    color: AppColors.lightBorder,
                                    width: 1.5,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              AppSpacing.hGapMd,
                              Text(labelName),
                            ],
                          ),
                        ),
                      );
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Move to trash',
                  onPressed: () async {
                    if (notifier.isEmptyContent) {
                      await ref.read(notesRepositoryProvider).deleteNotePermanently(widget.note.id);
                      await ref.read(notesListProvider).loadNotes();
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                      return;
                    }
                    await ref.read(notesListProvider).trashNote(widget.note.id);
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      AppSnackBar.show(
                        context,
                        message: 'Note moved to trash',
                        actionLabel: 'Undo',
                        onAction: () => ref.read(notesListProvider).restoreNote(widget.note.id),
                      );
                    }
                  },
                ),
              ],
              // Overflow Menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'More options',
                onSelected: (val) async {
                  if (val == 'export') {
                    if (notifier.note.isLocked) return;
                    _showExportModal(context, notifier.note);
                  } else if (val == 'lock') {
                    await _handleLockNote(context, notifier);
                  } else if (val == 'unlock') {
                    await _handleUnlockNote(context);
                  } else if (val == 'delete_locked') {
                    _handleDeleteLockedNote(context);
                  }
                },
                itemBuilder: (ctx) {
                  if (notifier.note.isLocked) {
                    return [
                      const PopupMenuItem(
                        value: 'unlock',
                        child: Row(
                          children: [
                            Icon(Icons.lock_open, size: 20, color: AppColors.primary),
                            SizedBox(width: AppSpacing.md),
                            Text('Unlock note'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete_locked',
                        child: Row(
                          children: [
                            Icon(Icons.delete_forever, size: 20, color: AppColors.error),
                            SizedBox(width: AppSpacing.md),
                            Text('Delete permanently', style: TextStyle(color: AppColors.error)),
                          ],
                        ),
                      ),
                    ];
                  }
                  return [
                    const PopupMenuItem(
                      value: 'lock',
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline, size: 20, color: AppColors.primary),
                          SizedBox(width: AppSpacing.md),
                          Text('Lock note'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'export',
                      child: Row(
                        children: [
                          Icon(Icons.ios_share_outlined, size: 20),
                          SizedBox(width: AppSpacing.md),
                          Text('Export note'),
                        ],
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
          body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _titleController,
                      style: textTheme.headlineSmall,
                      decoration: const InputDecoration(
                        hintText: 'Title',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) {
                        notifier.updateContent(title: val);
                      },
                    ),
                    AppSpacing.vGapMd,
                    if (notifier.note.isChecklistMode) ...[
                      if (notifier.checklistTotalCount > 0) ...[
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: notifier.checklistTotalCount == 0
                                      ? 0
                                      : notifier.checklistCompletedCount /
                                          notifier.checklistTotalCount,
                                  minHeight: 6,
                                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                                ),
                              ),
                            ),
                            AppSpacing.hGapMd,
                            Text(
                              '${notifier.checklistCompletedCount}/${notifier.checklistTotalCount} completed',
                              style: textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        AppSpacing.vGapSm,
                      ],
                      ChecklistEditorView(
                        items: notifier.checklistItems,
                        onItemChanged: (id, {text, isChecked}) {
                          notifier.updateChecklistItem(id, text: text, isChecked: isChecked);
                        },
                        onItemAdded: (index) {
                          notifier.addChecklistItem(afterIndex: index);
                        },
                        onItemDeleted: (id) {
                          notifier.deleteChecklistItem(id);
                        },
                        onItemReordered: (oldIndex, newIndex) {
                          notifier.reorderChecklistItems(oldIndex, newIndex);
                        },
                      ),
                    ]
                    else
                      TextField(
                        controller: _bodyController,
                        style: textTheme.bodyLarge,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        decoration: const InputDecoration(
                          hintText: 'Start writing...',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (val) {
                          notifier.updateContent(body: val);
                        },
                      ),
                  ],
                ),
              ),
            ),
            // Bottom Status Bar
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 0.5,
                  ),
                ),
                color: theme.colorScheme.surface,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (settings.showTimestamps)
                    Text(
                      'Edited ${_formatLastEdited(notifier.note.updatedAt)}',
                      style: textTheme.bodySmall,
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    children: [
                      // Autosave Indicator ("Saving..." / "Saved" / "Unsaved")
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: notifier.isSaving
                            ? Text(
                                'Saving...',
                                style: textTheme.bodySmall?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : notifier.isDirty
                                ? Text(
                                    'Unsaved',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: AppColors.warning,
                                    ),
                                  )
                                : Text(
                                    'Saved',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                      ),
                      if (settings.showWordCount)
                        Text(
                          '${notifier.wordCount} words',
                          style: textTheme.bodySmall,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLockNote(BuildContext context, NoteEditorNotifier notifier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lock note?'),
        content: const Text(
          'Locking will encrypt this note with your vault key. Its folder, pin, archive status, and color label will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Lock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final vaultNotifier = ref.read(vaultProvider);
    await vaultNotifier.loadVaultState();
    if (!context.mounted) return;
    if (!vaultNotifier.hasVault) {
      final setupResult = await context.push<bool>('/setup');
      if (setupResult != true && !ref.read(vaultProvider).hasVault) {
        return;
      }
    }

    if (!ref.read(vaultProvider).isUnlocked) {
      if (!context.mounted) return;
      final unlocked = await context.push<bool>('/unlock');
      if (unlocked != true && !ref.read(vaultProvider).isUnlocked) {
        return;
      }
    }

    final key = ref.read(vaultProvider).vaultKey;
    if (key == null) return;

    await notifier.saveImmediately();
    await ref.read(notesRepositoryProvider).lockNote(widget.note.id, key);
    await ref.read(notesListProvider).loadNotes();

    if (context.mounted) {
      AppSnackBar.show(context, message: 'Note locked');
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleUnlockNote(BuildContext context) async {
    final key = ref.read(vaultProvider).vaultKey;
    if (key == null) return;

    await ref.read(notesRepositoryProvider).unlockNote(widget.note.id, key);
    await ref.read(notesListProvider).loadNotes();

    if (context.mounted) {
      AppSnackBar.show(context, message: 'Note unlocked and returned to All');
      Navigator.of(context).pop();
    }
  }

  void _handleDeleteLockedNote(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete locked note?'),
        content: const Text(
          'This note will be PERMANENTLY deleted. It will not be moved to trash and cannot be recovered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              await ref.read(notesRepositoryProvider).deleteLockedNotePermanently(widget.note.id);
              if (context.mounted) {
                AppSnackBar.show(context, message: 'Locked note deleted permanently');
                Navigator.of(context).pop();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
  }
}
