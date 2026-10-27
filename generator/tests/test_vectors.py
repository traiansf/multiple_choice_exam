"""Replays shared/test-vectors.json — the cross-language determinism fixture.
The Dart suite replays the same file; if either side drifts, its suite fails."""

import json
from pathlib import Path

from mcexam.rng import SplitMix64
from mcexam.select import build_plan, build_variant

VECTORS = json.loads(
    (Path(__file__).resolve().parents[2] / "shared" / "test-vectors.json").read_text()
)


def test_splitmix64_streams_match_fixture() -> None:
    for case in VECTORS["splitmix64"]:
        rng = SplitMix64(int(case["seed"]))
        assert [str(rng.next_uint64()) for _ in range(5)] == case["first5"], case["seed"]


def test_variant_plans_match_fixture() -> None:
    assert VECTORS["variants"], "fixture must contain variant cases"
    for case in VECTORS["variants"]:
        plan = build_variant(
            int(case["seed"]), case["sections"], case["counts"], case["options_per_question"]
        )
        expected = case["expected"]
        assert {k: list(v) for k, v in plan.selections.items()} == expected["selections"]
        assert [list(sq.option_perm) for sq in plan.sheet] == expected["option_perms"]


def test_unit_plans_match_fixture() -> None:
    assert VECTORS["unit_plans"], "fixture must contain unit-plan cases"
    for case in VECTORS["unit_plans"]:
        units = {section["name"]: section["units"] for section in case["sections"]}
        counts = dict(zip(units, case["counts"], strict=True))
        plan = build_plan(int(case["seed"]), units, counts, case["options_per_question"])
        expected = case["expected"]
        assert [list(plan.selections[name]) for name in units] == expected["selections"]
        assert [sq.global_index for sq in plan.sheet] == expected["global_indices"]
        assert [list(sq.option_perm) for sq in plan.sheet] == expected["option_perms"]
