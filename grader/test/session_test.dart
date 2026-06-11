import 'package:flutter_test/flutter_test.dart';
import 'package:grader/session.dart';
import 'package:image/image.dart' as img;

import 'sheet_builder.dart';

/// Fixture-anchored seed-0 exam (see omr_grading_integration_test.dart):
/// correct bubble positions on the sheet are [3, 1, 0, 2, 3].
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
const qrRaw = 'v1|1|0|2|2|1|fp012345';
const correctPositions = [3, 1, 0, 2, 3];

img.Image correctSheet() => buildSheetImage(
      rows: 5,
      optionsPerQuestion: 4,
      filledByRow: {
        for (var row = 0; row < 5; row++) row: [correctPositions[row]],
      },
    );

void main() {
  test('happy flow: key -> QR -> sheet -> full score', () {
    final session = GraderSession();
    expect(session.stage, SessionStage.needKey);

    expect(session.loadKey(keyJson), isTrue);
    expect(session.stage, SessionStage.needQr);
    expect(session.answerKey!.examTitle, 'T');

    expect(session.setQr(qrRaw), isTrue);
    expect(session.stage, SessionStage.needSheet);

    expect(session.processSheet(correctSheet()), isTrue);
    expect(session.stage, SessionStage.result);
    expect(session.gradeResult!.score, 5);
    expect(session.gradeResult!.total, 5);
    expect(session.lastError, isNull);
  });

  test('invalid key JSON keeps the old state and reports the error', () {
    final session = GraderSession()..loadKey(keyJson);
    expect(session.loadKey('not json'), isFalse);
    expect(session.lastError, contains('JSON'));
    expect(session.answerKey, isNotNull); // old key kept
    expect(session.stage, SessionStage.needQr);
  });

  test('QR with mismatching fingerprint is rejected at scan time', () {
    final session = GraderSession()..loadKey(keyJson);
    expect(session.setQr('v1|1|0|2|2|1|deadbeef'), isFalse);
    expect(session.lastError, contains('different exam'));
    expect(session.stage, SessionStage.needQr);
  });

  test('QR counts exceeding the key sections are rejected at scan time', () {
    final session = GraderSession()..loadKey(keyJson);
    expect(session.setQr('v1|1|0|9|2|1|fp012345'), isFalse);
    expect(session.lastError, contains('easy'));
    expect(session.stage, SessionStage.needQr);
  });

  test('malformed QR text is rejected with the decoder message', () {
    final session = GraderSession()..loadKey(keyJson);
    expect(session.setQr('hello'), isFalse);
    expect(session.lastError, contains('7 fields'));
  });

  test('double-marked sheet lands in result stage flagged for review', () {
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    final sheet = buildSheetImage(
      rows: 5,
      optionsPerQuestion: 4,
      filledByRow: {
        0: [3],
        1: [1, 2],
        2: [0],
        3: [2],
        4: [3],
      },
    );
    expect(session.processSheet(sheet), isTrue);
    expect(session.stage, SessionStage.result);
    expect(session.gradeResult, isNull);
    expect(session.omrResult!.needsReview, isTrue);
    expect(session.omrResult!.reviewRows, [2]);
  });

  test('missing corner mark keeps needSheet with a corner hint', () {
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    final sheet = buildSheetImage(
      rows: 5,
      optionsPerQuestion: 4,
      omitTopLeftMark: true,
      filledByRow: {
        for (var row = 0; row < 5; row++) row: [correctPositions[row]],
      },
    );
    expect(session.processSheet(sheet), isFalse);
    expect(session.stage, SessionStage.needSheet);
    expect(session.lastError, contains('top-left'));
    expect(session.lastError, contains('bracket'));
  });

  test('dark image keeps needSheet with the exposure hint', () {
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    final dark = img.Image(width: 400, height: 566);
    img.fill(dark, color: img.ColorRgb8(30, 30, 30));
    expect(session.processSheet(dark), isFalse);
    expect(session.stage, SessionStage.needSheet);
    expect(session.lastError, contains('dark'));
  });

  test('loading a new key resets an in-flight session', () {
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    session.processSheet(correctSheet());
    expect(session.stage, SessionStage.result);

    expect(session.loadKey(keyJson), isTrue);
    expect(session.stage, SessionStage.needQr);
    expect(session.gradeResult, isNull);
    expect(session.omrResult, isNull);
  });

  test('nextSheet returns to needQr and keeps the key', () {
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    session.processSheet(correctSheet());
    session.nextSheet();
    expect(session.stage, SessionStage.needQr);
    expect(session.answerKey, isNotNull);
    expect(session.gradeResult, isNull);
  });

  test('retakeSheet clears the result but keeps the QR payload', () {
    final session = GraderSession()
      ..loadKey(keyJson)
      ..setQr(qrRaw);
    session.processSheet(correctSheet());
    session.retakeSheet();
    expect(session.stage, SessionStage.needSheet);
    expect(session.qrPayload, isNotNull);
  });

  test('notifies listeners on every transition', () {
    final session = GraderSession();
    var notifications = 0;
    session.addListener(() => notifications++);
    session.loadKey(keyJson);
    session.setQr(qrRaw);
    session.processSheet(correctSheet());
    session.nextSheet();
    expect(notifications, 4);
  });
}
