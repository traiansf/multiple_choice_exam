import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grader/main.dart';
import 'package:grader/result_screen.dart';
import 'package:grader/session.dart';
import 'package:image/image.dart' as img;

import 'sheet_builder.dart';

const keyJson = '''
{
  "version": 1,
  "exam_title": "Widget Exam",
  "source_fingerprint": "fp012345",
  "options_per_question": 4,
  "sections": {"easy": 5, "medium": 4, "hard": 3},
  "answer_key": [1, 2, 2, 1, 0, 2, 1, 1, 0, 1, 2, 0]
}
''';
const qrRaw = 'v1|1|0|2|2|1|fp012345';
const correctPositions = [3, 1, 0, 2, 3];

img.Image sheetWith(Map<int, List<int>> marks) =>
    buildSheetImage(rows: 5, optionsPerQuestion: 4, filledByRow: marks);

void main() {
  testWidgets('home: no key loaded shows prompt, grading disabled', (
    tester,
  ) async {
    await tester.pumpWidget(GraderApp(session: GraderSession()));
    expect(find.textContaining('No answer key loaded'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Grade a sheet'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('home: loaded key shows exam summary, grading enabled', (
    tester,
  ) async {
    final session = GraderSession()..loadKey(keyJson);
    await tester.pumpWidget(GraderApp(session: session));
    expect(find.text('Widget Exam'), findsOneWidget);
    expect(find.textContaining('easy 5'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Grade a sheet'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('result screen shows score and per-question rows', (
    tester,
  ) async {
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    // 4 correct, last row wrong (marked 0 instead of 3).
    session.processSheet(
      sheetWith({
        0: [3],
        1: [1],
        2: [0],
        3: [2],
        4: [0],
      }),
    );
    await tester.pumpWidget(MaterialApp(home: ResultScreen(session: session)));
    expect(find.text('4 / 5'), findsOneWidget);
    expect(find.textContaining('variant 001'), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(4));
    expect(find.textContaining('A — correct: D'), findsOneWidget);
  });

  testWidgets('result screen shows the manual-review notice', (tester) async {
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    session.processSheet(
      sheetWith({
        0: [3],
        1: [1, 2],
        2: [0],
        3: [2],
        4: [3],
      }),
    );
    await tester.pumpWidget(MaterialApp(home: ResultScreen(session: session)));
    expect(find.text('Manual review needed'), findsOneWidget);
    expect(find.textContaining('row 2'), findsOneWidget);
  });

  testWidgets('result screen buttons drive the session', (tester) async {
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    session.processSheet(
      sheetWith({
        for (var row = 0; row < 5; row++) row: [correctPositions[row]],
      }),
    );
    await tester.pumpWidget(MaterialApp(home: ResultScreen(session: session)));
    await tester.tap(find.text('Next sheet'));
    expect(session.stage, SessionStage.needQr);
  });
}
