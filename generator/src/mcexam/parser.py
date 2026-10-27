"""Markdown exam parser: text -> raw structure. Semantic rules live in validator.py.

A '###' heading opens either a standalone question (options follow directly)
or a case: stem lines (any Markdown except headings and option items),
then '####' questions with their options.
"""

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
class RawCase:
    line_no: int
    title: str
    stem_lines: list[str] = field(default_factory=list)
    questions: list[RawQuestion] = field(default_factory=list)

    @property
    def stem(self) -> str:
        return "\n".join(self.stem_lines).strip("\n")


@dataclass
class RawSection:
    line_no: int
    name: str
    units: list[RawQuestion | RawCase] = field(default_factory=list)

    @property
    def questions(self) -> list[RawQuestion]:
        """The standalone questions (units that are not cases)."""
        return [unit for unit in self.units if isinstance(unit, RawQuestion)]

    @property
    def cases(self) -> list[RawCase]:
        return [unit for unit in self.units if isinstance(unit, RawCase)]


@dataclass
class RawExam:
    titles: list[tuple[int, str]] = field(default_factory=list)
    sections: list[RawSection] = field(default_factory=list)


_OPTION_RE = re.compile(r"^- \[( |x|X)\] (.*\S.*)$")


def parse(text: str) -> RawExam:
    exam = RawExam()
    section: RawSection | None = None
    # A '###' heading whose kind (question or case) is not known yet: it
    # becomes a case at its first stem line or '####', a question at its
    # first option.
    pending: tuple[int, str] | None = None
    case: RawCase | None = None
    question: RawQuestion | None = None

    def flush_pending() -> None:
        """A '###' with nothing under it: a question without options (the
        validator reports it)."""
        nonlocal pending
        if pending is not None:
            section.units.append(RawQuestion(*pending))
            pending = None

    def open_case(line_no: int) -> RawCase:
        nonlocal pending, case
        assert section is not None and pending is not None
        case = RawCase(pending[0], pending[1])
        section.units.append(case)
        pending = None
        return case

    for line_no, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.rstrip()
        option = _OPTION_RE.match(line)
        in_stem = (pending is not None or case is not None) and question is None
        if not line:
            if case is not None and question is None:
                case.stem_lines.append("")
            continue
        if line.startswith("#### "):
            if pending is None and case is None:
                raise ParseError(line_no, "'####' question outside a '###' case")
            if pending is not None:
                open_case(line_no)
            question = RawQuestion(line_no, line[5:].strip())
            case.questions.append(question)
        elif line.startswith("### "):
            if section is None:
                raise ParseError(line_no, "question heading before any '##' section")
            flush_pending()
            pending, case, question = (line_no, line[4:].strip()), None, None
        elif line.startswith("## "):
            flush_pending()
            section = RawSection(line_no, line[3:].strip())
            pending, case, question = None, None, None
            exam.sections.append(section)
        elif line.startswith("# "):
            flush_pending()
            exam.titles.append((line_no, line[2:].strip()))
            pending, case, question = None, None, None
        elif option:
            if pending is not None:
                question = RawQuestion(*pending)
                section.units.append(question)
                pending = None
            elif question is None:
                if case is not None:
                    raise ParseError(
                        line_no,
                        "option list item in a case stem; a case's options follow"
                        " its '####' questions",
                    )
                raise ParseError(line_no, "option list item outside a '###' question")
            question.options.append(
                RawOption(line_no, option.group(2).strip(), option.group(1) in "xX")
            )
        elif in_stem:
            if line.lstrip().startswith("#"):
                raise ParseError(line_no, "headings are not allowed in a case stem")
            if pending is not None:
                open_case(line_no)
            case.stem_lines.append(line)
        else:
            raise ParseError(
                line_no,
                f"unrecognized content: {line!r}"
                " (expected a heading, '- [ ] option', or blank line;"
                " free text belongs in a case stem, between a '###' case"
                " heading and its first '####' question)",
            )
    flush_pending()
    return exam
