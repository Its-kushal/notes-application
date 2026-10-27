import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/crypto/security_window_service.dart';
import '../../../../core/theme/spacing.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/loading_state.dart';
import '../../../notes/domain/note.dart';
import '../../../notes/presentation/widgets/notes_empty_view.dart';
import '../controllers/vault_providers.dart';

class LockedNotesListScreen extends ConsumerStatefulWidget {
  const LockedNotesListScreen({super.key});

  @override
  ConsumerState<LockedNotesListScreen> createState() => _LockedNotesListScreenState();
}

class _LockedNotesListScreenState extends ConsumerState<LockedNotesListScreen> {
  @override
  void initState() {
    super.initState();
    SecurityWindowService.enableSecure();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(lockedNotesProvider.notifier).loadLockedNotes();
    });
  }

  @override
  void dispose() {
    SecurityWindowService.disableSecure();
    super.dispose();
  }

  void _lockAndExit() {
    ref.read(vaultProvider).lockVault();
    context.go('/');
  }

  void _showDeleteConfirmation(BuildContext context, Note note) {
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
              await ref.read(lockedNotesProvider.notifier).deleteLockedNotePermanently(note.id);
              if (context.mounted) {
                AppSnackBar.show(context, message: 'Locked note deleted permanently');
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

  @override
  Widget build(BuildContext context) {
    final vaultNotifier = ref.watch(vaultProvider);
    if (!vaultNotifier.isUnlocked) {
      // Vault was locked (e.g. backgrounded or timeout) -> return to home or prompt
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/unlock');
      });
      return const Scaffold(
        body: Center(child: LoadingState(message: 'Vault locked')),
      );
    }

    final lockedState = ref.watch(lockedNotesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Locked notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Lock vault now',
            onPressed: _lockAndExit,
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (lockedState.isLoading) {
            return const LoadingState(message: 'Decrypting notes...');
          }

          if (lockedState.notes.isEmpty) {
            return const NotesEmptyView(
              customTitle: 'No locked notes',
              customSubtitle: 'Lock sensitive notes from the editor overflow menu.',
              icon: Icons.lock_outline,
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(Spacing.md),
            itemCount: lockedState.notes.length,
            separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
            itemBuilder: (context, index) {
              final note = lockedState.notes[index];
              return _buildLockedNoteTile(context, note);
            },
          );
        },
      ),
    );
  }

  Widget _buildLockedNoteTile(BuildContext context, Note note) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 1,
      color: isDark ? AppColors.surfaceDark : AppColors.cardLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Spacing.sm),
        side: BorderSide(
          color: isDark ? AppColors.charcoal : AppColors.greyLight,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Spacing.sm),
        onTap: () async {
          await context.push('/note/${note.id}', extra: note);
          if (mounted) {
            ref.read(lockedNotesProvider.notifier).loadLockedNotes();
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock, size: 16, color: AppColors.primary),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Text(
                      note.title.isNotEmpty ? note.title : 'Untitled Note',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    tooltip: 'Note actions',
                    onSelected: (val) async {
                      if (val == 'unlock') {
                        await ref.read(lockedNotesProvider.notifier).unlockNote(note.id);
                        if (context.mounted) {
                          AppSnackBar.show(context, message: 'Note unlocked and returned to All');
                        }
                      } else if (val == 'delete') {
                        _showDeleteConfirmation(context, note);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'unlock',
                        child: Row(
                          children: [
                            Icon(Icons.lock_open, size: 20, color: AppColors.primary),
                            SizedBox(width: Spacing.sm),
                            Text('Unlock note'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_forever, size: 20, color: AppColors.error),
                            SizedBox(width: Spacing.sm),
                            Text('Delete permanently', style: TextStyle(color: AppColors.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (note.body.isNotEmpty) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  note.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.greyLight : AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
