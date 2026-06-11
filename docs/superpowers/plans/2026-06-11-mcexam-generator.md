# mcexam Generator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the `mcexam` Python CLI (`lint`, `generate`, `scramble`) that parses an exam Markdown file, validates it, and emits print-ready PDF variants + `answer-key.json`, plus the `shared/test-vectors.json` determinism fixture.

**Architecture:** A `src/`-layout package `mcexam` with small single-purpose modules (parser ≠ validator ≠ rng ≠ select ≠ render). The deterministic core (`rng.py` + `select.py`) implements the README's splitmix64 / Fisher–Yates contract exactly and is pinned by `shared/test-vectors.json`, which is *generated from the Python implementation* once its splitmix64 core is verified against published reference outputs. Rendering separates pure geometry (testable) from canvas drawing.

**Tech Stack:** Python ≥3.11, `click` (CLI), `segno` (QR), `reportlab` (PDF), `pytest` + `ruff` (dev). Repo venv at `.venv/` already has all of these.

**Branch:** work on `feat/generator`, commit per task.

**Key contract reminders (from CLAUDE.md):**
- RNG stream order: all section selections (Easy, Medium, Hard) first, then all option scrambles in sheet order.
- Fisher–Yates: `i` from `len-1` down to `1`, `j = next_below(i + 1)`, swap.
- Bounded ints by rejection sampling — never `%` directly on the raw output.
- `scramble` emits only Markdown, never a key file.
- 64-bit values are stored as **decimal strings** in JSON (Dart-safe).

---

### Task 1: Package scaffold

**Files:**
- Create: `generator/pyproject.toml`
- Create: `generator/src/mcexam/__init__.py`
- Create: `generator/tests/test_package.py`

- [ ] **Step 1: Create branch**

```bash
cd /home/traian/multiple_choice_exam && git checkout -b feat/generator
```

- [ ] **Step 2: Write `generator/pyproject.toml`**

```toml
[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[project]
name = "mcexam"
version = "0.1.0"
description = "Randomized multiple-choice exam generator (PDF variants + QR + OMR answer sheet)"
requires-python = ">=3.11"
license = "GPL-3.0-or-later"
dependencies = [
    "click>=8.1",
    "reportlab>=4.0",
    "segno>=1.6",
]

[project.optional-dependencies]
dev = [
    "pytest>=8",
    "ruff>=0.5",
]

[project.scripts]
mcexam = "mcexam.cli:main"

[tool.setuptools.packages.find]
where = ["src"]

[tool.ruff]
line-length = 100
src = ["src", "tests"]

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B", "SIM"]

[tool.pytest.ini_options]
testpaths = ["tests"]
```

- [ ] **Step 3: Write `generator/src/mcexam/__init__.py`**

```python
"""mcexam — randomized multiple-choice exam generator."""

__version__ = "0.1.0"
```

- [ ] **Step 4: Write the smoke test `generator/tests/test_package.py`**

```python
import mcexam


def test_version() -> None:
    assert mcexam.__version__ == "0.1.0"
```

- [ ] **Step 5: Install editable and run the test**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pip install -e ".[dev]" -q && ../.venv/bin/pytest -q`
Expected: `1 passed`

(Note: `cli.py` doesn't exist yet so the `mcexam` console script will fail if invoked — that's fine; it is wired up in Task 11.)

- [ ] **Step 6: Commit**

```bash
git add generator/ && git commit -m "feat: scaffold mcexam package (src layout, pyproject, dev tooling)"
```

---

### Task 2: `rng.py` — SplitMix64 + rejection sampling + Fisher–Yates

**Files:**
- Create: `generator/src/mcexam/rng.py`
- Test: `generator/tests/test_rng.py`

- [ ] **Step 1: Write the failing tests**

```python
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
    import pytest

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_rng.py -q`
Expected: collection error — `ModuleNotFoundError: No module named 'mcexam.rng'`

- [ ] **Step 3: Write `generator/src/mcexam/rng.py`**

```python
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_rng.py -q`
Expected: `10 passed`

- [ ] **Step 5: Commit**

```bash
git add generator/src/mcexam/rng.py generator/tests/test_rng.py
git commit -m "feat: splitmix64 PRNG with rejection sampling and Fisher-Yates"
```

---

### Task 3: `model.py` + `parser.py`

**Files:**
- Create: `generator/src/mcexam/model.py`
- Create: `generator/src/mcexam/parser.py`
- Create: `generator/tests/samples.py`
- Test: `generator/tests/test_parser.py`

- [ ] **Step 1: Write `generator/tests/samples.py` (shared fixture text)**

```python
"""Sample exam markdown used across the test suite. Sizes: easy 3, medium 3, hard 2; M=4."""

SAMPLE_MD = """\
# Sample Exam

## Easy

### What is 2 + 2?
- [ ] 3
- [x] 4
- [ ] 5
- [ ] 6

### What color is the sky on a clear day?
- [ ] Green
- [ ] Red
- [x] Blue
- [ ] Yellow

### How many days are in a week?
- [ ] 5
- [ ] 6
- [x] 7
- [ ] 8

## Medium

### What is 12 × 12?
- [ ] 124
- [x] 144
- [ ] 154
- [ ] 122

### Which planet is closest to the Sun?
- [x] Mercury
- [ ] Venus
- [ ] Mars
- [ ] Earth

### What is the square root of 81?
- [ ] 7
- [ ] 8
- [x] 9
- [ ] 11

## Hard

### What is the derivative of sin(x)?
- [ ] -sin(x)
- [x] cos(x)
- [ ] -cos(x)
- [ ] tan(x)

### Evaluate the integral of 2x from 0 to 3.
- [ ] 6
- [x] 9
- [ ] 12
- [ ] 3
"""
```

- [ ] **Step 2: Write the failing tests `generator/tests/test_parser.py`**

```python
import pytest
from samples import SAMPLE_MD

from mcexam.parser import ParseError, parse


def test_parses_sample_structure() -> None:
    raw = parse(SAMPLE_MD)
    assert [t for _, t in raw.titles] == ["Sample Exam"]
    assert [s.name for s in raw.sections] == ["Easy", "Medium", "Hard"]
    assert [len(s.questions) for s in raw.sections] == [3, 3, 2]
    first = raw.sections[0].questions[0]
    assert first.prompt == "What is 2 + 2?"
    assert [o.text for o in first.options] == ["3", "4", "5", "6"]
    assert [o.checked for o in first.options] == [False, True, False, False]


def test_uppercase_x_counts_as_checked() -> None:
    raw = parse("# T\n\n## Easy\n\n### Q?\n- [X] yes\n- [ ] no\n")
    assert raw.sections[0].questions[0].options[0].checked


def test_question_before_section_is_error() -> None:
    with pytest.raises(ParseError, match="line 3"):
        parse("# T\n\n### Q?\n- [x] a\n- [ ] b\n")


def test_option_outside_question_is_error() -> None:
    with pytest.raises(ParseError, match="line 3"):
        parse("# T\n\n- [x] stray\n")


def test_unrecognized_content_is_error() -> None:
    with pytest.raises(ParseError, match="line 5"):
        parse("# T\n\n## Easy\n\nsome prose\n")


