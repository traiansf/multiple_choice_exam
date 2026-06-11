import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grader/sheet_guide_overlay.dart';

void main() {
  testWidgets('overlay paints and shows the default framing hint', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SheetGuideOverlay())),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('corner square'), findsOneWidget);
  });

  testWidgets('overlay shows a custom hint instead', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SheetGuideOverlay(hint: 'Move closer.')),
      ),
    );
    expect(find.text('Move closer.'), findsOneWidget);
    expect(find.textContaining('corner square'), findsNothing);
  });
}
