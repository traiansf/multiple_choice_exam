"""Scramble a question bank and serialize it back to Markdown.

The '- [x]' marker travels with its option, so the output is a valid,
self-documenting exam file. No answer key is ever written here (that is a
generate-only artifact).
"""

from .model import Exam, Question, Section, Unit
from .select import build_plan


def scramble_exam(exam: Exam, seed: int) -> Exam:
    """Full shuffle = a 'variant' that selects every unit. Cases keep their
    questions in source order; every question's options are shuffled."""
    sizes = exam.unit_sizes()
    plan = build_plan(
        seed, sizes, {key: len(units) for key, units in sizes.items()}, exam.options_per_question
    )
    units_by_key = exam.units_by_key()
    parts = []
    for key, part in zip(exam.section_keys, exam.ordered_parts, strict=True):
        units = []
        for unit_index in plan.selections[key]:
            original = units_by_key[key][unit_index]
            rows = [sq for sq in plan.sheet if sq.section == key and sq.unit_index == unit_index]
            questions = []
            for question, sheet_question in zip(original.questions, rows, strict=True):
                perm = sheet_question.option_perm
                questions.append(
                    Question(
                        prompt=question.prompt,
                        options=tuple(question.options[orig] for orig in perm),
                        answer=perm.index(question.answer),
                    )
                )
            units.append(Unit(questions=tuple(questions), case=original.case))
        parts.append(Section(name=part.name, units=tuple(units)))
    return Exam(title=exam.title, parts=tuple(parts))


def _question_lines(heading: str, question: Question) -> list[str]:
    lines = ["", f"{heading} {question.prompt}"]
    for index, option in enumerate(question.options):
        mark = "x" if index == question.answer else " "
        lines.append(f"- [{mark}] {option}")
    return lines


def to_markdown(exam: Exam) -> str:
    lines = [f"# {exam.title}"]
    for part in exam.parts:
        lines += ["", f"## {part.name}"]
        for unit in part.units:
            if unit.case is None:
                lines += _question_lines("###", unit.questions[0])
                continue
            lines += ["", f"### {unit.case.title}"]
            if unit.case.stem:
                lines += ["", unit.case.stem]
            for question in unit.questions:
                lines += _question_lines("####", question)
    return "\n".join(lines) + "\n"
