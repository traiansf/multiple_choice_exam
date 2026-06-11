# Grader Core (Flutter) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The grader's pure-Dart core: replay the deterministic variant from a seed (mirroring the Python generator exactly, pinned by `shared/test-vectors.json`), load `answer-key.json`, decode the QR payload, and grade a sheet of marks — plus a minimal Flutter app shell so `flutter analyze` / `flutter test` run.

**Architecture:** `flutter create` scaffold; all logic in dependency-free Dart modules under `lib/` (rng, select, keyfile, qr_scan, grading) mirrored 1:1 from the Python generator. The RNG uses `BigInt` for exact unsigned-64-bit semantics (safe on VM and web). OMR image processing and camera UI are explicitly OUT of scope — next PRs.

**Tech Stack:** Flutter 3.44.1 / Dart 3.12 (installed at `~/development/flutter`), `flutter_test`, `flutter_lints`. No external packages.

**Branch:** `feat/grader-core`, commit per task. Flutter binary: `$HOME/development/flutter/bin/flutter`.

**Contract reminders (CLAUDE.md):**
- `rng.dart`/`select.dart` must equal `rng.py`/`select.py`; both suites replay `shared/test-vectors.json`.
- Grader inputs are exactly: `answer-key.json` + QR + scanned marks. Never the exam text.
- Fingerprint mismatch and malformed inputs → flag for manual review (throw typed exceptions), never guess.

---

### Task 1: Scaffold

- [ ] Step 1: `git checkout -b feat/grader-core`
- [ ] Step 2: `cd /home/traian/multiple_choice_exam && $HOME/development/flutter/bin/flutter create --project-name grader --platforms android,ios grader`
- [ ] Step 3: Edit `grader/pubspec.yaml` description to "Grading app for mcexam: scans the QR + OMR answer sheet and grades against answer-key.json." Keep generated deps.
- [ ] Step 4: `cd grader && $HOME/development/flutter/bin/flutter test && $HOME/development/flutter/bin/flutter analyze` → generated template passes.
- [ ] Step 5: Commit `feat: scaffold grader Flutter app`.

### Task 2: `lib/rng.dart`

Test `grader/test/rng_test.dart` (write first, expect compile failure):

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grader/rng.dart';

