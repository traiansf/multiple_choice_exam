"""Semantic validation: RawExam -> Exam. This module is the executable spec of
the exam Markdown format (mirrored in README 'The exam Markdown format')."""

from .model import MAX_OPTIONS, SECTION_NAMES, Case, Exam, Question, Section, Unit
from .parser import RawCase, RawExam, RawQuestion, parse


class ValidationError(ValueError):
    pass


def _check_question(
    question: RawQuestion, errors: list[str], option_counts: dict[int, int]
) -> None:
    checked = sum(1 for option in question.options if option.checked)
    if len(question.options) < 2:
        errors.append(
            f"line {question.line_no}: question '{question.prompt}' needs at least 2 options"
        )
    if len(question.options) > MAX_OPTIONS:
        errors.append(
            f"line {question.line_no}: question '{question.prompt}'"
            f" has {len(question.options)} options; the OMR bubble grid"
            f" supports at most {MAX_OPTIONS} options per question"
        )
    if checked != 1:
        errors.append(
            f"line {question.line_no}: question '{question.prompt}'"
            f" has {checked} '- [x]' marks; exactly one is required"
        )
    option_counts[len(question.options)] = question.line_no


def _question(question: RawQuestion) -> Question:
    answer = next(i for i, option in enumerate(question.options) if option.checked)
    return Question(
        prompt=question.prompt,
        options=tuple(option.text for option in question.options),
        answer=answer,
    )


def validate(raw: RawExam) -> Exam:
    errors: list[str] = []

    if not raw.titles:
        errors.append("missing exam title: add exactly one '# Title' heading")
    elif len(raw.titles) > 1:
        extra = ", ".join(f"line {line_no}" for line_no, _ in raw.titles[1:])
        errors.append(f"multiple '#' titles (extra at {extra}); keep exactly one")

    # Without cases and with only Easy/Medium/Hard names, the file is a
    # legacy (v1) exam and must have all three. Any other section name, or a
    # case, makes the sections free-form: any names, in source order.
    has_cases = any(section.cases for section in raw.sections)
    free_form = has_cases or any(s.name not in SECTION_NAMES for s in raw.sections)

    seen: set[str] = set()
    for section in raw.sections:
        if not section.name:
            errors.append(f"line {section.line_no}: empty section name")
        elif section.name in seen:
            errors.append(f"line {section.line_no}: duplicate section '## {section.name}'")
        seen.add(section.name)
    if free_form:
        if not raw.sections:
            errors.append("no sections: add at least one '## Section' heading")
    else:
        for name in SECTION_NAMES:
            if name not in seen:
                errors.append(f"missing required section '## {name}'")

    option_counts: dict[int, int] = {}
    for section in raw.sections:
        if not section.units:
            errors.append(f"section '## {section.name}' has no questions")
        for unit in section.units:
            if isinstance(unit, RawCase):
                if not unit.questions:
                    errors.append(
                        f"line {unit.line_no}: case '{unit.title}' has no '####' questions"
                    )
                for question in unit.questions:
                    _check_question(question, errors, option_counts)
            else:
                _check_question(unit, errors, option_counts)

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

    parts = []
    for section in raw.sections:
        units = []
        for unit in section.units:
            if isinstance(unit, RawCase):
                units.append(
                    Unit(
                        questions=tuple(_question(q) for q in unit.questions),
                        case=Case(title=unit.title, stem=unit.stem),
                    )
                )
            else:
                units.append(Unit(questions=(_question(unit),)))
        parts.append(Section(name=section.name, units=tuple(units)))
    return Exam(title=raw.titles[0][1], parts=tuple(parts), preamble=raw.preamble)


def load_exam(text: str) -> Exam:
    """Parse + validate. The single validation path for lint, generate, and scramble."""
    return validate(parse(text))
