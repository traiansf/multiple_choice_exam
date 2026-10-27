/// answer-key.json reader. Schema is produced by
/// generator/src/mcexam/keyfile.py and documented in README 'Data formats' —
/// change all three together.
library;

import 'dart:convert';

import 'select.dart' as select show sectionKeys;

class KeyfileFormatException implements Exception {
  KeyfileFormatException(this.message);

  final String message;

  @override
  String toString() => 'KeyfileFormatException: $message';
}

class AnswerKey {
  const AnswerKey({
    required this.version,
    required this.examTitle,
    required this.sourceFingerprint,
    required this.optionsPerQuestion,
    required this.units,
    required this.answerKey,
  });

  /// v1: sections easy/medium/hard of single questions. v2: named sections,
  /// in order, whose units are questions or cases (shared stems).
  static const List<int> supportedVersions = [1, 2];

  final int version;
  final String examTitle;
  final String sourceFingerprint;
  final int optionsPerQuestion;

  /// Per section key, in key order: the question count of each unit.
  final Map<String, List<int>> units;

  /// answerKey[i] = 0-based correct option of the i-th question in key order
  /// (sections in key order, then units, then the questions of each unit).
  final List<int> answerKey;

  List<String> get sectionKeys => units.keys.toList();

  /// Questions per section key, in key order.
  Map<String, int> get sections => {
    for (final entry in units.entries)
      entry.key: entry.value.fold(0, (a, b) => a + b),
  };

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
    if (version is! int || !supportedVersions.contains(version)) {
      throw KeyfileFormatException(
        'unsupported key file version $version (this build reads'
        ' ${supportedVersions.join(', ')})',
      );
    }
    final examTitle = _string(decoded, 'exam_title');
    final fingerprint = _string(decoded, 'source_fingerprint');
    final optionsPerQuestion = _positiveInt(decoded, 'options_per_question');
    final units = version == 1
        ? _unitsV1(decoded['sections'])
        : _unitsV2(decoded['sections']);
    final rawAnswers = decoded['answer_key'];
    if (rawAnswers is! List<dynamic>) {
      throw KeyfileFormatException("missing or malformed 'answer_key'");
    }
    final total = units.values
        .expand((sizes) => sizes)
        .fold(0, (a, b) => a + b);
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
      version: version,
      examTitle: examTitle,
      sourceFingerprint: fingerprint,
      optionsPerQuestion: optionsPerQuestion,
      units: units,
      answerKey: answers,
    );
  }

  /// v1: `{"easy": n, "medium": n, "hard": n}`, single-question units.
  static Map<String, List<int>> _unitsV1(Object? rawSections) {
    if (rawSections is! Map<String, dynamic>) {
      throw KeyfileFormatException("missing or malformed 'sections'");
    }
    final units = <String, List<int>>{};
    for (final key in select.sectionKeys) {
      final value = rawSections[key];
      if (value is! int || value < 0) {
        throw KeyfileFormatException(
          "'sections' must contain non-negative integer '$key'",
        );
      }
      units[key] = List<int>.filled(value, 1);
    }
    return units;
  }

  /// v2: `[{"name": "...", "units": [sizes]}, ...]`, in key order.
  static Map<String, List<int>> _unitsV2(Object? rawSections) {
    if (rawSections is! List<dynamic> || rawSections.isEmpty) {
      throw KeyfileFormatException(
        "'sections' must be a non-empty list of {name, units}",
      );
    }
    final units = <String, List<int>>{};
    for (final section in rawSections) {
      if (section is! Map<String, dynamic>) {
        throw KeyfileFormatException("malformed entry in 'sections'");
      }
      final name = section['name'];
      if (name is! String || name.isEmpty || units.containsKey(name)) {
        throw KeyfileFormatException(
          "every 'sections' entry needs a unique non-empty 'name'",
        );
      }
      final sizes = section['units'];
      if (sizes is! List<dynamic> ||
          sizes.isEmpty ||
          sizes.any((size) => size is! int || size < 1)) {
        throw KeyfileFormatException(
          "section '$name': 'units' must be a non-empty list of positive"
          ' integers',
        );
      }
      units[name] = List<int>.unmodifiable(sizes.cast<int>());
    }
    return units;
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
