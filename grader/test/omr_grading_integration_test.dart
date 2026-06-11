import 'package:flutter_test/flutter_test.dart';
import 'package:grader/grading.dart';
import 'package:grader/keyfile.dart';
import 'package:grader/omr.dart';
import 'package:grader/qr_scan.dart';
import 'package:grader/select.dart';

import 'sheet_builder.dart';

/// The production path end-to-end: synthesize a sheet image, run OMR, feed
/// the detected marks into grade(). Uses the fixture-anchored seed-0 case
/// from grading_test.dart (correct positions [3,1,0,2,3], hand-derived from
/// shared/test-vectors.json).
const keyJson = '''
{
  "version": 1,
  "exam_title": "T",
  "source_fingerprint": "fp012345",
  "options_per_question": 4,
  "sections": {"easy": 5, "medium": 4, "hard": 3},
  "answer_key": [1, 2, 2, 1, 0, 2, 1, 1, 0, 1, 2, 0]
}
''';

void main() {
  final key = AnswerKey.parse(keyJson);
  final payload = QrPayload.decode('v1|1|0|2|2|1|fp012345');

  test('scan a clean sheet image and grade it: full score', () {
    final plan = buildVariant(
      seed: payload.seed,
      sectionSizes: key.sections,
      counts: payload.counts,
      optionsPerQuestion: key.optionsPerQuestion,
    );
    final correctPositions = [
      for (final q in plan.sheet)
        q.optionPerm.indexOf(key.answerKey[q.globalIndex]),
    ];
    expect(correctPositions, [3, 1, 0, 2, 3]); // hand-derived anchor

    final sheet = buildSheetImage(
      rows: plan.sheet.length,
      optionsPerQuestion: key.optionsPerQuestion,
      filledByRow: {
        for (var row = 0; row < correctPositions.length; row++)
          row: [correctPositions[row]],
      },
    );
    final omr = detectMarks(
      sheet,
      rows: plan.sheet.length,
      optionsPerQuestion: key.optionsPerQuestion,
    );
    expect(omr.needsReview, isFalse);

    final result = grade(
      key: key,
      payload: payload,
      marks: omr.marksForGrading,
    );
    expect(result.score, 5);
    expect(result.total, 5);
  });

  test('a sheet with a double-marked row cannot be graded directly', () {
    final sheet = buildSheetImage(
      rows: 5,
      optionsPerQuestion: 4,
      filledByRow: {
        0: [3],
        1: [1, 2], // double mark
        2: [0],
        3: [2],
        4: [3],
      },
    );
    final omr = detectMarks(sheet, rows: 5, optionsPerQuestion: 4);
    expect(omr.needsReview, isTrue);
    expect(omr.reviewRows, [2]);
    expect(() => omr.marksForGrading, throwsA(isA<OmrException>()));

    // A blank row, by contrast, grades normally as unanswered.
    final blankRowSheet = buildSheetImage(
      rows: 5,
      optionsPerQuestion: 4,
      filledByRow: {
        0: [3],
        2: [0],
        3: [2],
        4: [3],
      },
    );
    final blankOmr = detectMarks(blankRowSheet, rows: 5, optionsPerQuestion: 4);
    expect(blankOmr.needsReview, isFalse);
    final result = grade(
      key: key,
      payload: payload,
      marks: blankOmr.marksForGrading,
    );
    expect(result.score, 4);
    expect(result.perQuestion[1].markedPosition, isNull);
    expect(result.perQuestion[1].correct, isFalse);
  });
}
