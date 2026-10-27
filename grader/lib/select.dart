/// Deterministic variant construction from a seed. Mirror of
/// generator/src/mcexam/select.py.
///
/// RNG stream order (the contract — README 'Determinism & reproducibility'):
/// all section selections first, in key order, then all option scrambles in
/// sheet order. Do not reorder or lazily evaluate.
///
/// A section is a list of units (a standalone question, or a case with several
/// questions). Selection shuffles and draws units; the questions of a selected
/// case follow it in source order. With single-question units in the sections
/// [easy, medium, hard], this is exactly the v1 algorithm.
library;

import 'rng.dart';

const List<String> sectionKeys = ['easy', 'medium', 'hard'];

class SheetQuestion {
  const SheetQuestion({
    required this.section,
    required this.indexInSection,
    required this.globalIndex,
    required this.optionPerm,
    this.unitIndex = 0,
  });

  /// Section key: 'easy' | 'medium' | 'hard', or a section name.
  final String section;
  final int indexInSection;
  final int globalIndex;

  /// 0-based index of its unit (question or case) within the section.
  final int unitIndex;

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

  /// Selected unit indices per section, in sheet order.
  final Map<String, List<int>> selections;
  final List<SheetQuestion> sheet;
}

/// [units]: per section key, in key order, the question count of each unit.
/// [counts]: per section key, the number of units to draw.
VariantPlan buildPlan({
  required BigInt seed,
  required Map<String, List<int>> units,
  required Map<String, int> counts,
  required int optionsPerQuestion,
}) {
  for (final entry in units.entries) {
    final count = counts[entry.key];
    final size = entry.value.length;
    if (count == null || count < 0 || count > size) {
      throw ArgumentError(
        "requested $count '${entry.key}' units but the section has only $size",
      );
    }
  }

  final rng = SplitMix64(seed);

  final selections = <String, List<int>>{};
  for (final entry in units.entries) {
    // All selections first ...
    final indices = List<int>.generate(entry.value.length, (i) => i);
    rng.shuffle(indices);
    selections[entry.key] = List.unmodifiable(
      indices.sublist(0, counts[entry.key]!),
    );
  }

  final sheet = <SheetQuestion>[];
  var sectionOffset = 0;
  for (final entry in units.entries) {
    // ... then option scrambles, in sheet order.
    final sizes = entry.value;
    final unitOffsets = <int>[];
    var running = 0;
    for (final size in sizes) {
      unitOffsets.add(running);
      running += size;
    }
    for (final unit in selections[entry.key]!) {
      for (var k = 0; k < sizes[unit]; k++) {
        final perm = List<int>.generate(optionsPerQuestion, (i) => i);
        rng.shuffle(perm);
        final index = unitOffsets[unit] + k;
        sheet.add(
          SheetQuestion(
            section: entry.key,
            indexInSection: index,
            globalIndex: sectionOffset + index,
            optionPerm: List.unmodifiable(perm),
            unitIndex: unit,
          ),
        );
      }
    }
    sectionOffset += running;
  }
  return VariantPlan(seed: seed, selections: selections, sheet: sheet);
}

/// v1 form: sections [easy, medium, hard] of single-question units.
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
  return buildPlan(
    seed: seed,
    units: {
      for (final key in sectionKeys)
        key: List<int>.filled(sectionSizes[key]!, 1),
    },
    counts: counts,
    optionsPerQuestion: optionsPerQuestion,
  );
}
