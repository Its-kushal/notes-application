import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../../settings/presentation/controllers/settings_provider.dart';
import '../../domain/checklist_item.dart';
import '../../domain/note.dart';

class NoteCard extends ConsumerWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback? onTogglePin;
  final VoidCallback onDelete;
  final VoidCallback? onLongPress;
  final VoidCallback? onArchive;
  final bool isSelected;
  final bool isSelectionMode;

  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    this.onTogglePin,
    required this.onDelete,
    this.onLongPress,
    this.onArchive,
    this.isSelected = false,
    this.isSelectionMode = false,
  });

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (now.difference(date).inDays == 0) {
      return DateFormat.jm().format(date);
    } else if (now.year == date.year) {
      return DateFormat('MMM d').format(date);
    } else {
      return DateFormat('MMM d, y').format(date);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final settings = ref.watch(settingsProvider).settings;

    final displayTitle = note.title.trim().isNotEmpty
        ? note.title
        : (note.body.trim().isNotEmpty || (note.isChecklistMode && (note.checklistJson?.isNotEmpty ?? false))
            ? 'Untitled'
            : 'Empty note');

    final colorAccent = (note.colorLabel > 0 &&
            note.colorLabel < AppColors.noteLabelColors.length)
        ? AppColors.noteLabelColors[note.colorLabel]
        : AppColors.transparent;

    final colorName = (note.colorLabel >= 0 &&
            note.colorLabel < AppColors.noteLabelNames.length)
        ? AppColors.noteLabelNames[note.colorLabel]
        : 'None';

    return Semantics(
      label: 'Note: $displayTitle. Color label: $colorName.${note.isPinned ? " Pinned." : ""}',
      selected: isSelected,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs + 2,
        ),
        elevation: isSelected ? 2 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusMd,
          side: BorderSide(
            color: isSelected
                ? AppColors.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : null,
              border: Border(
                left: BorderSide(
                  color: colorAccent,
                  width: colorAccent == AppColors.transparent ? 0 : 5,
                ),
              ),
            ),
            padding: AppSpacing.paddingLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isSelectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.md),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.lightTextHint,
                          size: 22,
                        ),
                      ),
                    Expanded(
                      child: Row(
                        children: [
                          if (note.isChecklistMode)
                            const Padding(
                              padding: EdgeInsets.only(right: AppSpacing.xs),
                              child: Icon(
                                Icons.checklist,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              displayTitle,
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isSelectionMode) ...[
                      if (onTogglePin != null && note.isPinned)
                        IconButton(
                          icon: const Icon(Icons.push_pin, size: 20),
                          color: AppColors.primary,
                          visualDensity: VisualDensity.compact,
                          onPressed: onTogglePin,
                          tooltip: 'Unpin note',
                        )
                      else
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 20),
                          tooltip: 'Note options',
                          onSelected: (value) {
                            if (value == 'pin' && onTogglePin != null) {
                              onTogglePin!();
                            } else if (value == 'archive' && onArchive != null) {
                              onArchive!();
                            } else if (value == 'delete') {
                              onDelete();
                            }
                          },
                          itemBuilder: (context) => [
                            if (onTogglePin != null)
                              const PopupMenuItem(
                                value: 'pin',
                                child: Text('Pin note'),
                              ),
                            if (onArchive != null)
                              PopupMenuItem(
                                value: 'archive',
                                child: Text(note.isArchived ? 'Unarchive' : 'Archive'),
                              ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Move to trash'),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
                if (note.isChecklistMode && note.checklistJson != null) ...[
                  AppSpacing.vGapSm,
                  Builder(builder: (context) {
                    final items = ChecklistItem.parseList(note.checklistJson);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...items.take(3).map((item) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1.0),
                              child: Row(
                                children: [
                                  Icon(
                                    item.isChecked
                                        ? Icons.check_box_outlined
                                        : Icons.check_box_outline_blank,
                                    size: 14,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  AppSpacing.hGapXs,
                                  Expanded(
                                    child: Text(
                                      item.text.isEmpty ? 'List item' : item.text,
                                      style: textTheme.bodySmall?.copyWith(
                                        decoration: item.isChecked
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                        if (items.length > 3)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              '+ ${items.length - 3} more items',
                              style: textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    );
                  }),
                ] else if (note.body.trim().isNotEmpty) ...[
                  AppSpacing.vGapSm,
                  Text(
                    note.body,
                    style: textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                AppSpacing.vGapMd,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (settings.showTimestamps)
                      Text(
                        _formatDate(note.updatedAt),
                        style: textTheme.bodySmall,
                      )
                    else
                      const SizedBox.shrink(),
                    if (note.isChecklistMode && note.checklistJson != null)
                      Builder(builder: (context) {
                        final items = ChecklistItem.parseList(note.checklistJson);
                        final completed = items.where((i) => i.isChecked).length;
                        return Text(
                          '$completed/${items.length} completed',
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      })
                    else if (settings.showWordCount && note.wordCount > 0)
                      Text(
                        '${note.wordCount} words',
                        style: textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
