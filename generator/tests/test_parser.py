import pytest

from mcexam.parser import ParseError, parse
from samples import SAMPLE_MD


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


def test_crlf_input_parses_identically_to_lf() -> None:
    crlf = SAMPLE_MD.replace("\n", "\r\n")
    assert parse(crlf) == parse(SAMPLE_MD)


def test_blank_lines_and_trailing_whitespace_ignored() -> None:
    raw = parse("# T  \n\n\n## Easy   \n\n### Q?  \n- [x] a\n- [ ] b   \n")
    assert raw.titles[0][1] == "T"
    assert raw.sections[0].questions[0].options[1].text == "b"
