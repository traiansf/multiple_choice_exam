"""Deterministic variant construction from a seed. Mirror of grader/lib/select.dart.

RNG stream order (the contract — see README 'Determinism & reproducibility'):
all section selections first, in [easy, medium, hard] order, then all option
scrambles in sheet order. Do not reorder or lazily evaluate.
"""

from dataclasses import dataclass

from .model import SECTION_KEYS
from .rng import SplitMix64


@dataclass(frozen=True)
class SheetQuestion:
    section: str  # "easy" | "medium" | "hard"
    index_in_section: int  # 0-based index of the original question within its section
    global_index: int  # 0-based index in source order (easy ++ medium ++ hard)
    option_perm: tuple[int, ...]  # sheet position p shows original option option_perm[p]


@dataclass(frozen=True)
class VariantPlan:
    seed: int
    selections: dict[str, tuple[int, ...]]  # per section, in sheet order
    sheet: tuple[SheetQuestion, ...]


def build_variant(
    seed: int,
    section_sizes: dict[str, int],
    counts: dict[str, int],
    options_per_question: int,
) -> VariantPlan:
    for key in SECTION_KEYS:
        if not 0 <= counts[key] <= section_sizes[key]:
            raise ValueError(
                f"requested {counts[key]} '{key}' questions but the section has"
                f" only {section_sizes[key]}"
            )

    rng = SplitMix64(seed)

    selections: dict[str, tuple[int, ...]] = {}
    for key in SECTION_KEYS:  # all selections first ...
        indices = list(range(section_sizes[key]))
        rng.shuffle(indices)
        selections[key] = tuple(indices[: counts[key]])

    offsets: dict[str, int] = {}
    running = 0
    for key in SECTION_KEYS:
        offsets[key] = running
        running += section_sizes[key]

    sheet: list[SheetQuestion] = []
    for key in SECTION_KEYS:  # ... then option scrambles, in sheet order
        for index in selections[key]:
            perm = list(range(options_per_question))
            rng.shuffle(perm)
            sheet.append(
                SheetQuestion(
                    section=key,
                    index_in_section=index,
                    global_index=offsets[key] + index,
                    option_perm=tuple(perm),
                )
            )
    return VariantPlan(seed=seed, selections=selections, sheet=tuple(sheet))


def variant_seeds(base_seed: int, count: int) -> list[int]:
    """Per-variant seeds derived from the base seed (generator-internal: the
    actual per-variant seed always travels in the QR, so the grader never
    needs this derivation)."""
    rng = SplitMix64(base_seed)
    return [rng.next_uint64() for _ in range(count)]