void main() {
  test('seed 0 matches published splitmix64 reference outputs', () {
    final rng = SplitMix64(BigInt.zero);
    expect(
      [for (var i = 0; i < 3; i++) rng.nextUint64()],
      [
        BigInt.parse('16294208416658607535'), // 0xE220A8397B1DCDAF
        BigInt.parse('7960286522194355700'), // 0x6E789E6AA1B965F4
        BigInt.parse('487617019471545679'), // 0x06C45D188009454F
      ],
    );
  });

  test('hand-derived shuffle vector for seed 0 (see generator test_rng.py)', () {
    // shuffle([0,1,2]) seed 0: i=2 -> j=1 -> [0,2,1]; i=1 -> j=0 -> [2,0,1].
    final items = [0, 1, 2];
    SplitMix64(BigInt.zero).shuffle(items);
    expect(items, [2, 0, 1]);
  });

  test('nextBelow covers range and bound 1 is zero', () {
    final rng = SplitMix64(BigInt.from(7));
    final seen = {for (var i = 0; i < 200; i++) rng.nextBelow(5)};
    expect(seen, {0, 1, 2, 3, 4});
    expect(SplitMix64(BigInt.from(3)).nextBelow(1), 0);
    expect(() => SplitMix64(BigInt.from(3)).nextBelow(0), throwsArgumentError);
  });

  test('shuffle of empty and single lists consumes no randomness', () {
    final rng = SplitMix64(BigInt.from(5));
    rng.shuffle(<int>[]);
    rng.shuffle([42]);
    expect(rng.nextUint64(), SplitMix64(BigInt.from(5)).nextUint64());
  });

  test('raw streams match shared/test-vectors.json', () {
    final vectors = jsonDecode(
      File('../shared/test-vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final raw in vectors['splitmix64'] as List<dynamic>) {
      final c = raw as Map<String, dynamic>;
      final rng = SplitMix64(BigInt.parse(c['seed'] as String));
      expect(
        [for (var i = 0; i < 5; i++) rng.nextUint64().toString()],
        c['first5'],
        reason: 'seed ${c['seed']}',
      );
    }
  });
}
```

Implementation `grader/lib/rng.dart`:

```dart
/// SplitMix64 PRNG with rejection-sampled bounded ints and Fisher-Yates
/// shuffle. Mirror of generator/src/mcexam/rng.py — any change there requires
/// the same change here, regenerated shared/test-vectors.json, and a QR
/// payload version bump. BigInt keeps exact unsigned-64-bit semantics on
/// every Dart platform.
class SplitMix64 {
  SplitMix64(BigInt seed) : _state = seed & _mask64;

  static final BigInt _mask64 = (BigInt.one << 64) - BigInt.one;
  static final BigInt _two64 = BigInt.one << 64;
  static final BigInt _gamma = BigInt.parse('9E3779B97F4A7C15', radix: 16);
  static final BigInt _mix1 = BigInt.parse('BF58476D1CE4E5B9', radix: 16);
  static final BigInt _mix2 = BigInt.parse('94D049BB133111EB', radix: 16);

  BigInt _state;

  BigInt nextUint64() {
    _state = (_state + _gamma) & _mask64;
    var z = _state;
    z = ((z ^ (z >> 30)) * _mix1) & _mask64;
    z = ((z ^ (z >> 27)) * _mix2) & _mask64;
    return z ^ (z >> 31);
  }

  /// Uniform int in [0, bound) via rejection sampling (no modulo bias).
  int nextBelow(int bound) {
    if (bound <= 0) {
      throw ArgumentError.value(bound, 'bound', 'must be positive');
    }
    final big = BigInt.from(bound);
    final limit = _two64 - (_two64 % big);
    while (true) {
      final value = nextUint64();
      if (value < limit) return (value % big).toInt();
    }
  }

  /// In-place Fisher-Yates: i from length-1 down to 1, j = nextBelow(i + 1).
  void shuffle(List<int> items) {
    for (var i = items.length - 1; i >= 1; i--) {
      final j = nextBelow(i + 1);
      final tmp = items[i];
      items[i] = items[j];
      items[j] = tmp;
    }
  }
}
```

Run `flutter test test/rng_test.dart` → pass. Commit `feat: splitmix64 PRNG (mirror of generator rng.py)`.

### Task 3: `lib/select.dart` + vector replay

Test `grader/test/select_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grader/select.dart';

void main() {
  test('variant plans match shared/test-vectors.json', () {
    final vectors = jsonDecode(
      File('../shared/test-vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final cases = vectors['variants'] as List<dynamic>;
    expect(cases, isNotEmpty);
    for (final raw in cases) {
      final c = raw as Map<String, dynamic>;
      final plan = buildVariant(
        seed: BigInt.parse(c['seed'] as String),
        sectionSizes: (c['sections'] as Map<String, dynamic>).cast<String, int>(),
        counts: (c['counts'] as Map<String, dynamic>).cast<String, int>(),
        optionsPerQuestion: c['options_per_question'] as int,
      );
      final expected = c['expected'] as Map<String, dynamic>;
      final expectedSelections =
          (expected['selections'] as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as List<dynamic>).cast<int>()));
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
```

Implementation `grader/lib/select.dart`:

```dart
/// Deterministic variant construction from a seed. Mirror of
/// generator/src/mcexam/select.py.
///
/// RNG stream order (the contract — README 'Determinism & reproducibility'):
/// all section selections first, in [easy, medium, hard] order, then all
/// option scrambles in sheet order. Do not reorder or lazily evaluate.
library;

import 'rng.dart';

const List<String> sectionKeys = ['easy', 'medium', 'hard'];

class SheetQuestion {
  const SheetQuestion({
    required this.section,
    required this.indexInSection,
    required this.globalIndex,
    required this.optionPerm,
  });

  final String section;
  final int indexInSection;
  final int globalIndex;

  /// Sheet position p shows original option optionPerm[p].
  final List<int> optionPerm;
}

class VariantPlan {
  const VariantPlan({
    required this.seed,
    required this.selections,
    required this.sheet,
  });

  final BigInt seed;
  final Map<String, List<int>> selections;
  final List<SheetQuestion> sheet;
}

VariantPlan buildVariant({
  required BigInt seed,
  required Map<String, int> sectionSizes,
  required Map<String, int> counts,
  required int optionsPerQuestion,
}) {
  for (final key in sectionKeys) {
    final count = counts[key]!;
    final size = sectionSizes[key]!;
    if (count < 0 || count > size) {
      throw ArgumentError(
        "requested $count '$key' questions but the section has only $size",
      );
    }
  }

  final rng = SplitMix64(seed);

  final selections = <String, List<int>>{};
  for (final key in sectionKeys) {
    // All selections first ...
    final indices = List<int>.generate(sectionSizes[key]!, (i) => i);
    rng.shuffle(indices);
    selections[key] = indices.sublist(0, counts[key]!);
  }

  final offsets = <String, int>{};
  var running = 0;
  for (final key in sectionKeys) {
    offsets[key] = running;
    running += sectionSizes[key]!;
  }

  final sheet = <SheetQuestion>[];
  for (final key in sectionKeys) {
    // ... then option scrambles, in sheet order.
    for (final index in selections[key]!) {
      final perm = List<int>.generate(optionsPerQuestion, (i) => i);
      rng.shuffle(perm);
      sheet.add(
        SheetQuestion(
          section: key,
          indexInSection: index,
          globalIndex: offsets[key]! + index,
          optionPerm: perm,
        ),
      );
    }
  }
  return VariantPlan(seed: seed, selections: selections, sheet: sheet);
}
```

Run, pass, commit `feat: deterministic variant replay (mirror of select.py)`.

### Task 4: `lib/keyfile.dart`

Test `grader/test/keyfile_test.dart`:

```dart
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
        isA<KeyfileFormatException>()
            .having((e) => e.message, 'message', contains(message)),
      ),
    );
  }

  test('rejects unsupported version', () {
    expectRejects(validJson.replaceFirst('"version": 1', '"version": 2'),
        'version');
  });

  test('rejects malformed json', () {
    expectRejects('not json', 'not valid JSON');
  });

  test('rejects missing field', () {
    expectRejects(
        validJson.replaceFirst('"exam_title": "Sample Exam",', ''), 'exam_title');
  });

  test('rejects answer index out of range', () {
    expectRejects(
        validJson.replaceFirst('[1, 2, 2, 1, 0, 2, 1, 1]',
            '[1, 2, 2, 1, 0, 2, 1, 4]'),
        'answer_key');
  });

  test('rejects answer_key length not matching sections', () {
    expectRejects(
        validJson.replaceFirst('[1, 2, 2, 1, 0, 2, 1, 1]', '[1, 2, 2]'),
        'answer_key');
  });

  test('rejects missing section key', () {
    expectRejects(
        validJson.replaceFirst('"hard": 2', '"brutal": 2'), 'sections');
  });
}
```

Implementation `grader/lib/keyfile.dart`:

```dart
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
    if (version != supportedVersion) {
      throw KeyfileFormatException(
        'unsupported key file version $version (this build reads'
        ' $supportedVersion)',
      );
    }
    final examTitle = _string(decoded, 'exam_title');
    final fingerprint = _string(decoded, 'source_fingerprint');
    final optionsPerQuestion = _int(decoded, 'options_per_question');
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
          "'answer_key' entries must be integers in [0,"
          ' $optionsPerQuestion)',
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

  static int _int(Map<String, dynamic> map, String field) {
    final value = map[field];
    if (value is! int || value <= 0) {
      throw KeyfileFormatException("missing or malformed '$field'");
    }
    return value;
  }
}
```

Run, pass, commit `feat: answer-key.json reader with strict validation`.

### Task 5: `lib/qr_scan.dart` payload codec

Test `grader/test/qr_scan_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:grader/qr_scan.dart';

