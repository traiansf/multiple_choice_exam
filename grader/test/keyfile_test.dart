import 'package:flutter_test/flutter_test.dart';
import 'package:grader/keyfile.dart';

const validJson = '''
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
  test('parses a valid answer key', () {
    final key = AnswerKey.parse(validJson);
    expect(key.examTitle, 'Sample Exam');
    expect(key.sourceFingerprint, 'ab12cd34');
    expect(key.optionsPerQuestion, 4);
    expect(key.sections, {'easy': 3, 'medium': 3, 'hard': 2});
    expect(key.answerKey, [1, 2, 2, 1, 0, 2, 1, 1]);
    expect(key.totalQuestions, 8);
  });

  void expectRejects(String json, Pattern message) {
    expect(
      () => AnswerKey.parse(json),
      throwsA(
        isA<KeyfileFormatException>().having(
          (e) => e.message,
          'message',
          contains(message),
        ),
      ),
    );
  }

  test('rejects unsupported version', () {
    expectRejects(
      validJson.replaceFirst('"version": 1', '"version": 2'),
      'version',
    );
  });

  test('rejects malformed json', () {
    expectRejects('not json', 'not valid JSON');
  });

  test('rejects missing field', () {
    expectRejects(
      validJson.replaceFirst('"exam_title": "Sample Exam",', ''),
      'exam_title',
    );
  });

  test('rejects answer index out of range', () {
    expectRejects(
      validJson.replaceFirst(
        '[1, 2, 2, 1, 0, 2, 1, 1]',
        '[1, 2, 2, 1, 0, 2, 1, 4]',
      ),
      'answer_key',
    );
  });

  test('rejects answer_key length not matching sections', () {
    expectRejects(
      validJson.replaceFirst('[1, 2, 2, 1, 0, 2, 1, 1]', '[1, 2, 2]'),
      'answer_key',
    );
  });

  test('rejects missing section key', () {
    expectRejects(
      validJson.replaceFirst('"hard": 2', '"brutal": 2'),
      'sections',
    );
  });
}
