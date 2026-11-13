import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/spacing.dart';
import '../../domain/checklist_item.dart';

/// Interactive checklist editor component with check, edit, delete, and reorder.
class ChecklistEditorView extends StatefulWidget {
  final List<ChecklistItem> items;
  final void Function(String id, {String? text, bool? isChecked}) onItemChanged;
  final void Function(int afterIndex) onItemAdded;
  final void Function(String id) onItemDeleted;
  final void Function(int oldIndex, int newIndex) onItemReordered;

  const ChecklistEditorView({
    super.key,
    required this.items,
    required this.onItemChanged,
    required this.onItemAdded,
    required this.onItemDeleted,
    required this.onItemReordered,
  });

  @override
  State<ChecklistEditorView> createState() => _ChecklistEditorViewState();
}

class _ChecklistEditorViewState extends State<ChecklistEditorView> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(ChecklistEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  void _syncControllers() {
    final activeIds = widget.items.map((i) => i.id).toSet();

    // Clean up removed items
    _controllers.removeWhere((id, controller) {
      if (!activeIds.contains(id)) {
        controller.dispose();
        return true;
      }
      return false;
    });

    _focusNodes.removeWhere((id, node) {
      if (!activeIds.contains(id)) {
        node.dispose();
        return true;
      }
      return false;
    });

    // Create or update controllers
    for (final item in widget.items) {
      if (!_controllers.containsKey(item.id)) {
        _controllers[item.id] = TextEditingController(text: item.text);
        _focusNodes[item.id] = FocusNode();
      } else {
        if (_controllers[item.id]!.text != item.text) {
          final oldPos = _controllers[item.id]!.selection;
          _controllers[item.id]!.text = item.text;
          _controllers[item.id]!.selection = oldPos;
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.items.length,
          // ignore: deprecated_member_use
          onReorder: widget.onItemReordered,
          buildDefaultDragHandles: false,
          itemBuilder: (context, index) {
            final item = widget.items[index];
            final controller = _controllers[item.id] ?? TextEditingController(text: item.text);
            final focusNode = _focusNodes[item.id] ?? FocusNode();

            return Container(
              key: ValueKey(item.id),
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Drag Handle for Reorder
                  ReorderableDragStartListener(
                    index: index,
                    child: Semantics(
                      label: 'Reorder item ${index + 1}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Icon(
                          Icons.drag_indicator,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                  // Checkbox
                  Semantics(
                    label: item.isChecked ? 'Mark item as uncompleted' : 'Mark item as completed',
                    child: Checkbox(
                      value: item.isChecked,
                      activeColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onChanged: (val) {
                        widget.onItemChanged(item.id, isChecked: val ?? false);
                      },
                    ),
                  ),
                  // Item Text Input
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: textTheme.bodyLarge?.copyWith(
                        decoration: item.isChecked ? TextDecoration.lineThrough : null,
                        color: item.isChecked
                            ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7)
                            : theme.colorScheme.onSurface,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'List item',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      textInputAction: TextInputAction.next,
                      onChanged: (val) {
                        widget.onItemChanged(item.id, text: val);
                      },
                      onSubmitted: (_) {
                        widget.onItemAdded(index);
                      },
                    ),
                  ),
                  // Delete Button
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    tooltip: 'Delete item',
                    onPressed: () {
                      widget.onItemDeleted(item.id);
                    },
                  ),
                ],
              ),
            );
          },
        ),
        // Add new item button
        InkWell(
          onTap: () {
            widget.onItemAdded(widget.items.isEmpty ? 0 : widget.items.length - 1);
          },
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm,
              horizontal: AppSpacing.xs,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.add,
                  size: 20,
                  color: AppColors.primary,
                ),
                AppSpacing.hGapSm,
                Text(
                  'List item',
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
