import 'package:flutter_test/flutter_test.dart';
import 'package:grader/grading.dart';
import 'package:grader/keyfile.dart';
import 'package:grader/qr_scan.dart';
import 'package:grader/select.dart';

const keyJson = '''
{
  "version": 1,
  "exam_title": "Sample Exam",
  "source_fingerprint": "ab12cd34",
  "options_per_question": 4,
  "sections": {"easy": 3, "medium": 3, "hard": 2},
  "answer_key": [1, 2, 2, 1, 0, 2, 1, 1]
}
''';

void main() {
  final key = AnswerKey.parse(keyJson);
  final payload = QrPayload.decode('v1|1|424242|2|2|1|ab12cd34');

  VariantPlan planFor(QrPayload p) => buildVariant(
        seed: p.seed,
        sectionSizes: key.sections,
        counts: p.counts,
        optionsPerQuestion: key.optionsPerQuestion,
      );

  List<int> correctMarks(VariantPlan plan) => [
        for (final q in plan.sheet)
          q.optionPerm.indexOf(key.answerKey[q.globalIndex]),
      ];

  test('round trip: all-correct marks score full', () {
    final result = grade(
      key: key,
      payload: payload,
      marks: correctMarks(planFor(payload)),
    );
    expect(result.score, 5);
    expect(result.total, 5);
    expect(result.perQuestion.every((q) => q.correct), isTrue);
  });

  test('round trip: alternating wrong marks score the expected pattern', () {
    final plan = planFor(payload);
    final correct = correctMarks(plan);
    final marks = <int?>[
      for (var row = 0; row < plan.sheet.length; row++)
        row.isEven ? correct[row] : (correct[row] + 1) % 4,
    ];
    final result = grade(key: key, payload: payload, marks: marks);
    expect(
      [for (final q in result.perQuestion) q.correct],
      [true, false, true, false, true],
    );
    expect(result.score, 3);
  });

  test('unanswered (null) marks count as incorrect but are reported', () {
    final marks = List<int?>.filled(5, null);
    final result = grade(key: key, payload: payload, marks: marks);
    expect(result.score, 0);
    expect(result.perQuestion.every((q) => q.markedPosition == null), isTrue);
  });

  test('fingerprint mismatch is flagged, not graded', () {
    final other = QrPayload.decode('v1|1|424242|2|2|1|deadbeef');
    expect(
      () => grade(key: key, payload: other, marks: List<int?>.filled(5, 0)),
      throwsA(
        isA<GradingException>()
            .having((e) => e.message, 'message', contains('fingerprint')),
      ),
    );
  });

  test('marks length mismatch is flagged', () {
    expect(
      () => grade(key: key, payload: payload, marks: [0, 1]),
      throwsA(
        isA<GradingException>()
            .having((e) => e.message, 'message', contains('marks')),
      ),
    );
  });

  test('payload counts exceeding key sections are flagged', () {
    final tooMany = QrPayload.decode('v1|1|424242|9|2|1|ab12cd34');
    expect(
      () => grade(key: key, payload: tooMany, marks: List<int?>.filled(12, 0)),
      throwsA(isA<GradingException>()),
    );
  });

  test('mark position outside the option range is flagged', () {
    expect(
      () => grade(key: key, payload: payload, marks: [0, 1, 2, 3, 4]),
      throwsA(
        isA<GradingException>()
            .having((e) => e.message, 'message', contains('position')),
      ),
    );
  });
}
