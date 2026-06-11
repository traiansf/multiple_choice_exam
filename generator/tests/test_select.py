import pytest

from mcexam.select import build_variant, variant_seeds

SIZES = {"easy": 8, "medium": 6, "hard": 4}
COUNTS = {"easy": 3, "medium": 2, "hard": 1}


def test_deterministic_for_same_seed() -> None:
    assert build_variant(42, SIZES, COUNTS, 4) == build_variant(42, SIZES, COUNTS, 4)


def test_different_seeds_give_different_plans() -> None:
    assert build_variant(1, SIZES, COUNTS, 4) != build_variant(2, SIZES, COUNTS, 4)


def test_sheet_structure() -> None:
    plan = build_variant(7, SIZES, COUNTS, 4)
    assert len(plan.sheet) == 6
    assert [sq.section for sq in plan.sheet] == ["easy"] * 3 + ["medium"] * 2 + ["hard"]
    for sq in plan.sheet:
        assert 0 <= sq.index_in_section < SIZES[sq.section]
        assert sorted(sq.option_perm) == [0, 1, 2, 3]
    # global_index = section offset + index_in_section
    offsets = {"easy": 0, "medium": 8, "hard": 14}
    for sq in plan.sheet:
        assert sq.global_index == offsets[sq.section] + sq.index_in_section


def test_selection_indices_are_distinct() -> None:
    plan = build_variant(11, SIZES, COUNTS, 4)
    for key, selected in plan.selections.items():
        assert len(set(selected)) == len(selected) == COUNTS[key]


def test_selections_are_prefix_stable_in_count() -> None:
    """The full section array is shuffled regardless of n, so a smaller draw is a
    prefix of a larger one. Guards the 'all selections first' RNG stream order."""
    small = build_variant(7, SIZES, COUNTS, 4)
    big = build_variant(7, SIZES, {"easy": 6, "medium": 5, "hard": 3}, 4)
    for key in SIZES:
        n = len(small.selections[key])
        assert big.selections[key][:n] == small.selections[key]


def test_count_exceeding_section_is_error() -> None:
    with pytest.raises(ValueError, match="only 4"):
        build_variant(1, SIZES, {"easy": 1, "medium": 1, "hard": 5}, 4)


def test_variant_seeds_deterministic() -> None:
    assert variant_seeds(123, 5) == variant_seeds(123, 5)
    assert len(set(variant_seeds(123, 5))) == 5
