"""SplitMix64 PRNG with rejection-sampled bounded ints and Fisher-Yates shuffle.

One half of the cross-language determinism contract: grader/lib/rng.dart must
implement the identical algorithm, and shared/test-vectors.json pins both.
Any change here requires the same change there, regenerated vectors, and a
QR payload version bump.
"""

_MASK64 = (1 << 64) - 1
_GAMMA = 0x9E3779B97F4A7C15
_MIX1 = 0xBF58476D1CE4E5B9
_MIX2 = 0x94D049BB133111EB


class SplitMix64:
    """Vigna's splitmix64 (https://prng.di.unimi.it/splitmix64.c)."""

    def __init__(self, seed: int) -> None:
        self._state = seed & _MASK64

    def next_uint64(self) -> int:
        self._state = (self._state + _GAMMA) & _MASK64
        z = self._state
        z = ((z ^ (z >> 30)) * _MIX1) & _MASK64
        z = ((z ^ (z >> 27)) * _MIX2) & _MASK64
        return z ^ (z >> 31)

    def next_below(self, bound: int) -> int:
        """Uniform int in [0, bound) via rejection sampling (no modulo bias)."""
        if bound <= 0:
            raise ValueError(f"bound must be positive, got {bound}")
        limit = (1 << 64) - ((1 << 64) % bound)
        while True:
            value = self.next_uint64()
            if value < limit:
                return value % bound

    def shuffle(self, items: list) -> None:
        """In-place Fisher-Yates: i from len-1 down to 1, j = next_below(i + 1)."""
        for i in range(len(items) - 1, 0, -1):
            j = self.next_below(i + 1)
            items[i], items[j] = items[j], items[i]