void main() {
  test('decodes a valid v1 payload including max seed', () {
    final p = QrPayload.decode('v1|3|18446744073709551615|10|8|2|ab12cd34');
    expect(p.variantId, 3);
    expect(p.seed, BigInt.parse('18446744073709551615'));
    expect(p.counts, {'easy': 10, 'medium': 8, 'hard': 2});
    expect(p.sourceFingerprint, 'ab12cd34');
  });

  void expectRejects(String text, Pattern message) {
    expect(
      () => QrPayload.decode(text),
      throwsA(
        isA<QrPayloadException>()
            .having((e) => e.message, 'message', contains(message)),
      ),
    );
  }

  test('rejects wrong field count', () {
    expectRejects('v1|1|2|3', 'expected 7 fields');
  });

  test('rejects unknown version', () {
    expectRejects('v9|3|5|10|8|2|ab12cd34', 'version');
  });

  test('rejects non-numeric and negative fields', () {
    expectRejects('v1|x|5|10|8|2|ab12cd34', 'variant id');
    expectRejects('v1|3|-5|10|8|2|ab12cd34', 'seed');
    expectRejects('v1|3|5|-1|8|2|ab12cd34', 'count');
  });

  test('rejects seed exceeding 64 bits', () {
    expectRejects('v1|3|18446744073709551616|10|8|2|ab12cd34', 'seed');
  });
}
```

Implementation `grader/lib/qr_scan.dart`:

```dart
/// QR payload codec. Format is produced by generator/src/mcexam/qr.py and
/// documented in README 'QR payload' — bump the version on ANY field change:
///     v1|<variant_id>|<seed>|<n_easy>|<n_medium>|<n_hard>|<source_fp>
/// Camera scanning (mobile_scanner) wires into this in a later milestone.
library;

