import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Single item in a selection dialog.
class SelectionItem<T> {
  final String title;
  final T value;
  final String? subtitle;

  const SelectionItem({
    required this.title,
    required this.value,
    this.subtitle,
  });
}

/// A section of options within a selection dialog.
class SelectionSection<T> {
  final String? title;
  final T selectedValue;
  final List<SelectionItem<T>> items;
  final void Function(dynamic) _onSelectedInternal;

  SelectionSection({
    this.title,
    required this.selectedValue,
    required this.items,
    required ValueChanged<T> onSelected,
  }) : _onSelectedInternal = ((dynamic val) => onSelected(val as T));

  void select(dynamic val) => _onSelectedInternal(val);
}

/// Shared selection dialog widget replacing duplicated dialogs across settings.
class SelectionDialog extends StatelessWidget {
  final String title;
  final List<SelectionSection<dynamic>> sections;
  final bool popOnSelect;

  const SelectionDialog({
    super.key,
    required this.title,
    required this.sections,
    this.popOnSelect = true,
  });

  /// Factory helper for single-section dialogs.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required T selectedValue,
    required List<SelectionItem<T>> items,
    required ValueChanged<T> onSelected,
  }) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => SelectionDialog(
        title: title,
        popOnSelect: true,
        sections: [
          SelectionSection<T>(
            selectedValue: selectedValue,
            items: items,
            onSelected: (val) {
              onSelected(val);
            },
          ),
        ],
      ),
    );
  }

  /// Factory helper for multi-section selection dialogs (e.g., sort field & direction).
  static Future<void> showSectioned({
    required BuildContext context,
    required String title,
    required List<SelectionSection<dynamic>> sections,
    bool popOnSelect = true,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => SelectionDialog(
        title: title,
        sections: sections,
        popOnSelect: popOnSelect,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < sections.length; i++) ...[
              if (i > 0) const Divider(),
              if (sections[i].title != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, bottom: 4.0, left: 8.0),
                  child: Text(
                    sections[i].title!,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ...sections[i].items.map((item) {
                final isSelected = item.value == sections[i].selectedValue;
                return ListTile(
                  dense: true,
                  title: Text(item.title),
                  subtitle: item.subtitle != null ? Text(item.subtitle!) : null,
                  trailing: isSelected
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  selected: isSelected,
                  onTap: () {
                    sections[i].select(item.value);
                    if (popOnSelect) {
                      Navigator.of(context).pop();
                    }
                  },
                );
              }),
            ],
          ],
        ),
      ),
      actions: !popOnSelect
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ]
          : null,
    );
  }
}
