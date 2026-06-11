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