def test_blank_lines_and_trailing_whitespace_ignored() -> None:
    raw = parse("# T  \n\n\n## Easy   \n\n### Q?  \n- [x] a\n- [ ] b   \n")
    assert raw.titles[0][1] == "T"
    assert raw.sections[0].questions[0].options[1].text == "b"
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_parser.py -q`
Expected: `ModuleNotFoundError: No module named 'mcexam.parser'`

- [ ] **Step 4: Write `generator/src/mcexam/model.py`**

```python
"""Typed exam model produced by the validator and consumed downstream."""

from dataclasses import dataclass

SECTION_NAMES = ("Easy", "Medium", "Hard")
SECTION_KEYS = ("easy", "medium", "hard")


@dataclass(frozen=True)
class Question:
    prompt: str
    options: tuple[str, ...]
    answer: int  # 0-based index into options of the correct one


@dataclass(frozen=True)
class Exam:
    title: str
    sections: dict[str, tuple[Question, ...]]  # keys: "easy", "medium", "hard"

    @property
    def options_per_question(self) -> int:
        for key in SECTION_KEYS:
            for question in self.sections[key]:
                return len(question.options)
        raise ValueError("exam has no questions")

    def section_sizes(self) -> dict[str, int]:
        return {key: len(self.sections[key]) for key in SECTION_KEYS}

    def answer_key(self) -> list[int]:
        """Correct-option indices in source order: all easy, then medium, then hard."""
        return [q.answer for key in SECTION_KEYS for q in self.sections[key]]
```

- [ ] **Step 5: Write `generator/src/mcexam/parser.py`**

```python
"""Markdown exam parser: text -> raw structure. Semantic rules live in validator.py."""

import re
from dataclasses import dataclass, field


class ParseError(ValueError):
    def __init__(self, line_no: int, message: str) -> None:
        super().__init__(f"line {line_no}: {message}")
        self.line_no = line_no


@dataclass
class RawOption:
    line_no: int
    text: str
    checked: bool


@dataclass
class RawQuestion:
    line_no: int
    prompt: str
    options: list[RawOption] = field(default_factory=list)


@dataclass
class RawSection:
    line_no: int
    name: str
    questions: list[RawQuestion] = field(default_factory=list)


@dataclass
class RawExam:
    titles: list[tuple[int, str]] = field(default_factory=list)
    sections: list[RawSection] = field(default_factory=list)


_OPTION_RE = re.compile(r"^- \[( |x|X)\] (.*\S.*)$")


def parse(text: str) -> RawExam:
    exam = RawExam()
    section: RawSection | None = None
    question: RawQuestion | None = None
    for line_no, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.rstrip()
        if not line:
            continue
        if line.startswith("### "):
            if section is None:
                raise ParseError(line_no, "question heading before any '##' section")
            question = RawQuestion(line_no, line[4:].strip())
            section.questions.append(question)
        elif line.startswith("## "):
            section = RawSection(line_no, line[3:].strip())
            question = None
            exam.sections.append(section)
        elif line.startswith("# "):
            exam.titles.append((line_no, line[2:].strip()))
        elif match := _OPTION_RE.match(line):
            if question is None:
                raise ParseError(line_no, "option list item outside a '###' question")
            question.options.append(
                RawOption(line_no, match.group(2).strip(), match.group(1) in "xX")
            )
        else:
            raise ParseError(
                line_no,
                f"unrecognized content: {line!r} (expected a heading, '- [ ] option', or blank line)",
            )
    return exam
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_parser.py -q`
Expected: `6 passed`

- [ ] **Step 7: Commit**

```bash
git add generator/src/mcexam/model.py generator/src/mcexam/parser.py generator/tests/samples.py generator/tests/test_parser.py
git commit -m "feat: exam model and markdown parser"
```

---

### Task 4: `validator.py`

**Files:**
- Create: `generator/src/mcexam/validator.py`
- Test: `generator/tests/test_validator.py`

- [ ] **Step 1: Write the failing tests**

```python
import pytest
from samples import SAMPLE_MD

from mcexam.validator import ValidationError, load_exam


def test_valid_sample_builds_exam() -> None:
    exam = load_exam(SAMPLE_MD)
    assert exam.title == "Sample Exam"
    assert exam.section_sizes() == {"easy": 3, "medium": 3, "hard": 2}
    assert exam.options_per_question == 4
    assert exam.answer_key() == [1, 2, 2, 1, 0, 2, 1, 1]


def _replace(old: str, new: str) -> str:
    assert old in SAMPLE_MD
    return SAMPLE_MD.replace(old, new)


def expect_error(text: str, fragment: str) -> None:
    with pytest.raises(ValidationError, match=fragment):
        load_exam(text)


def test_missing_title() -> None:
    expect_error(_replace("# Sample Exam\n\n", ""), "missing exam title")


def test_multiple_titles() -> None:
    expect_error(SAMPLE_MD + "\n# Another Title\n", "multiple '#' titles")


def test_missing_section() -> None:
    text = SAMPLE_MD.split("## Hard")[0]
    expect_error(text, "missing required section '## Hard'")


def test_unknown_section_name() -> None:
    expect_error(_replace("## Easy", "## Trivial"), "unknown section")


def test_duplicate_section() -> None:
    expect_error(_replace("## Medium", "## Easy"), "duplicate section")


def test_zero_checked_options() -> None:
    expect_error(_replace("- [x] 4", "- [ ] 4"), "has 0 '- \\[x\\]' marks")


def test_multiple_checked_options() -> None:
    expect_error(_replace("- [ ] 3", "- [x] 3"), "has 2 '- \\[x\\]' marks")


def test_non_uniform_option_counts() -> None:
    expect_error(_replace("- [ ] 6\n", ""), "non-uniform option counts")


def test_question_with_too_few_options() -> None:
    text = _replace(
        "### What is 2 + 2?\n- [ ] 3\n- [x] 4\n- [ ] 5\n- [ ] 6\n",
        "### What is 2 + 2?\n- [x] 4\n",
    )
    expect_error(text, "at least 2 options")


def test_empty_section() -> None:
    text = SAMPLE_MD.split("## Hard")[0] + "## Hard\n"
    expect_error(text, "has no questions")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_validator.py -q`
Expected: `ModuleNotFoundError: No module named 'mcexam.validator'`

- [ ] **Step 3: Write `generator/src/mcexam/validator.py`**

```python
"""Semantic validation: RawExam -> Exam. This module is the executable spec of
the exam Markdown format (mirrored in README 'The exam Markdown format')."""

from .model import SECTION_KEYS, SECTION_NAMES, Exam, Question
from .parser import RawExam, RawSection, parse


class ValidationError(ValueError):
    pass


