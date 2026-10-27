"""Deterministic variant construction from a seed. Mirror of grader/lib/select.dart.

RNG stream order (the contract — see README 'Determinism & reproducibility'):
all section selections first, in key order, then all option scrambles in
sheet order. Do not reorder or lazily evaluate.

A section is a list of units (a standalone question, or a case with several
questions). Selection shuffles and draws units; the questions of a selected
case follow it in source order. With single-question units in the sections
[easy, medium, hard], this is exactly the v1 algorithm.
"""

from collections.abc import Mapping, Sequence
from dataclasses import dataclass

from .model import SECTION_KEYS
from .rng import SplitMix64


@dataclass(frozen=True)
class SheetQuestion:
    section: str  # section key: "easy" | "medium" | "hard", or a section name
    index_in_section: int  # 0-based index of the original question within its section
    global_index: int  # 0-based index in key order (answer_key index)
    option_perm: tuple[int, ...]  # sheet position p shows original option option_perm[p]
    unit_index: int = 0  # 0-based index of its unit within the section


@dataclass(frozen=True)
class VariantPlan:
    seed: int
    selections: dict[str, tuple[int, ...]]  # selected unit indices per section, in sheet order
    sheet: tuple[SheetQuestion, ...]


def build_plan(
    seed: int,
    units: Mapping[str, Sequence[int]],
    counts: Mapping[str, int],
    options_per_question: int,
) -> VariantPlan:
    """units: per section key (in key order), the question count of each unit.
    counts: per section key, the number of units to draw."""
    for key, sizes in units.items():
        if not 0 <= counts[key] <= len(sizes):
            raise ValueError(
                f"requested {counts[key]} '{key}' units but the section has only {len(sizes)}"
            )

    rng = SplitMix64(seed)

    selections: dict[str, tuple[int, ...]] = {}
    for key, sizes in units.items():  # all selections first ...
        indices = list(range(len(sizes)))
        rng.shuffle(indices)
        selections[key] = tuple(indices[: counts[key]])

    sheet: list[SheetQuestion] = []
    section_offset = 0
    for key, sizes in units.items():  # ... then option scrambles, in sheet order
        unit_offsets = [sum(sizes[:u]) for u in range(len(sizes))]
        for unit in selections[key]:
            for k in range(sizes[unit]):
                perm = list(range(options_per_question))
                rng.shuffle(perm)
                index = unit_offsets[unit] + k
                sheet.append(
                    SheetQuestion(
                        section=key,
                        index_in_section=index,
                        global_index=section_offset + index,
                        option_perm=tuple(perm),
                        unit_index=unit,
                    )
                )
        section_offset += sum(sizes)
    return VariantPlan(seed=seed, selections=selections, sheet=tuple(sheet))


def build_variant(
    seed: int,
    section_sizes: Mapping[str, int],
    counts: Mapping[str, int],
    options_per_question: int,
) -> VariantPlan:
    """v1 form: sections [easy, medium, hard] of single-question units."""
    for key in SECTION_KEYS:
        if not 0 <= counts[key] <= section_sizes[key]:
            raise ValueError(
                f"requested {counts[key]} '{key}' questions but the section has"
                f" only {section_sizes[key]}"
            )
    units = {key: [1] * section_sizes[key] for key in SECTION_KEYS}
    return build_plan(seed, units, counts, options_per_question)


def variant_seeds(base_seed: int, count: int) -> list[int]:
    """Per-variant seeds derived from the base seed (generator-internal: the
    actual per-variant seed always travels in the QR, so the grader never
    needs this derivation)."""
    rng = SplitMix64(base_seed)
    return [rng.next_uint64() for _ in range(count)]
