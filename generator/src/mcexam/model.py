"""Typed exam model produced by the validator and consumed downstream.

An exam is a list of named sections; a section is a list of *units*. A unit is
either a standalone question or a case: a shared stem (Markdown) followed by
the questions that refer to it. Units are what a variant selects, so the
questions of a case always appear together.

Legacy (v1) exams have exactly the sections Easy, Medium, and Hard and no
cases. They keep the v1 key file, QR payload, and canonical section order
[easy, medium, hard] regardless of source order, so their variants are
unchanged.
"""

from dataclasses import dataclass

SECTION_NAMES = ("Easy", "Medium", "Hard")
SECTION_KEYS = ("easy", "medium", "hard")

# The OMR bubble grid labels options A..J; more options per question than this
# cannot be rendered (validator rejects them at lint time).
MAX_OPTIONS = 10


@dataclass(frozen=True)
class Question:
    prompt: str
    options: tuple[str, ...]
    answer: int  # 0-based index into options of the correct one


@dataclass(frozen=True)
class Case:
    title: str
    stem: str  # Markdown shown once above the case's questions


@dataclass(frozen=True)
class Unit:
    questions: tuple[Question, ...]
    case: Case | None = None  # None for a standalone question


@dataclass(frozen=True)
class Section:
    name: str
    units: tuple[Unit, ...]


@dataclass(frozen=True)
class Exam:
    title: str
    parts: tuple[Section, ...]  # in source order
    preamble: str = ""  # Markdown printed before the first question

    @property
    def legacy(self) -> bool:
        """v1 shape: sections exactly Easy/Medium/Hard, every unit a single
        question without a case."""
        return sorted(p.name for p in self.parts) == sorted(SECTION_NAMES) and all(
            unit.case is None for p in self.parts for unit in p.units
        )

    @property
    def ordered_parts(self) -> tuple[Section, ...]:
        """Sections in key/sheet order: canonical for legacy exams, else source order."""
        if self.legacy:
            by_name = {p.name: p for p in self.parts}
            return tuple(by_name[name] for name in SECTION_NAMES)
        return self.parts

    @property
    def section_keys(self) -> tuple[str, ...]:
        """Keys used in the key file, plans, and counts: easy/medium/hard for
        legacy exams, else the section names."""
        if self.legacy:
            return SECTION_KEYS
        return tuple(p.name for p in self.parts)

    @property
    def sections(self) -> dict[str, tuple[Question, ...]]:
        """Each section's questions, flattened in source order, by key."""
        return {
            key: tuple(q for unit in part.units for q in unit.questions)
            for key, part in zip(self.section_keys, self.ordered_parts, strict=True)
        }

    def units_by_key(self) -> dict[str, tuple[Unit, ...]]:
        return {
            key: part.units for key, part in zip(self.section_keys, self.ordered_parts, strict=True)
        }

    def unit_sizes(self) -> dict[str, list[int]]:
        """Questions per unit, per section key, in source order."""
        return {
            key: [len(unit.questions) for unit in units]
            for key, units in self.units_by_key().items()
        }

    @property
    def options_per_question(self) -> int:
        for questions in self.sections.values():
            for question in questions:
                return len(question.options)
        raise ValueError("exam has no questions")

    def section_sizes(self) -> dict[str, int]:
        """Questions per section key."""
        return {key: len(questions) for key, questions in self.sections.items()}

    def answer_key(self) -> list[int]:
        """Correct-option indices in key order: sections in key order, then
        units, then the questions of each unit."""
        return [q.answer for questions in self.sections.values() for q in questions]
