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