class QrPayloadException implements Exception {
  QrPayloadException(this.message);

  final String message;

  @override
  String toString() => 'QrPayloadException: $message';
}

class QrPayload {
  const QrPayload({
    required this.variantId,
    required this.seed,
    required this.nEasy,
    required this.nMedium,
    required this.nHard,
    required this.sourceFingerprint,
  });

  static const String supportedVersion = 'v1';
  static final BigInt _two64 = BigInt.one << 64;

  final int variantId;
  final BigInt seed;
  final int nEasy;
  final int nMedium;
  final int nHard;
  final String sourceFingerprint;

  Map<String, int> get counts =>
      {'easy': nEasy, 'medium': nMedium, 'hard': nHard};

  static QrPayload decode(String text) {
    final parts = text.split('|');
    if (parts.length != 7) {
      throw QrPayloadException(
        'malformed QR payload: expected 7 fields, got ${parts.length}',
      );
    }
    if (parts[0] != supportedVersion) {
      throw QrPayloadException(
        "unsupported QR payload version '${parts[0]}' (this build reads"
        " '$supportedVersion')",
      );
    }
    final seed = BigInt.tryParse(parts[2]);
    if (seed == null || seed < BigInt.zero || seed >= _two64) {
      throw QrPayloadException(
        "seed '${parts[2]}' is not an unsigned 64-bit integer",
      );
    }
    return QrPayload(
      variantId: _count(parts[1], 'variant id'),
      seed: seed,
      nEasy: _count(parts[3], 'count'),
      nMedium: _count(parts[4], 'count'),
      nHard: _count(parts[5], 'count'),
      sourceFingerprint: parts[6],
    );
  }

