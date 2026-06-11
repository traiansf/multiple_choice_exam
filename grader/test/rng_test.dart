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

  test(
    'hand-derived shuffle vector for seed 0 (see generator test_rng.py)',
    () {
      // shuffle([0,1,2]) seed 0: i=2 -> j=1 -> [0,2,1]; i=1 -> j=0 -> [2,0,1].
      final items = [0, 1, 2];
      SplitMix64(BigInt.zero).shuffle(items);
      expect(items, [2, 0, 1]);
    },
  );

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
    final vectors =
        jsonDecode(File('../shared/test-vectors.json').readAsStringSync())
            as Map<String, dynamic>;
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
