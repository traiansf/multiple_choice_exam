// Format v2: named sections whose units are questions or cases (shared
// stems). Python counterpart: generator/tests/test_cases.py.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grader/grading.dart';
import 'package:grader/keyfile.dart';
import 'package:grader/qr_scan.dart';
import 'package:grader/select.dart';

// The key mcexam writes for generator/tests/test_cases.py's CASE_MD.
const keyJson = '''
{
  "version": 2,
  "exam_title": "Case Exam",
  "source_fingerprint": "deadbeef",
  "options_per_question": 4,
  "sections": [
    {"name": "Modeling", "units": [2, 1]},
    {"name": "Contracts", "units": [1, 1]}
  ],
  "answer_key": [0, 1, 1, 0, 1]
}
''';

void main() {
  test('unit plans match shared/test-vectors.json', () {
    final vectors =
        jsonDecode(File('../shared/test-vectors.json').readAsStringSync())
            as Map<String, dynamic>;
    final cases = vectors['unit_plans'] as List<dynamic>;
    expect(cases, isNotEmpty);
    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      final sections = (c['sections'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final names = [for (final s in sections) s['name'] as String];
      final counts = (c['counts'] as List<dynamic>).cast<int>();
      final plan = buildPlan(
        seed: BigInt.parse(c['seed'] as String),
        units: {
          for (final s in sections)
            s['name'] as String: (s['units'] as List<dynamic>).cast<int>(),
        },
        counts: {for (var i = 0; i < names.length; i++) names[i]: counts[i]},
        optionsPerQuestion: c['options_per_question'] as int,
      );
      final expected = c['expected'] as Map<String, dynamic>;
      final reason = 'seed ${c['seed']}';
      expect(
        [for (final name in names) plan.selections[name]],
        (expected['selections'] as List<dynamic>)
            .map((s) => (s as List<dynamic>).cast<int>())
            .toList(),
        reason: reason,
      );
      expect(
        [for (final q in plan.sheet) q.globalIndex],
        (expected['global_indices'] as List<dynamic>).cast<int>(),
        reason: reason,
      );
      expect(
        [for (final q in plan.sheet) q.optionPerm],
        (expected['option_perms'] as List<dynamic>)
            .map((p) => (p as List<dynamic>).cast<int>())
            .toList(),
        reason: reason,
      );
    }
  });

  test('parses a v2 key', () {
    final key = AnswerKey.parse(keyJson);
    expect(key.version, 2);
    expect(key.sectionKeys, ['Modeling', 'Contracts']);
    expect(key.units, {
      'Modeling': [2, 1],
      'Contracts': [1, 1],
    });
    expect(key.sections, {'Modeling': 3, 'Contracts': 2});
    expect(key.totalQuestions, 5);
  });

  test('v1 keys become single-question units', () {
    final key = AnswerKey.parse('''
{"version": 1, "exam_title": "T", "source_fingerprint": "ab12cd34",
 "options_per_question": 4, "sections": {"easy": 2, "medium": 1, "hard": 0},
 "answer_key": [0, 1, 2]}
''');
    expect(key.units, {
      'easy': [1, 1],
      'medium': [1],
      'hard': <int>[],
    });
  });

  test('rejects malformed v2 sections', () {
    for (final sections in [
      '{"Modeling": 3}',
      '[]',
      '[{"name": "", "units": [1]}]',
      '[{"name": "A", "units": [0]}]',
      '[{"name": "A", "units": [1]}, {"name": "A", "units": [1]}]',
    ]) {
      expect(
        () => AnswerKey.parse(
          '{"version": 2, "exam_title": "T", "source_fingerprint": "ab",'
          ' "options_per_question": 4, "sections": $sections,'
          ' "answer_key": [0]}',
        ),
        throwsA(isA<KeyfileFormatException>()),
        reason: sections,
      );
    }
  });

  test('decodes a v2 QR payload', () {
    final p = QrPayload.decode('v2|7|18446744073709551615|ab12cd34|2,0,1');
    expect(p.version, 'v2');
    expect(p.variantId, 7);
    expect(p.seed, BigInt.parse('18446744073709551615'));
    expect(p.countList, [2, 0, 1]);
    expect(p.countsFor(['A', 'B', 'C']), {'A': 2, 'B': 0, 'C': 1});
    expect(p.sourceFingerprint, 'ab12cd34');
  });

  test('rejects malformed v2 QR payloads', () {
    for (final text in [
      'v2|1|5|ab12cd34',
      'v2|1|5||2,1',
      'v2|1|5|ab12cd34|2,x',
      'v2|1|5|ab12cd34|',
    ]) {
      expect(
        () => QrPayload.decode(text),
        throwsA(isA<QrPayloadException>()),
        reason: text,
      );
    }
  });

  group('grading a case sheet', () {
    final key = AnswerKey.parse(keyJson);

    test('case questions stay together, in source order', () {
      for (var seed = 0; seed < 40; seed++) {
        final plan = planFor(key, QrPayload.decode('v2|1|$seed|deadbeef|2,1'));
        expect(plan.sheet, hasLength(4));
        final modeling = [
          for (final q in plan.sheet)
            if (q.section == 'Modeling') q.indexInSection,
        ];
        expect(modeling, anyOf(equals([0, 1, 2]), equals([2, 0, 1])));
      }
    });

    test('all-correct marks score full; QR v1 or wrong counts rejected', () {
      final payload = QrPayload.decode('v2|1|9|deadbeef|2,2');
      final plan = planFor(key, payload);
      final marks = [
        for (final q in plan.sheet)
          q.optionPerm.indexOf(key.answerKey[q.globalIndex]),
      ];
      final result = grade(key: key, payload: payload, marks: marks);
      expect(result.score, 5);
      expect(result.total, 5);

      for (final text in [
        'v1|1|9|1|1|1|deadbeef',
        'v2|1|9|deadbeef|2',
        'v2|1|9|deadbeef|3,1',
      ]) {
        expect(
          () => planFor(key, QrPayload.decode(text)),
          throwsA(isA<GradingException>()),
          reason: text,
        );
      }
    });
  });
}
