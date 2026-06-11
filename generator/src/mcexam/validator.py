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
            option_counts[len(question.options)] = question.line_no

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
    for key, name in zip(SECTION_KEYS, SECTION_NAMES, strict=True):
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
