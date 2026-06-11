/// Grades a sheet of detected marks against the answer key by replaying the
/// variant from the QR seed. Inputs are exactly: AnswerKey + QrPayload +
/// marks; the original exam text is never needed. Inconsistent inputs throw
/// GradingException — the app flags those sheets for manual review instead
/// of guessing.
library;

import 'keyfile.dart';
import 'qr_scan.dart';
import 'select.dart';

class GradingException implements Exception {
  GradingException(this.message);

  final String message;

  @override
  String toString() => 'GradingException: $message';
}

class QuestionResult {
  const QuestionResult({
    required this.sheetNumber,
    required this.section,
    required this.globalIndex,
    required this.markedPosition,
    required this.correctPosition,
    required this.correct,
  });

  /// 1-based row number as printed on the sheet.
  final int sheetNumber;
  final String section;

  /// Index of the original question in source order (key.answerKey index).
  final int globalIndex;

  /// Bubble position the student marked (null = unanswered).
  final int? markedPosition;

  /// Bubble position that holds the correct option for this variant.
  final int correctPosition;
  final bool correct;
}

class GradeResult {
  const GradeResult({
    required this.score,
    required this.total,
    required this.perQuestion,
  });

  final int score;
  final int total;
  final List<QuestionResult> perQuestion;
}

GradeResult grade({
  required AnswerKey key,
  required QrPayload payload,
  required List<int?> marks,
}) {
  if (payload.sourceFingerprint != key.sourceFingerprint) {
    throw GradingException(
      'source fingerprint mismatch: QR says ${payload.sourceFingerprint},'
      ' key file says ${key.sourceFingerprint} — this sheet was generated'
      ' from a different exam source',
    );
  }
  final VariantPlan plan;
  try {
    plan = buildVariant(
      seed: payload.seed,
      sectionSizes: key.sections,
      counts: payload.counts,
      optionsPerQuestion: key.optionsPerQuestion,
    );
  } on ArgumentError catch (error) {
    throw GradingException(
      'QR counts are inconsistent with the key file: ${error.message}',
    );
  }
  if (marks.length != plan.sheet.length) {
    throw GradingException(
      'expected ${plan.sheet.length} marks but got ${marks.length}',
    );
  }
  final perQuestion = <QuestionResult>[];
  var score = 0;
  for (var row = 0; row < plan.sheet.length; row++) {
    final question = plan.sheet[row];
    final mark = marks[row];
    if (mark != null && (mark < 0 || mark >= key.optionsPerQuestion)) {
      throw GradingException(
        'mark position $mark on row ${row + 1} is outside the option range',
      );
    }
    final correctPosition = question.optionPerm.indexOf(
      key.answerKey[question.globalIndex],
    );
    final correct = mark != null && mark == correctPosition;
    if (correct) score++;
    perQuestion.add(
      QuestionResult(
        sheetNumber: row + 1,
        section: question.section,
        globalIndex: question.globalIndex,
        markedPosition: mark,
        correctPosition: correctPosition,
        correct: correct,
      ),
    );
  }
  return GradeResult(
    score: score,
    total: plan.sheet.length,
    perQuestion: perQuestion,
  );
}
