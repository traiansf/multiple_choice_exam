import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grader/select.dart';

void main() {
  test('variant plans match shared/test-vectors.json', () {
    final vectors =
        jsonDecode(File('../shared/test-vectors.json').readAsStringSync())
            as Map<String, dynamic>;
    final cases = vectors['variants'] as List<dynamic>;
    expect(cases, isNotEmpty);
    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      final plan = buildVariant(
        seed: BigInt.parse(c['seed'] as String),
        sectionSizes: (c['sections'] as Map<String, dynamic>)
            .cast<String, int>(),
        counts: (c['counts'] as Map<String, dynamic>).cast<String, int>(),
        optionsPerQuestion: c['options_per_question'] as int,
      );
      final expected = c['expected'] as Map<String, dynamic>;
      final expectedSelections =
          (expected['selections'] as Map<String, dynamic>).map(
            (k, v) => MapEntry(k, (v as List<dynamic>).cast<int>()),
          );
      expect(plan.selections, expectedSelections, reason: 'seed ${c['seed']}');
      expect(
        [for (final q in plan.sheet) q.optionPerm],
        (expected['option_perms'] as List<dynamic>)
            .map((p) => (p as List<dynamic>).cast<int>())
            .toList(),
        reason: 'seed ${c['seed']}',
      );
    }
  });

  test('sheet structure: sections grouped, global index offset', () {
    final plan = buildVariant(
      seed: BigInt.from(7),
      sectionSizes: {'easy': 8, 'medium': 6, 'hard': 4},
      counts: {'easy': 3, 'medium': 2, 'hard': 1},
      optionsPerQuestion: 4,
    );
    expect(plan.sheet, hasLength(6));
    expect(
      [for (final q in plan.sheet) q.section],
      ['easy', 'easy', 'easy', 'medium', 'medium', 'hard'],
    );
    const offsets = {'easy': 0, 'medium': 8, 'hard': 14};
    for (final q in plan.sheet) {
      expect(q.globalIndex, offsets[q.section]! + q.indexInSection);
      expect(q.optionPerm.toSet(), {0, 1, 2, 3});
    }
  });

  test('count exceeding section size throws', () {
    expect(
      () => buildVariant(
        seed: BigInt.one,
        sectionSizes: {'easy': 2, 'medium': 2, 'hard': 2},
        counts: {'easy': 3, 'medium': 0, 'hard': 0},
        optionsPerQuestion: 4,
      ),
      throwsArgumentError,
    );
  });
}
