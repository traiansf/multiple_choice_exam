import pytest

from mcexam.rng import SplitMix64

# Published reference outputs of Vigna's splitmix64.c for seed 0.
# If these ever fail, verify against https://prng.di.unimi.it/splitmix64.c
# before touching the implementation — the constants below are the contract.
SEED0_FIRST3 = [
    0xE220A8397B1DCDAF,
    0x6E789E6AA1B965F4,
    0x06C45D188009454F,
]


def test_seed0_reference_outputs() -> None:
    rng = SplitMix64(0)
    assert [rng.next_uint64() for _ in range(3)] == SEED0_FIRST3


def test_same_seed_same_stream() -> None:
    a, b = SplitMix64(987654321), SplitMix64(987654321)
    assert [a.next_uint64() for _ in range(20)] == [b.next_uint64() for _ in range(20)]


def test_different_seeds_differ() -> None:
    a, b = SplitMix64(1), SplitMix64(2)
    assert [a.next_uint64() for _ in range(4)] != [b.next_uint64() for _ in range(4)]


def test_outputs_fit_in_64_bits() -> None:
    rng = SplitMix64(2**64 - 1)  # max seed must not overflow
    for _ in range(100):
        assert 0 <= rng.next_uint64() < 2**64


def test_next_below_in_range_and_covers_all_values() -> None:
    rng = SplitMix64(7)
    seen = {rng.next_below(5) for _ in range(200)}
    assert seen == {0, 1, 2, 3, 4}


def test_next_below_bound_one_is_zero() -> None:
    assert SplitMix64(3).next_below(1) == 0


def test_next_below_rejects_nonpositive_bound() -> None:
    with pytest.raises(ValueError):
        SplitMix64(3).next_below(0)


def test_shuffle_is_permutation_and_deterministic() -> None:
    a, b = list(range(10)), list(range(10))
    SplitMix64(99).shuffle(a)
    SplitMix64(99).shuffle(b)
    assert a == b
    assert sorted(a) == list(range(10))
    assert a != list(range(10))  # astronomically unlikely to be identity


def test_shuffle_empty_and_single_consume_nothing() -> None:
    rng = SplitMix64(5)
    rng.shuffle([])
    rng.shuffle([42])
    assert rng.next_uint64() == SplitMix64(5).next_uint64()
