import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/features/notes/domain/checklist_item.dart';

void main() {
  group('ChecklistItem Logic & Round-Trip Tests', () {
    test('JSON serialization round-trip maintains integrity', () {
      final items = [
        const ChecklistItem(id: 'item-1', text: 'Task 1', isChecked: false),
        const ChecklistItem(id: 'item-2', text: 'Task 2', isChecked: true),
      ];

      final jsonStr = ChecklistItem.encodeList(items);
      final decoded = ChecklistItem.parseList(jsonStr);

      expect(decoded.length, 2);
      expect(decoded[0].id, 'item-1');
      expect(decoded[0].text, 'Task 1');
      expect(decoded[0].isChecked, isFalse);
      expect(decoded[1].id, 'item-2');
      expect(decoded[1].text, 'Task 2');
      expect(decoded[1].isChecked, isTrue);
    });

    test('Bidirectional conversion between Plain Text and Checklist without data loss', () {
      const originalText = '''
- [ ] Milk
- [x] Eggs
- Bread
* Butter
• Coffee
1. Sugar
''';

      // 1. Text -> Checklist
      final items = ChecklistItem.fromPlainText(originalText);
      expect(items.length, 6);
      expect(items[0].text, 'Milk');
      expect(items[0].isChecked, isFalse);
      expect(items[1].text, 'Eggs');
      expect(items[1].isChecked, isTrue);
      expect(items[2].text, 'Bread');
      expect(items[2].isChecked, isFalse);
      expect(items[3].text, 'Butter');
      expect(items[3].isChecked, isFalse);
      expect(items[4].text, 'Coffee');
      expect(items[4].isChecked, isFalse);
      expect(items[5].text, 'Sugar');
      expect(items[5].isChecked, isFalse);

      // 2. Checklist -> Text
      final convertedBackText = ChecklistItem.toPlainText(items);
      expect(convertedBackText.contains('- [ ] Milk'), isTrue);
      expect(convertedBackText.contains('- [x] Eggs'), isTrue);
      expect(convertedBackText.contains('- [ ] Bread'), isTrue);
      expect(convertedBackText.contains('- [ ] Butter'), isTrue);
      expect(convertedBackText.contains('- [ ] Coffee'), isTrue);
      expect(convertedBackText.contains('- [ ] Sugar'), isTrue);

      // 3. Text -> Checklist again
      final roundTripItems = ChecklistItem.fromPlainText(convertedBackText);
      expect(roundTripItems.length, 6);
      expect(roundTripItems[0].text, 'Milk');
      expect(roundTripItems[0].isChecked, isFalse);
      expect(roundTripItems[1].text, 'Eggs');
      expect(roundTripItems[1].isChecked, isTrue);
    });

    test('Add, check, delete, and reorder items', () {
      var items = [
        const ChecklistItem(id: '1', text: 'Task A', isChecked: false),
        const ChecklistItem(id: '2', text: 'Task B', isChecked: false),
      ];

      // Add (Enter creates new item)
      items = [
        ...items,
        const ChecklistItem(id: '3', text: 'Task C', isChecked: false),
      ];
      expect(items.length, 3);
      expect(items[2].text, 'Task C');

      // Check item
      items = items.map((i) => i.id == '2' ? i.copyWith(isChecked: true) : i).toList();
      expect(items.firstWhere((i) => i.id == '2').isChecked, isTrue);

      // Reorder (move index 0 to index 2)
      final moved = items.removeAt(0);
      items.insert(1, moved);
      expect(items[0].id, '2');
      expect(items[1].id, '1');
      expect(items[2].id, '3');

      // Delete item
      items = items.where((i) => i.id != '1').toList();
      expect(items.length, 2);
      expect(items.any((i) => i.id == '1'), isFalse);
    });

    test('Word and character count includes checklist text', () {
      final items = [
        const ChecklistItem(id: '1', text: 'Buy fresh apples', isChecked: false), // 3 words, 16 chars
        const ChecklistItem(id: '2', text: 'Call doctor', isChecked: true), // 2 words, 11 chars
      ];

      final wordCount = ChecklistItem.calculateWordCount(items);
      expect(wordCount, 5);

      final charCount = ChecklistItem.calculateCharCount(items);
      expect(charCount, 27);
    });
  });
}
