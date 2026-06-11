import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grader/main.dart';
import 'package:grader/records_screen.dart';
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
    // Tall surface so the per-question list is fully built below the
    // comparison images.
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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

  testWidgets('result screen shows blank-row text for unanswered question', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    session.processSheet(
      sheetWith({
        0: [3],
        2: [0],
        3: [2],
        4: [3],
      }), // row 1 left blank
    );
    await tester.pumpWidget(MaterialApp(home: ResultScreen(session: session)));
    expect(find.textContaining('blank — correct:'), findsOneWidget);
    expect(find.text('4 / 5'), findsOneWidget);
  });

  testWidgets('retake button returns the session to needSheet', (tester) async {
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    session.processSheet(
      sheetWith({
        for (var row = 0; row < 5; row++) row: [correctPositions[row]],
      }),
    );
    await tester.pumpWidget(MaterialApp(home: ResultScreen(session: session)));
    await tester.tap(find.text('Retake sheet'));
    expect(session.stage, SessionStage.needSheet);
    expect(session.qrPayload, isNotNull);
  });

  testWidgets(
    'grade-a-sheet recovers a result-stage session after back navigation',
    (tester) async {
      final session = GraderSession()
        ..loadKey(keyJson)
        ..setQr(qrRaw);
      session.processSheet(
        sheetWith({
          for (var row = 0; row < 5; row++) row: [correctPositions[row]],
        }),
      );
      expect(session.stage, SessionStage.result);
      await tester.pumpWidget(GraderApp(session: session));
      await tester.tap(find.text('Grade a sheet'));
      await tester.pumpAndSettle();
      // Returns straight to the result screen instead of doing nothing.
      expect(find.text('5 / 5'), findsOneWidget);
    },
  );

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
    await tester.tap(find.text('Confirm — next sheet'));
    expect(session.stage, SessionStage.needQr);
  });

  testWidgets('graded result shows the side-by-side comparison images', (
    tester,
  ) async {
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    session.processSheet(
      sheetWith({
        0: [3],
        1: [1],
        2: [0],
        3: [2],
        4: [0], // wrong
      }),
    );
    await tester.pumpWidget(MaterialApp(home: ResultScreen(session: session)));
    expect(find.text('Correct answers'), findsOneWidget);
    expect(find.text('Scanned sheet'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.text('Confirm — next sheet'), findsOneWidget);
  });

  testWidgets('review result shows no comparison and keeps Next sheet', (
    tester,
  ) async {
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
    // No side-by-side comparison, but the scan itself is shown so the
    // grader can grade by hand.
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Correct answers'), findsNothing);
    expect(find.text('Next sheet'), findsOneWidget);
    expect(find.text('Confirm — next sheet'), findsNothing);
  });

  testWidgets('review screen accepts a manual grade and records it', (
    tester,
  ) async {
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
    expect(find.text('Submit manual grade'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '3');
    await tester.tap(find.text('Submit manual grade'));
    await tester.pump();
    final record = session.gradeBook.records.single;
    expect(record.score, 3);
    expect(record.manual, isTrue);
    expect(session.stage, SessionStage.needQr);
  });

  testWidgets('review screen rejects an out-of-range manual grade', (
    tester,
  ) async {
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
    await tester.enterText(find.byType(TextField), '9');
    await tester.tap(find.text('Submit manual grade'));
    await tester.pump();
    expect(find.text('Enter a score between 0 and 5.'), findsOneWidget);
    expect(session.gradeBook.isEmpty, isTrue);
    expect(session.stage, SessionStage.result);
  });

  testWidgets('home shows the recorded count and gates the records button', (
    tester,
  ) async {
    final session = GraderSession()..loadKey(keyJson);
    await tester.pumpWidget(GraderApp(session: session));
    expect(find.text('0 sheets recorded'), findsOneWidget);
    final disabled = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Recorded grades'),
    );
    expect(disabled.onPressed, isNull);

    session.setQr(qrRaw);
    session.processSheet(
      sheetWith({
        for (var row = 0; row < 5; row++) row: [correctPositions[row]],
      }),
    );
    session.confirmResult();
    session.nextSheet();
    await tester.pump();
    expect(find.text('1 sheet recorded'), findsOneWidget);
    final enabled = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Recorded grades'),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('records screen lists the recorded grades', (tester) async {
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    session.processSheet(
      sheetWith({
        0: [3],
        1: [1],
        2: [0],
        3: [2],
        4: [0], // wrong: 4/5
      }),
    );
    session.confirmResult();
    await tester.pumpWidget(MaterialApp(home: RecordsScreen(session: session)));
    expect(find.text('Variant 001'), findsOneWidget);
    expect(find.textContaining('4 / 5'), findsOneWidget);
    expect(find.textContaining('80.0%'), findsOneWidget);
    expect(find.text('Export report (CSV)'), findsOneWidget);
    expect(find.text('graded manually'), findsNothing);
  });

  testWidgets('records screen marks manually graded rows', (tester) async {
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
    session.submitManualGrade(3);
    await tester.pumpWidget(MaterialApp(home: RecordsScreen(session: session)));
    expect(find.text('graded manually'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsOneWidget);
  });

  testWidgets('export button shares the CSV without errors', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/share'),
          (call) async => 'dev.fluttercommunity.plus/share/unavailable',
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/share'),
            null,
          ),
    );
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    session.processSheet(
      sheetWith({
        for (var row = 0; row < 5; row++) row: [correctPositions[row]],
      }),
    );
    session.confirmResult();
    await tester.pumpWidget(MaterialApp(home: RecordsScreen(session: session)));
    await tester.tap(find.text('Export report (CSV)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('replace-key dialog warns about discarding recorded grades', (
    tester,
  ) async {
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    session.processSheet(
      sheetWith({
        for (var row = 0; row < 5; row++) row: [correctPositions[row]],
      }),
    );
    session.confirmResult();
    session.nextSheet();
    await tester.pumpWidget(GraderApp(session: session));
    await tester.tap(find.text('Load a different key'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 recorded grade'), findsOneWidget);
    expect(find.textContaining('Export the report first'), findsOneWidget);
    await tester.tap(find.text('Cancel')); // never reaches the file picker
    await tester.pumpAndSettle();
    expect(session.gradeBook.length, 1);
  });

  testWidgets('double-tapping Confirm during the pop animation is harmless', (
    tester,
  ) async {
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    session.processSheet(
      sheetWith({
        for (var row = 0; row < 5; row++) row: [correctPositions[row]],
      }),
    );
    await tester.pumpWidget(MaterialApp(home: ResultScreen(session: session)));
    await tester.tap(find.text('Confirm — next sheet'));
    await tester.tap(find.text('Confirm — next sheet'), warnIfMissed: false);
    expect(tester.takeException(), isNull);
    expect(session.stage, SessionStage.needQr);
  });

  testWidgets('confirm button marks the result confirmed before advancing', (
    tester,
  ) async {
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    session.processSheet(
      sheetWith({
        for (var row = 0; row < 5; row++) row: [correctPositions[row]],
      }),
    );
    var confirmedSeen = false;
    session.addListener(
      () => confirmedSeen = confirmedSeen || session.confirmed,
    );
    await tester.pumpWidget(MaterialApp(home: ResultScreen(session: session)));
    await tester.tap(find.text('Confirm — next sheet'));
    expect(confirmedSeen, isTrue, reason: 'confirmResult ran before nextSheet');
    expect(session.stage, SessionStage.needQr);
  });
}
