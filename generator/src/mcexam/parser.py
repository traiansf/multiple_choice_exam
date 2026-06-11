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