def validate(raw: RawExam) -> Exam:
    errors: list[str] = []

    if not raw.titles:
        errors.append("missing exam title: add exactly one '# Title' heading")
    elif len(raw.titles) > 1:
        extra = ", ".join(f"line {line_no}" for line_no, _ in raw.titles[1:])
        errors.append(f"multiple '#' titles (extra at {extra}); keep exactly one")

    by_name: dict[str, RawSection] = {}
    for section in raw.sections:
        if section.name not in SECTION_NAMES:
            errors.append(
                f"line {section.line_no}: unknown section '## {section.name}'"
                f" (expected one of: {', '.join(SECTION_NAMES)})"
            )
        elif section.name in by_name:
            errors.append(f"line {section.line_no}: duplicate section '## {section.name}'")
        else:
            by_name[section.name] = section
    for name in SECTION_NAMES:
        if name not in by_name:
            errors.append(f"missing required section '## {name}'")

    option_counts: dict[int, int] = {}
    for name in SECTION_NAMES:
        section = by_name.get(name)
        if section is None:
            continue
        if not section.questions:
            errors.append(f"section '## {name}' has no questions")
        for question in section.questions:
            checked = sum(1 for option in question.options if option.checked)
            if len(question.options) < 2:
                errors.append(
                    f"line {question.line_no}: question '{question.prompt}'"
                    " needs at least 2 options"
                )
            if checked != 1:
                errors.append(
                    f"line {question.line_no}: question '{question.prompt}'"
                    f" has {checked} '- [x]' marks; exactly one is required"
                )
            count = len(question.options)
            option_counts[count] = question.line_no

    if len(option_counts) > 1:
        detail = "; ".join(
            f"{count} options (e.g. question at line {line_no})"
            for count, line_no in sorted(option_counts.items())
        )
        errors.append(
            f"non-uniform option counts: {detail}."
            " Every question must have the same number of options"
            " (the OMR bubble grid is fixed)."
        )

    if errors:
        raise ValidationError("\n".join(errors))

    sections: dict[str, tuple[Question, ...]] = {}
    for key, name in zip(SECTION_KEYS, SECTION_NAMES):
        questions = []
        for question in by_name[name].questions:
            answer = next(i for i, option in enumerate(question.options) if option.checked)
            questions.append(
                Question(
                    prompt=question.prompt,
                    options=tuple(option.text for option in question.options),
                    answer=answer,
                )
            )
        sections[key] = tuple(questions)
    return Exam(title=raw.titles[0][1], sections=sections)


def load_exam(text: str) -> Exam:
    """Parse + validate. The single validation path for lint, generate, and scramble."""
    return validate(parse(text))
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_validator.py -q`
Expected: `11 passed`

- [ ] **Step 5: Commit**

```bash
git add generator/src/mcexam/validator.py generator/tests/test_validator.py
git commit -m "feat: semantic validator (single validation path for all commands)"
```

---

### Task 5: `select.py` — deterministic variant construction

**Files:**
- Create: `generator/src/mcexam/select.py`
- Test: `generator/tests/test_select.py`

- [ ] **Step 1: Write the failing tests**

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_select.py -q`
Expected: `ModuleNotFoundError: No module named 'mcexam.select'`

- [ ] **Step 3: Write `generator/src/mcexam/select.py`**

```python
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_select.py -q`
Expected: `7 passed`

- [ ] **Step 5: Commit**

```bash
git add generator/src/mcexam/select.py generator/tests/test_select.py
git commit -m "feat: deterministic seed-to-variant selection and option scramble"
```

---

### Task 6: `shared/test-vectors.json` + determinism test

**Files:**
- Create: `generator/scripts/make_test_vectors.py`
- Create: `shared/test-vectors.json` (generated)
- Test: `generator/tests/test_vectors.py`

- [ ] **Step 1: Write `generator/scripts/make_test_vectors.py`**

```python
"""Regenerate shared/test-vectors.json from the Python reference implementation.

Run deliberately, from generator/:  ../.venv/bin/python scripts/make_test_vectors.py
Changing the vectors changes the cross-language contract: the Dart side must be
updated to match and the QR payload version must be bumped (v1 -> v2).

All 64-bit values are decimal strings (JSON-number-safe for every parser).
"""

import json
from pathlib import Path

from mcexam.rng import SplitMix64
from mcexam.select import build_variant

RAW_SEEDS = [0, 1, 42, 123456789, 2**64 - 1]

VARIANT_CASES = [
    {"seed": 0, "sections": {"easy": 5, "medium": 4, "hard": 3},
     "counts": {"easy": 2, "medium": 2, "hard": 1}, "m": 4},
    {"seed": 1, "sections": {"easy": 5, "medium": 4, "hard": 3},
     "counts": {"easy": 5, "medium": 4, "hard": 3}, "m": 4},
    {"seed": 424242, "sections": {"easy": 30, "medium": 25, "hard": 15},
     "counts": {"easy": 10, "medium": 8, "hard": 2}, "m": 5},
    {"seed": 2**64 - 1, "sections": {"easy": 10, "medium": 10, "hard": 10},
     "counts": {"easy": 3, "medium": 3, "hard": 3}, "m": 6},
    {"seed": 987654321987654321, "sections": {"easy": 2, "medium": 2, "hard": 2},
     "counts": {"easy": 0, "medium": 1, "hard": 2}, "m": 2},
]


def main() -> None:
    vectors = {
        "comment": "Cross-language determinism fixture. Generated by"
        " generator/scripts/make_test_vectors.py; do not edit by hand."
        " 64-bit values are decimal strings.",
        "splitmix64": [],
        "variants": [],
    }
    for seed in RAW_SEEDS:
        rng = SplitMix64(seed)
        vectors["splitmix64"].append(
            {"seed": str(seed), "first5": [str(rng.next_uint64()) for _ in range(5)]}
        )
    for case in VARIANT_CASES:
        plan = build_variant(case["seed"], case["sections"], case["counts"], case["m"])
        vectors["variants"].append(
            {
                "seed": str(case["seed"]),
                "sections": case["sections"],
                "counts": case["counts"],
                "options_per_question": case["m"],
                "expected": {
                    "selections": {k: list(v) for k, v in plan.selections.items()},
                    "option_perms": [list(sq.option_perm) for sq in plan.sheet],
                },
            }
        )
    out = Path(__file__).resolve().parents[2] / "shared" / "test-vectors.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(vectors, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Generate the fixture**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/python scripts/make_test_vectors.py`
Expected: `wrote /home/traian/multiple_choice_exam/shared/test-vectors.json`

Sanity check: the `first5` for seed `"0"` must start with `"16294208416658607535"` (== 0xE220A8397B1DCDAF, the published reference value already asserted in test_rng.py).

- [ ] **Step 3: Write the failing test `generator/tests/test_vectors.py`**

```python
"""Replays shared/test-vectors.json — the cross-language determinism fixture.
The Dart suite replays the same file; if either side drifts, its suite fails."""

import json
from pathlib import Path

from mcexam.rng import SplitMix64
from mcexam.select import build_variant

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
```

- [ ] **Step 4: Run the test**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_vectors.py -q`
Expected: `2 passed`

- [ ] **Step 5: Commit**

```bash
git add generator/scripts/make_test_vectors.py shared/test-vectors.json generator/tests/test_vectors.py
git commit -m "feat: cross-language determinism fixture and replay test"
```

---

### Task 7: `keyfile.py`

**Files:**
- Create: `generator/src/mcexam/keyfile.py`
- Test: `generator/tests/test_keyfile.py`

- [ ] **Step 1: Write the failing tests**

```python
import json

from samples import SAMPLE_MD

from mcexam.keyfile import build_key, source_fingerprint, write_key
from mcexam.validator import load_exam


def test_fingerprint_is_8_hex_chars_and_stable() -> None:
    fp = source_fingerprint(SAMPLE_MD)
    assert len(fp) == 8
    int(fp, 16)  # raises if not hex
    assert fp == source_fingerprint(SAMPLE_MD)
    assert fp != source_fingerprint(SAMPLE_MD + "x")


def test_fingerprint_normalizes_crlf() -> None:
    assert source_fingerprint("a\r\nb") == source_fingerprint("a\nb")


