/// answer-key.json reader. Schema is produced by
/// generator/src/mcexam/keyfile.py and documented in README 'Data formats' —
/// change all three together.
library;

import 'dart:convert';

import 'select.dart' show sectionKeys;

class KeyfileFormatException implements Exception {
  KeyfileFormatException(this.message);

  final String message;

  @override
  String toString() => 'KeyfileFormatException: $message';
}

class AnswerKey {
  const AnswerKey({
    required this.examTitle,
    required this.sourceFingerprint,
    required this.optionsPerQuestion,
    required this.sections,
    required this.answerKey,
  });

  static const int supportedVersion = 1;

  final String examTitle;
  final String sourceFingerprint;
  final int optionsPerQuestion;
  final Map<String, int> sections;

  /// answerKey[i] = 0-based correct option of the i-th question in source
  /// order (all easy, then medium, then hard).
  final List<int> answerKey;

  int get totalQuestions => answerKey.length;

  static AnswerKey parse(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw KeyfileFormatException('not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw KeyfileFormatException('expected a JSON object at the top level');
    }
    final version = decoded['version'];
    if (version == null) {
      throw KeyfileFormatException("missing required field 'version'");
    }
    if (version != supportedVersion) {
      throw KeyfileFormatException(
        'unsupported key file version $version (this build reads'
        ' $supportedVersion)',
      );
    }
    final examTitle = _string(decoded, 'exam_title');
    final fingerprint = _string(decoded, 'source_fingerprint');
    final optionsPerQuestion = _positiveInt(decoded, 'options_per_question');
    final rawSections = decoded['sections'];
    if (rawSections is! Map<String, dynamic>) {
      throw KeyfileFormatException("missing or malformed 'sections'");
    }
    final sections = <String, int>{};
    for (final key in sectionKeys) {
      final value = rawSections[key];
      if (value is! int || value < 0) {
        throw KeyfileFormatException(
          "'sections' must contain non-negative integer '$key'",
        );
      }
      sections[key] = value;
    }
    final rawAnswers = decoded['answer_key'];
    if (rawAnswers is! List<dynamic>) {
      throw KeyfileFormatException("missing or malformed 'answer_key'");
    }
    final total = sections.values.fold(0, (a, b) => a + b);
    if (rawAnswers.length != total) {
      throw KeyfileFormatException(
        "'answer_key' has ${rawAnswers.length} entries but 'sections' sums"
        ' to $total',
      );
    }
    final answers = <int>[];
    for (final value in rawAnswers) {
      if (value is! int || value < 0 || value >= optionsPerQuestion) {
        throw KeyfileFormatException(
          "'answer_key' entries must be integers in [0, $optionsPerQuestion)",
        );
      }
      answers.add(value);
    }
    return AnswerKey(
      examTitle: examTitle,
      sourceFingerprint: fingerprint,
      optionsPerQuestion: optionsPerQuestion,
      sections: sections,
      answerKey: answers,
    );
  }

  static String _string(Map<String, dynamic> map, String field) {
    final value = map[field];
    if (value is! String || value.isEmpty) {
      throw KeyfileFormatException("missing or malformed '$field'");
    }
    return value;
  }

  static int _positiveInt(Map<String, dynamic> map, String field) {
    final value = map[field];
    if (value is! int || value <= 0) {
      throw KeyfileFormatException("missing or malformed '$field'");
    }
    return value;
  }
}
