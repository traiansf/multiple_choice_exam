"""Typed exam model produced by the validator and consumed downstream."""

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