def test_build_key_schema() -> None:
    exam = load_exam(SAMPLE_MD)
    key = build_key(exam, "ab12cd34")
    assert key == {
        "version": 1,
        "exam_title": "Sample Exam",
        "source_fingerprint": "ab12cd34",
        "options_per_question": 4,
        "sections": {"easy": 3, "medium": 3, "hard": 2},
        "answer_key": [1, 2, 2, 1, 0, 2, 1, 1],
    }


def test_write_key_round_trips(tmp_path) -> None:
    exam = load_exam(SAMPLE_MD)
    path = tmp_path / "answer-key.json"
    write_key(path, exam, "ab12cd34")
    assert json.loads(path.read_text()) == build_key(exam, "ab12cd34")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_keyfile.py -q`
Expected: `ModuleNotFoundError: No module named 'mcexam.keyfile'`

- [ ] **Step 3: Write `generator/src/mcexam/keyfile.py`**

```python
"""answer-key.json writer. Schema is mirrored by grader/lib/keyfile.dart and
documented in README 'Data formats' — change all three together."""

import hashlib
import json
from pathlib import Path

from .model import Exam

KEY_VERSION = 1


def source_fingerprint(text: str) -> str:
    """First 8 hex chars of sha256 over the newline-normalized source text."""
    normalized = text.replace("\r\n", "\n")
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:8]


def build_key(exam: Exam, fingerprint: str) -> dict:
    return {
        "version": KEY_VERSION,
        "exam_title": exam.title,
        "source_fingerprint": fingerprint,
        "options_per_question": exam.options_per_question,
        "sections": exam.section_sizes(),
        "answer_key": exam.answer_key(),
    }


def write_key(path: Path, exam: Exam, fingerprint: str) -> None:
    payload = json.dumps(build_key(exam, fingerprint), ensure_ascii=False, indent=2)
    path.write_text(payload + "\n", encoding="utf-8")
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_keyfile.py -q`
Expected: `4 passed`

- [ ] **Step 5: Commit**

```bash
git add generator/src/mcexam/keyfile.py generator/tests/test_keyfile.py
git commit -m "feat: answer-key.json writer with source fingerprint"
```

---

### Task 8: `qr.py` — payload codec + QR PNG

**Files:**
- Create: `generator/src/mcexam/qr.py`
- Test: `generator/tests/test_qr.py`

- [ ] **Step 1: Write the failing tests**

```python
import pytest

from mcexam.qr import QrPayload, decode_payload, encode_payload, qr_png

PAYLOAD = QrPayload(
    variant_id=3,
    seed=18446744073709551615,  # 2**64 - 1: must survive the round trip
    n_easy=10,
    n_medium=8,
    n_hard=2,
    source_fingerprint="ab12cd34",
)


def test_encode_format_is_pipe_separated_v1() -> None:
    assert encode_payload(PAYLOAD) == "v1|3|18446744073709551615|10|8|2|ab12cd34"


def test_round_trip() -> None:
    assert decode_payload(encode_payload(PAYLOAD)) == PAYLOAD


def test_decode_rejects_wrong_field_count() -> None:
    with pytest.raises(ValueError, match="expected 7 fields"):
        decode_payload("v1|1|2|3")


def test_decode_rejects_unknown_version() -> None:
    with pytest.raises(ValueError, match="version"):
        decode_payload("v9|3|5|10|8|2|ab12cd34")


def test_qr_png_produces_png_bytes() -> None:
    data = qr_png(encode_payload(PAYLOAD))
    assert data.startswith(b"\x89PNG\r\n\x1a\n")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_qr.py -q`
Expected: `ModuleNotFoundError: No module named 'mcexam.qr'`

- [ ] **Step 3: Write `generator/src/mcexam/qr.py`**

```python
"""QR payload codec (format mirrored by grader/lib/qr_scan.dart) and QR rendering.

Payload format (README 'QR payload') — bump QR_VERSION on ANY field change:
    v1|<variant_id>|<seed>|<n_easy>|<n_medium>|<n_hard>|<source_fp>
"""

import io
from dataclasses import dataclass

import segno

QR_VERSION = "v1"


@dataclass(frozen=True)
class QrPayload:
    variant_id: int
    seed: int
    n_easy: int
    n_medium: int
    n_hard: int
    source_fingerprint: str


def encode_payload(payload: QrPayload) -> str:
    return "|".join(
        [
            QR_VERSION,
            str(payload.variant_id),
            str(payload.seed),
            str(payload.n_easy),
            str(payload.n_medium),
            str(payload.n_hard),
            payload.source_fingerprint,
        ]
    )


def decode_payload(text: str) -> QrPayload:
    parts = text.split("|")
    if len(parts) != 7:
        raise ValueError(f"malformed QR payload: expected 7 fields, got {len(parts)}")
    if parts[0] != QR_VERSION:
        raise ValueError(
            f"unsupported QR payload version {parts[0]!r} (this build reads {QR_VERSION!r})"
        )
    return QrPayload(
        variant_id=int(parts[1]),
        seed=int(parts[2]),
        n_easy=int(parts[3]),
        n_medium=int(parts[4]),
        n_hard=int(parts[5]),
        source_fingerprint=parts[6],
    )


def qr_png(payload: str, scale: int = 8) -> bytes:
    """Render the payload as a PNG (error level M, 2-module quiet zone)."""
    buffer = io.BytesIO()
    segno.make(payload, error="m", micro=False).save(buffer, kind="png", scale=scale, border=2)
    return buffer.getvalue()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_qr.py -q`
Expected: `5 passed`

- [ ] **Step 5: Commit**

```bash
git add generator/src/mcexam/qr.py generator/tests/test_qr.py
git commit -m "feat: QR payload codec and PNG rendering"
```

---

### Task 9: `scramble.py` — shuffled Markdown output

**Files:**
- Create: `generator/src/mcexam/scramble.py`
- Test: `generator/tests/test_scramble.py`

- [ ] **Step 1: Write the failing tests**

```python
from samples import SAMPLE_MD

from mcexam.scramble import scramble_exam, to_markdown
from mcexam.validator import load_exam


def test_scramble_preserves_question_multiset_per_section() -> None:
    exam = load_exam(SAMPLE_MD)
    shuffled = scramble_exam(exam, seed=99)
    for key in ("easy", "medium", "hard"):
        assert sorted(q.prompt for q in shuffled.sections[key]) == sorted(
            q.prompt for q in exam.sections[key]
        )
        assert len(shuffled.sections[key]) == len(exam.sections[key])


def test_marker_travels_with_correct_option() -> None:
    exam = load_exam(SAMPLE_MD)
    shuffled = scramble_exam(exam, seed=99)
    originals = {q.prompt: q for key in exam.sections for q in exam.sections[key]}
    for key in shuffled.sections:
        for question in shuffled.sections[key]:
            original = originals[question.prompt]
            assert sorted(question.options) == sorted(original.options)
            assert question.options[question.answer] == original.options[original.answer]


def test_scramble_is_deterministic() -> None:
    exam = load_exam(SAMPLE_MD)
    assert scramble_exam(exam, seed=5) == scramble_exam(exam, seed=5)
    assert scramble_exam(exam, seed=5) != scramble_exam(exam, seed=6)


def test_markdown_round_trip() -> None:
    exam = load_exam(SAMPLE_MD)
    shuffled = scramble_exam(exam, seed=123)
    assert load_exam(to_markdown(shuffled)) == shuffled


