import 'package:flutter_test/flutter_test.dart';
import 'package:grader/main.dart';

void main() {
  testWidgets('home screen renders', (tester) async {
    await tester.pumpWidget(const GraderApp());
    expect(find.text('MC Exam Grader'), findsOneWidget);
  });
}
