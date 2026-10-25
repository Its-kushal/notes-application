import 'dart:convert';
import '../../../core/crypto/id_generator.dart';

/// Single item in a checklist note.
class ChecklistItem {
  final String id;
  final String text;
  final bool isChecked;

  const ChecklistItem({
    required this.id,
    required this.text,
    this.isChecked = false,
  });

  ChecklistItem copyWith({
    String? id,
    String? text,
    bool? isChecked,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      text: text ?? this.text,
      isChecked: isChecked ?? this.isChecked,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'text': text,
      'is_checked': isChecked,
    };
  }

  factory ChecklistItem.fromMap(Map<String, dynamic> map) {
    return ChecklistItem(
      id: map['id'] as String? ?? IdGenerator.generateUuidV4(),
      text: map['text'] as String? ?? '',
      isChecked: (map['is_checked'] as bool?) ?? false,
    );
  }

  /// Parses a JSON array string into a list of checklist items.
  static List<ChecklistItem> parseList(String? jsonString) {
    if (jsonString == null || jsonString.trim().isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        return decoded
            .map((e) => ChecklistItem.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Serializes a list of checklist items into a JSON string.
  static String encodeList(List<ChecklistItem> items) {
    final list = items.map((i) => i.toMap()).toList();
    return jsonEncode(list);
  }

  /// Converts plain text lines into a list of checklist items.
  /// Recognizes [x] / [ ] prefixes or bullet points.
  static List<ChecklistItem> fromPlainText(String plainText) {
    final lines = plainText.split('\n');
    final items = <ChecklistItem>[];
    for (final rawLine in lines) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      bool checked = false;
      String content = trimmed;

      if (content.startsWith('- [x] ') || content.startsWith('- [X] ')) {
        checked = true;
        content = content.substring(6).trim();
      } else if (content.startsWith('- [ ] ')) {
        checked = false;
        content = content.substring(6).trim();
      } else if (content.startsWith('[x] ') || content.startsWith('[X] ')) {
        checked = true;
        content = content.substring(4).trim();
      } else if (content.startsWith('[ ] ')) {
        checked = false;
        content = content.substring(4).trim();
      } else if (content.startsWith('- ') || content.startsWith('* ') || content.startsWith('• ')) {
        content = content.substring(2).trim();
      } else {
        // Strip leading numbering like "1. ", "2) " if present
        final match = RegExp(r'^\d+[\.\)]\s+').firstMatch(content);
        if (match != null) {
          content = content.substring(match.end).trim();
        }
      }

      items.add(ChecklistItem(
        id: IdGenerator.generateUuidV4(),
        text: content,
        isChecked: checked,
      ));
    }
    return items;
  }

  /// Converts a list of checklist items into plain text markdown lines.
  static String toPlainText(List<ChecklistItem> items) {
    return items.map((i) {
      final mark = i.isChecked ? '[x]' : '[ ]';
      return '- $mark ${i.text}';
    }).join('\n');
  }

  /// Calculates total word count across all checklist items.
  static int calculateWordCount(List<ChecklistItem> items) {
    final combined = items.map((i) => i.text.trim()).where((t) => t.isNotEmpty).join(' ');
    if (combined.isEmpty) return 0;
    return combined.split(RegExp(r'\s+')).length;
  }

  /// Calculates total character count across all checklist items.
  static int calculateCharCount(List<ChecklistItem> items) {
    return items.fold(0, (sum, item) => sum + item.text.length);
  }
}