def test_to_markdown_of_unscrambled_exam_is_canonical_sample() -> None:
    exam = load_exam(SAMPLE_MD)
    assert load_exam(to_markdown(exam)) == exam
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_scramble.py -q`
Expected: `ModuleNotFoundError: No module named 'mcexam.scramble'`

- [ ] **Step 3: Write `generator/src/mcexam/scramble.py`**

```python
"""Scramble a question bank and serialize it back to Markdown.

The '- [x]' marker travels with its option, so the output is a valid,
self-documenting exam file. No answer key is ever written here (that is a
generate-only artifact).
"""

from .model import SECTION_KEYS, SECTION_NAMES, Exam, Question
from .select import build_variant


def scramble_exam(exam: Exam, seed: int) -> Exam:
    """Full shuffle = a 'variant' that selects every question."""
    sizes = exam.section_sizes()
    plan = build_variant(seed, sizes, sizes, exam.options_per_question)
    sections: dict[str, list[Question]] = {key: [] for key in SECTION_KEYS}
    for sheet_question in plan.sheet:
        original = exam.sections[sheet_question.section][sheet_question.index_in_section]
        options = tuple(original.options[orig] for orig in sheet_question.option_perm)
        answer = sheet_question.option_perm.index(original.answer)
        sections[sheet_question.section].append(
            Question(prompt=original.prompt, options=options, answer=answer)
        )
    return Exam(
        title=exam.title,
        sections={key: tuple(questions) for key, questions in sections.items()},
    )


def to_markdown(exam: Exam) -> str:
    lines = [f"# {exam.title}"]
    for key, name in zip(SECTION_KEYS, SECTION_NAMES):
        lines += ["", f"## {name}"]
        for question in exam.sections[key]:
            lines += ["", f"### {question.prompt}"]
            for index, option in enumerate(question.options):
                mark = "x" if index == question.answer else " "
                lines.append(f"- [{mark}] {option}")
    return "\n".join(lines) + "\n"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_scramble.py -q`
Expected: `5 passed`

- [ ] **Step 5: Commit**

```bash
git add generator/src/mcexam/scramble.py generator/tests/test_scramble.py
git commit -m "feat: scramble - shuffled self-documenting markdown output"
```

---

### Task 10: `render.py` — answer sheet geometry + PDF drawing

**Files:**
- Create: `generator/src/mcexam/render.py`
- Test: `generator/tests/test_render.py`

- [ ] **Step 1: Write the failing tests**

```python
from samples import SAMPLE_MD

from mcexam.qr import qr_png
from mcexam.render import (
    GRID_LEFT,
    MARGIN,
    PAGE_H,
    PAGE_W,
    ROWS_PER_BLOCK,
    bubble_center,
    max_rows,
    registration_mark_positions,
)
from mcexam.select import build_variant
from mcexam.validator import load_exam


def test_bubble_centers_increase_with_column() -> None:
    xs = [bubble_center(0, col, 4)[0] for col in range(4)]
    assert xs == sorted(xs)
    assert len(set(xs)) == 4


def test_rows_descend_within_block_and_wrap_to_next_block() -> None:
    x0, y0 = bubble_center(0, 0, 4)
    x1, y1 = bubble_center(1, 0, 4)
    assert x1 == x0 and y1 < y0
    x_wrap, y_wrap = bubble_center(ROWS_PER_BLOCK, 0, 4)
    assert x_wrap > x0 and y_wrap == y0


def test_capacity_for_four_options() -> None:
    assert max_rows(4) >= 50


def test_all_bubbles_inside_page() -> None:
    m = 4
    for row in range(max_rows(m)):
        for col in range(m):
            x, y = bubble_center(row, col, m)
            assert GRID_LEFT <= x <= PAGE_W - MARGIN
            assert MARGIN <= y <= PAGE_H


def test_four_registration_marks_at_corners() -> None:
    positions = registration_mark_positions()
    assert len(positions) == 4
    assert len({(round(x), round(y)) for x, y in positions}) == 4


def test_render_writes_pdf(tmp_path) -> None:
    from mcexam.render import render_variant

    exam = load_exam(SAMPLE_MD)
    plan = build_variant(1, exam.section_sizes(), {"easy": 2, "medium": 2, "hard": 1}, 4)
    out = tmp_path / "variant-001.pdf"
    pages = render_variant(out, exam, plan, qr_png("v1|1|1|2|2|1|deadbeef"), 1)
    data = out.read_bytes()
    assert data.startswith(b"%PDF")
    assert pages >= 2  # answer sheet + at least one question page
    assert len(data) > 1000


def test_render_is_byte_reproducible(tmp_path) -> None:
    from mcexam.render import render_variant

    exam = load_exam(SAMPLE_MD)
    plan = build_variant(1, exam.section_sizes(), {"easy": 2, "medium": 2, "hard": 1}, 4)
    a, b = tmp_path / "a.pdf", tmp_path / "b.pdf"
    png = qr_png("v1|1|1|2|2|1|deadbeef")
    render_variant(a, exam, plan, png, 1)
    render_variant(b, exam, plan, png, 1)
    assert a.read_bytes() == b.read_bytes()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_render.py -q`
Expected: `ModuleNotFoundError: No module named 'mcexam.render'`

- [ ] **Step 3: Write `generator/src/mcexam/render.py`**

```python
"""PDF rendering: fixed-geometry answer sheet + flowing question pages.

The answer-sheet geometry (registration marks, bubble centers, row blocks) is
the contract the grader's OMR detection relies on. Change it only together
with the grader and treat the constants below as frozen once sheets are in
the wild.
"""

import io
from pathlib import Path

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader, simpleSplit
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen.canvas import Canvas

from .model import SECTION_KEYS, SECTION_NAMES, Exam
from .select import VariantPlan

PAGE_W, PAGE_H = A4
MARGIN = 15 * mm

# Registration marks: filled squares at the four page corners.
REG_INSET = 8 * mm
REG_SIZE = 6 * mm

# Bubble grid: rows run top-down in vertical blocks of ROWS_PER_BLOCK,
# blocks stack left-to-right.
GRID_TOP = PAGE_H - 70 * mm
GRID_LEFT = MARGIN + 10 * mm
ROW_HEIGHT = 7 * mm
BUBBLE_RADIUS = 2 * mm
BUBBLE_PITCH = 8 * mm
ROWS_PER_BLOCK = 25
BLOCK_LABEL_WIDTH = 10 * mm
BLOCK_GAP = 12 * mm

OPTION_LETTERS = "ABCDEFGHIJ"

_FONT_PATHS = (
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans.ttf",
)


def block_width(options_per_question: int) -> float:
    return BLOCK_LABEL_WIDTH + options_per_question * BUBBLE_PITCH + BLOCK_GAP