  static int _count(String text, String what) {
    final value = int.tryParse(text);
    if (value == null || value < 0) {
      throw QrPayloadException("$what '$text' is not a non-negative integer");
    }
    return value;
  }
}
```

Run, pass, commit `feat: QR payload decoder`.

### Task 6: `lib/grading.dart` + round-trip test

Test `grader/test/grading_test.dart`:

```dart
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

  List<int> correctMarks(VariantPlan plan) => [
        for (final q in plan.sheet)
          q.optionPerm.indexOf(key.answerKey[q.globalIndex]),
      ];

  VariantPlan planFor(QrPayload p) => buildVariant(
        seed: p.seed,
        sectionSizes: key.sections,
        counts: p.counts,
        optionsPerQuestion: key.optionsPerQuestion,
      );

  test('round trip: all-correct marks score full', () {
    final result = grade(key: key, payload: payload, marks: correctMarks(planFor(payload)));
    expect(result.score, 5);
    expect(result.total, 5);
    expect(result.perQuestion.every((q) => q.correct), isTrue);
  });

  test('round trip: alternating wrong marks score the expected pattern', () {
    final plan = planFor(payload);
    final marks = <int?>[];
    final correct = correctMarks(plan);
    for (var row = 0; row < plan.sheet.length; row++) {
      marks.add(row.isEven ? correct[row] : (correct[row] + 1) % 4);
    }
    final result = grade(key: key, payload: payload, marks: marks);
    expect([for (final q in result.perQuestion) q.correct],
        [true, false, true, false, true]);
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
      throwsA(isA<GradingException>()
          .having((e) => e.message, 'message', contains('fingerprint'))),
    );
  });

  test('marks length mismatch is flagged', () {
    expect(
      () => grade(key: key, payload: payload, marks: [0, 1]),
      throwsA(isA<GradingException>()
          .having((e) => e.message, 'message', contains('marks'))),
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
      throwsA(isA<GradingException>()
          .having((e) => e.message, 'message', contains('position'))),
    );
  });
}
```

Implementation `grader/lib/grading.dart`:

```dart
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
    final correctPosition =
        question.optionPerm.indexOf(key.answerKey[question.globalIndex]);
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
```

Run, pass, commit `feat: grading engine with round-trip tests`.

### Task 7: Minimal app shell

Replace `grader/lib/main.dart`:

```dart
import 'package:flutter/material.dart';

void main() => runApp(const GraderApp());

class GraderApp extends StatelessWidget {
  const GraderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MC Exam Grader',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MC Exam Grader')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Workflow', style: TextStyle(fontSize: 20)),
            SizedBox(height: 12),
            Text('1. Load answer-key.json for the exam'),
            Text('2. Scan the QR code on a student sheet'),
            Text('3. Scan the bubble sheet'),
            Text('4. Review the score and per-question breakdown'),
            SizedBox(height: 24),
            Text(
              'The grading engine is implemented and tested; QR camera'
              ' scanning and OMR sheet detection arrive in the next'
              ' milestone.',
            ),
          ],
        ),
      ),
    );
  }
}
```

Replace `grader/test/widget_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:grader/main.dart';

void main() {
  testWidgets('home screen renders', (tester) async {
    await tester.pumpWidget(const GraderApp());
    expect(find.text('MC Exam Grader'), findsOneWidget);
  });
}
```

Run `flutter test` (all) + `flutter analyze`. Commit `feat: minimal grader app shell`.

### Task 8: Final verification

- [ ] `flutter test` → all pass; `flutter analyze` → no issues.
- [ ] `cd ../generator && ../.venv/bin/pytest -q` → still green (nothing changed, sanity).
- [ ] Review diff vs main; push branch; open PR with summary + known limitations (no OMR, no camera, UI placeholder).
