/// SplitMix64 PRNG with rejection-sampled bounded ints and Fisher-Yates
/// shuffle. Mirror of generator/src/mcexam/rng.py — any change there requires
/// the same change here, regenerated shared/test-vectors.json, and a QR
/// payload version bump. BigInt keeps exact unsigned-64-bit semantics on
/// every Dart platform.
library;

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