def max_rows(options_per_question: int) -> int:
    usable = PAGE_W - MARGIN - GRID_LEFT
    return int(usable // block_width(options_per_question)) * ROWS_PER_BLOCK


def bubble_center(row: int, col: int, options_per_question: int) -> tuple[float, float]:
    block, row_in_block = divmod(row, ROWS_PER_BLOCK)
    x = (
        GRID_LEFT
        + block * block_width(options_per_question)
        + BLOCK_LABEL_WIDTH
        + (col + 0.5) * BUBBLE_PITCH
    )
    y = GRID_TOP - row_in_block * ROW_HEIGHT
    return x, y


def registration_mark_positions() -> list[tuple[float, float]]:
    """Lower-left corners of the four corner squares."""
    return [
        (REG_INSET, PAGE_H - REG_INSET - REG_SIZE),
        (PAGE_W - REG_INSET - REG_SIZE, PAGE_H - REG_INSET - REG_SIZE),
        (REG_INSET, REG_INSET),
        (PAGE_W - REG_INSET - REG_SIZE, REG_INSET),
    ]


def _body_font() -> str:
    """DejaVu Sans if available (full Unicode for math symbols), else Helvetica."""
    if "ExamBody" in pdfmetrics.getRegisteredFontNames():
        return "ExamBody"
    for path in _FONT_PATHS:
        if Path(path).exists():
            pdfmetrics.registerFont(TTFont("ExamBody", path))
            return "ExamBody"
    return "Helvetica"


def render_variant(
    path: Path, exam: Exam, plan: VariantPlan, qr_png_bytes: bytes, variant_id: int
) -> int:
    """Write the variant PDF; returns the page count."""
    rows = len(plan.sheet)
    m = exam.options_per_question
    if rows > max_rows(m):
        raise ValueError(
            f"{rows} questions exceed the single-page answer sheet capacity of"
            f" {max_rows(m)} rows for {m} options per question"
        )
    font = _body_font()
    canvas = Canvas(str(path), pagesize=A4, invariant=1, pageCompression=0)
    _draw_answer_sheet(canvas, exam.title, variant_id, rows, m, qr_png_bytes, font)
    canvas.showPage()
    _draw_questions(canvas, exam, plan, variant_id, font)
    pages = canvas.getPageNumber()
    canvas.save()
    return pages


def _draw_answer_sheet(
    canvas: Canvas, title: str, variant_id: int, rows: int, m: int, qr_png_bytes: bytes, font: str
) -> None:
    for x, y in registration_mark_positions():
        canvas.rect(x, y, REG_SIZE, REG_SIZE, stroke=0, fill=1)
    qr_size = 28 * mm
    canvas.drawImage(
        ImageReader(io.BytesIO(qr_png_bytes)),
        PAGE_W - MARGIN - qr_size,
        PAGE_H - 22 * mm - qr_size,
        qr_size,
        qr_size,
    )
    canvas.setFont(font, 16)
    canvas.drawString(MARGIN, PAGE_H - 25 * mm, title)
    canvas.setFont(font, 12)
    canvas.drawString(MARGIN, PAGE_H - 33 * mm, f"Variant {variant_id:03d}")
    canvas.drawString(MARGIN, PAGE_H - 45 * mm, "Name: " + "_" * 40)

    canvas.setFont(font, 9)
    blocks = (rows + ROWS_PER_BLOCK - 1) // ROWS_PER_BLOCK
    for block in range(blocks):
        for col in range(m):
            x, _ = bubble_center(block * ROWS_PER_BLOCK, col, m)
            canvas.drawCentredString(x, GRID_TOP + 6 * mm, OPTION_LETTERS[col])
    for row in range(rows):
        x_first, y = bubble_center(row, 0, m)
        canvas.drawRightString(x_first - 0.5 * BUBBLE_PITCH - 2 * mm, y - 3, str(row + 1))
        for col in range(m):
            x, y = bubble_center(row, col, m)
            canvas.circle(x, y, BUBBLE_RADIUS, stroke=1, fill=0)


def _draw_questions(
    canvas: Canvas, exam: Exam, plan: VariantPlan, variant_id: int, font: str
) -> None:
    section_titles = dict(zip(SECTION_KEYS, SECTION_NAMES))
    width = PAGE_W - 2 * MARGIN
    y = PAGE_H - MARGIN

    def ensure_space(needed: float) -> None:
        nonlocal y
        if y - needed < MARGIN:
            canvas.showPage()
            y = PAGE_H - MARGIN

    canvas.setFont(font, 14)
    canvas.drawString(MARGIN, y - 14, f"{exam.title} — Variant {variant_id:03d}")
    y -= 30

    current_section = None
    for number, sheet_question in enumerate(plan.sheet, start=1):
        question = exam.sections[sheet_question.section][sheet_question.index_in_section]
        prompt_lines = simpleSplit(f"{number}. {question.prompt}", font, 11, width)
        option_lines: list[str] = []
        for position, original_index in enumerate(sheet_question.option_perm):
            text = f"{OPTION_LETTERS[position]}) {question.options[original_index]}"
            option_lines.extend(simpleSplit(text, font, 11, width - 8 * mm))
        needed = 14 * len(prompt_lines) + 13 * len(option_lines) + 10
        if sheet_question.section != current_section:
            needed += 26
        ensure_space(needed)
        if sheet_question.section != current_section:
            current_section = sheet_question.section
            canvas.setFont(font, 13)
            canvas.drawString(MARGIN, y - 13, section_titles[current_section])
            y -= 26
        canvas.setFont(font, 11)
        for line in prompt_lines:
            canvas.drawString(MARGIN, y - 11, line)
            y -= 14
        for line in option_lines:
            canvas.drawString(MARGIN + 8 * mm, y - 11, line)
            y -= 13
        y -= 10
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_render.py -q`
Expected: `7 passed`

(If `test_render_is_byte_reproducible` fails on font-subset nondeterminism, keep `invariant=1` and compare everything except the embedded font stream — but reportlab's `invariant` mode exists precisely for byte-regression tests, so expect it to pass.)

- [ ] **Step 5: Commit**

```bash
git add generator/src/mcexam/render.py generator/tests/test_render.py
git commit -m "feat: PDF renderer - OMR answer sheet geometry + question pages"
```

---

### Task 11: `cli.py` + `examples/sample-exam.md` + round-trip test

**Files:**
- Create: `generator/src/mcexam/cli.py`
- Create: `examples/sample-exam.md`
- Test: `generator/tests/test_cli.py`
- Test: `generator/tests/test_round_trip.py`

- [ ] **Step 1: Write `examples/sample-exam.md`** (valid bank: easy 6 / medium 5 / hard 4, M=4)

```markdown
# Sample Exam — Demo Course

## Easy

### What is 2 + 2?
- [ ] 3
- [x] 4
- [ ] 5
- [ ] 6

### What color is the sky on a clear day?
- [ ] Green
- [ ] Red
- [x] Blue
- [ ] Yellow

### How many days are in a week?
- [ ] 5
- [ ] 6
- [x] 7
- [ ] 8

### Which animal barks?
- [ ] Cat
- [x] Dog
- [ ] Fish
- [ ] Bird

### What is 10 − 4?
- [ ] 5
- [x] 6
- [ ] 7
- [ ] 4

### How many sides does a triangle have?
- [ ] 2
- [x] 3
- [ ] 4
- [ ] 5

## Medium

### What is 12 × 12?
- [ ] 124
- [x] 144
- [ ] 154
- [ ] 122

### Which planet is closest to the Sun?
- [x] Mercury
- [ ] Venus
- [ ] Mars
- [ ] Earth

### What is the square root of 81?
- [ ] 7
- [ ] 8
- [x] 9
- [ ] 11

### In which year did World War II end?
- [ ] 1943
- [ ] 1944
- [x] 1945
- [ ] 1946

### What is 3³?
- [ ] 9
- [ ] 18
- [x] 27
- [ ] 81

## Hard

### What is the derivative of sin(x)?
- [ ] -sin(x)
- [x] cos(x)
- [ ] -cos(x)
- [ ] tan(x)

### Evaluate ∫₀³ 2x dx.
- [ ] 6
- [x] 9
- [ ] 12
- [ ] 3
```

…plus two more Hard questions to reach 4:

```markdown
### What is the limit of (1 + 1/n)ⁿ as n → ∞?
- [ ] 1
- [ ] 2
- [x] e
- [ ] π

### Which complexity class describes binary search?
- [ ] O(n)
- [x] O(log n)
- [ ] O(n log n)
- [ ] O(1)
```

- [ ] **Step 2: Write the failing CLI tests `generator/tests/test_cli.py`**

```python
import json
from pathlib import Path

from click.testing import CliRunner
from samples import SAMPLE_MD

from mcexam.cli import _split_counts, main

EXAMPLE = Path(__file__).resolve().parents[2] / "examples" / "sample-exam.md"


def write_sample(tmp_path: Path) -> Path:
    path = tmp_path / "exam.md"
    path.write_text(SAMPLE_MD, encoding="utf-8")
    return path


def test_split_counts_default_50_30_20() -> None:
    assert _split_counts(20) == {"easy": 10, "medium": 6, "hard": 4}
    assert sum(_split_counts(7).values()) == 7


def test_lint_ok(tmp_path) -> None:
    result = CliRunner().invoke(main, ["lint", "--input", str(write_sample(tmp_path))])
    assert result.exit_code == 0, result.output
    assert "OK" in result.output and "Sample Exam" in result.output


def test_lint_rejects_invalid(tmp_path) -> None:
    path = tmp_path / "bad.md"
    path.write_text(SAMPLE_MD.replace("- [x] 4", "- [ ] 4"), encoding="utf-8")
    result = CliRunner().invoke(main, ["lint", "--input", str(path)])
    assert result.exit_code != 0
    assert "- [x]" in result.output


def test_lint_example_file() -> None:
    result = CliRunner().invoke(main, ["lint", "--input", str(EXAMPLE)])
    assert result.exit_code == 0, result.output


def test_generate_writes_pdfs_and_key(tmp_path) -> None:
    out = tmp_path / "build"
    result = CliRunner().invoke(
        main,
        ["generate", "--input", str(write_sample(tmp_path)), "--variants", "3",
         "--easy", "2", "--medium", "2", "--hard", "1",
         "--base-seed", "12345", "--out", str(out)],
    )
    assert result.exit_code == 0, result.output
    assert sorted(p.name for p in out.glob("*.pdf")) == [
        "variant-001.pdf", "variant-002.pdf", "variant-003.pdf",
    ]
    key = json.loads((out / "answer-key.json").read_text())
    assert key["version"] == 1
    assert key["sections"] == {"easy": 3, "medium": 3, "hard": 2}


def test_generate_reproducible_with_base_seed(tmp_path) -> None:
    exam = write_sample(tmp_path)
    outs = []
    for name in ("one", "two"):
        out = tmp_path / name
        result = CliRunner().invoke(
            main,
            ["generate", "--input", str(exam), "--variants", "2", "--questions", "5",
             "--base-seed", "777", "--out", str(out)],
        )
        assert result.exit_code == 0, result.output
        outs.append(out)
    for name in ("variant-001.pdf", "variant-002.pdf", "answer-key.json"):
        assert (outs[0] / name).read_bytes() == (outs[1] / name).read_bytes()


def test_generate_questions_conflicting_with_explicit_counts(tmp_path) -> None:
    result = CliRunner().invoke(
        main,
        ["generate", "--input", str(write_sample(tmp_path)), "--questions", "9",
         "--easy", "2", "--medium", "2", "--hard", "1"],
    )
    assert result.exit_code != 0


def test_generate_count_exceeding_section(tmp_path) -> None:
    result = CliRunner().invoke(
        main,
        ["generate", "--input", str(write_sample(tmp_path)),
         "--easy", "9", "--medium", "1", "--hard", "1"],
    )
    assert result.exit_code != 0
    assert "easy" in result.output


def test_scramble_writes_only_markdown(tmp_path) -> None:
    out = tmp_path / "shuffled.md"
    result = CliRunner().invoke(
        main,
        ["scramble", "--input", str(write_sample(tmp_path)),
         "--out", str(out), "--seed", "999"],
    )
    assert result.exit_code == 0, result.output
    assert out.exists()
    # only the markdown file is produced - never a key
    produced = {p.name for p in tmp_path.iterdir()} - {"exam.md"}
    assert produced == {"shuffled.md"}
    lint = CliRunner().invoke(main, ["lint", "--input", str(out)])
    assert lint.exit_code == 0, lint.output


def test_scramble_deterministic_with_seed(tmp_path) -> None:
    exam = write_sample(tmp_path)
    texts = []
    for name in ("a.md", "b.md"):
        out = tmp_path / name
        CliRunner().invoke(
            main, ["scramble", "--input", str(exam), "--out", str(out), "--seed", "31"]
        )
        texts.append(out.read_text())
    assert texts[0] == texts[1]
```

- [ ] **Step 3: Write the failing round-trip test `generator/tests/test_round_trip.py`**

```python
"""Integration backstop: generate a variant plan from a known seed, synthesize a
sheet of known marks, grade it with the documented mapping, assert the score."""

from samples import SAMPLE_MD

from mcexam.keyfile import build_key
from mcexam.select import build_variant
from mcexam.validator import load_exam


def grade(plan, answer_key: list[int], marks: list[int]) -> list[bool]:
    """A mark at sheet position p of row r is correct iff
    plan.sheet[r].option_perm[p] == answer_key[plan.sheet[r].global_index]."""
    return [
        sq.option_perm[marks[row]] == answer_key[sq.global_index]
        for row, sq in enumerate(plan.sheet)
    ]


def test_round_trip_known_marks() -> None:
    exam = load_exam(SAMPLE_MD)
    plan = build_variant(
        424242, exam.section_sizes(), {"easy": 2, "medium": 2, "hard": 1}, 4
    )
    answer_key = build_key(exam, "00000000")["answer_key"]

    # Student answers correctly on even sheet rows, deliberately wrong on odd rows.
    marks = []
    for row, sq in enumerate(plan.sheet):
        correct_position = sq.option_perm.index(answer_key[sq.global_index])
        marks.append(correct_position if row % 2 == 0 else (correct_position + 1) % 4)

    results = grade(plan, answer_key, marks)
    assert results == [True, False, True, False, True]
    assert sum(results) == 3


def test_round_trip_all_correct_any_seed() -> None:
    exam = load_exam(SAMPLE_MD)
    for seed in (0, 1, 2**64 - 1, 555):
        plan = build_variant(
            seed, exam.section_sizes(), {"easy": 3, "medium": 3, "hard": 2}, 4
        )
        answer_key = build_key(exam, "00000000")["answer_key"]
        marks = [
            sq.option_perm.index(answer_key[sq.global_index]) for sq in plan.sheet
        ]
        assert all(grade(plan, answer_key, marks))
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest tests/test_cli.py tests/test_round_trip.py -q`
Expected: `ModuleNotFoundError: No module named 'mcexam.cli'` (round-trip tests pass already — they use existing modules — that's fine.)

- [ ] **Step 5: Write `generator/src/mcexam/cli.py`**

```python
"""mcexam command-line interface: lint, generate, scramble."""

import secrets
from pathlib import Path

import click

from .keyfile import source_fingerprint, write_key
from .model import SECTION_KEYS, Exam
from .parser import ParseError
from .qr import QrPayload, encode_payload, qr_png
from .render import render_variant
from .scramble import scramble_exam, to_markdown
from .select import build_variant, variant_seeds
from .validator import ValidationError, load_exam


def _load(input_path: Path) -> tuple[str, Exam]:
    text = input_path.read_text(encoding="utf-8")
    try:
        return text, load_exam(text)
    except (ParseError, ValidationError) as exc:
        raise click.ClickException(f"{input_path}:\n{exc}") from exc


def _split_counts(questions: int) -> dict[str, int]:
    """Default 50/30/20 split; hard takes the rounding remainder."""
    easy = round(questions * 0.5)
    medium = round(questions * 0.3)
    return {"easy": easy, "medium": medium, "hard": questions - easy - medium}


def _resolve_counts(
    easy: int | None, medium: int | None, hard: int | None, questions: int | None
) -> dict[str, int]:
    explicit = (easy, medium, hard)
    if any(value is not None for value in explicit):
        if not all(value is not None for value in explicit):
            raise click.UsageError("--easy, --medium, and --hard must be given together")
        counts = {"easy": easy, "medium": medium, "hard": hard}
        total = sum(counts.values())
        if total == 0:
            raise click.UsageError("at least one question must be requested")
        if questions is not None and questions != total:
            raise click.UsageError(
                f"--questions {questions} does not match --easy+--medium+--hard = {total}"
            )
        return counts
    if questions is None:
        raise click.UsageError("give --questions, or all of --easy/--medium/--hard")
    return _split_counts(questions)


_INPUT_OPTION = click.option(
    "--input",
    "input_path",
    type=click.Path(exists=True, dir_okay=False, path_type=Path),
    required=True,
    help="Exam Markdown file.",
)


@click.group()
@click.version_option(package_name="mcexam")
def main() -> None:
    """Generate, lint, and scramble randomized multiple-choice exams."""


@main.command()
@_INPUT_OPTION
def lint(input_path: Path) -> None:
    """Validate an exam Markdown file."""
    _, exam = _load(input_path)
    sizes = exam.section_sizes()
    click.echo(
        f"OK: '{exam.title}' — easy {sizes['easy']}, medium {sizes['medium']},"
        f" hard {sizes['hard']}, {exam.options_per_question} options per question"
    )


@main.command()
@_INPUT_OPTION
@click.option("--variants", default=1, show_default=True, type=click.IntRange(min=1))
@click.option("--easy", type=click.IntRange(min=0), default=None)
@click.option("--medium", type=click.IntRange(min=0), default=None)
@click.option("--hard", type=click.IntRange(min=0), default=None)
@click.option("--questions", type=click.IntRange(min=1), default=None)
@click.option("--base-seed", type=int, default=None, help="Fix for a reproducible run.")
@click.option(
    "--out",
    "out_dir",
    type=click.Path(file_okay=False, path_type=Path),
    default=Path("build"),
    show_default=True,
)
def generate(
    input_path: Path,
    variants: int,
    easy: int | None,
    medium: int | None,
    hard: int | None,
    questions: int | None,
    base_seed: int | None,
    out_dir: Path,
) -> None:
    """Generate variant PDFs and answer-key.json."""
    text, exam = _load(input_path)
    counts = _resolve_counts(easy, medium, hard, questions)
    sizes = exam.section_sizes()
    for key in SECTION_KEYS:
        if counts[key] > sizes[key]:
            raise click.ClickException(
                f"requested {counts[key]} {key} questions but '{input_path}'"
                f" has only {sizes[key]}"
            )
    if base_seed is None:
        base_seed = secrets.randbits(64)
    click.echo(f"base seed: {base_seed}")

    out_dir.mkdir(parents=True, exist_ok=True)
    fingerprint = source_fingerprint(text)
    write_key(out_dir / "answer-key.json", exam, fingerprint)
    for variant_id, seed in enumerate(variant_seeds(base_seed, variants), start=1):
        plan = build_variant(seed, sizes, counts, exam.options_per_question)
        payload = encode_payload(
            QrPayload(
                variant_id=variant_id,
                seed=seed,
                n_easy=counts["easy"],
                n_medium=counts["medium"],
                n_hard=counts["hard"],
                source_fingerprint=fingerprint,
            )
        )
        render_variant(
            out_dir / f"variant-{variant_id:03d}.pdf", exam, plan, qr_png(payload), variant_id
        )
    click.echo(f"wrote {variants} variant(s) + answer-key.json to {out_dir}/")


@main.command()
@_INPUT_OPTION
@click.option(
    "--out",
    "out_path",
    type=click.Path(dir_okay=False, path_type=Path),
    required=True,
    help="Output Markdown file.",
)
@click.option("--seed", type=int, default=None, help="Fix for a reproducible shuffle.")
def scramble(input_path: Path, out_path: Path, seed: int | None) -> None:
    """Write a shuffled copy of the question bank (Markdown only, never a key)."""
    _, exam = _load(input_path)
    if seed is None:
        seed = secrets.randbits(64)
    click.echo(f"seed: {seed}")
    out_path.write_text(to_markdown(scramble_exam(exam, seed)), encoding="utf-8")
    click.echo(f"wrote {out_path}")
```

- [ ] **Step 6: Run all tests**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest -q`
Expected: all tests pass (≈60)

- [ ] **Step 7: Smoke-test the real CLI**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/mcexam lint --input ../examples/sample-exam.md && ../.venv/bin/mcexam generate --input ../examples/sample-exam.md --variants 2 --questions 10 --base-seed 1 --out /tmp/mcexam-smoke && ls /tmp/mcexam-smoke`
Expected: lint OK line; `base seed: 1`; `variant-001.pdf variant-002.pdf answer-key.json`

- [ ] **Step 8: Commit**

```bash
git add generator/src/mcexam/cli.py generator/tests/test_cli.py generator/tests/test_round_trip.py examples/sample-exam.md
git commit -m "feat: mcexam CLI (lint, generate, scramble) + sample exam + round-trip test"
```

---

### Task 12: Final verification

- [ ] **Step 1: Lint + format**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/ruff check . && ../.venv/bin/ruff format .`
Expected: no errors; if `ruff format` reformats files, re-run pytest, then `git add -u && git commit -m "style: ruff format"`.

- [ ] **Step 2: Full suite**

Run: `cd /home/traian/multiple_choice_exam/generator && ../.venv/bin/pytest -q`
Expected: all pass.

- [ ] **Step 3: Visual sanity check**

Generate a PDF and read it as an image (or open it) to confirm: registration marks at 4 corners, QR top-right, grid rows = question count, questions readable.

Run: `cd /home/traian/multiple_choice_exam && .venv/bin/mcexam generate --input examples/sample-exam.md --variants 1 --questions 10 --base-seed 7 --out /tmp/mcexam-visual && pdftoppm -png -r 60 /tmp/mcexam-visual/variant-001.pdf /tmp/mcexam-visual/page 2>/dev/null || echo "pdftoppm unavailable - inspect PDF size/pages instead"`

- [ ] **Step 4: Review the full diff vs main**

Run: `git log --oneline main..HEAD && git diff main --stat`

- [ ] **Step 5: Summarize:** what changed, tests run, known limitations (no Dart side yet, answer sheet capacity is single-page, QR decode untested against a real scanner).
