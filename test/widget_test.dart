import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_notes/main.dart';

void main() {
  testWidgets('PrivacyNotesApp renders placeholder smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PrivacyNotesApp());

    expect(find.text('Privacy Notes'), findsOneWidget);
    expect(find.text('Encrypted at rest • Zero cloud • 100% Local'), findsOneWidget);
  });
}
