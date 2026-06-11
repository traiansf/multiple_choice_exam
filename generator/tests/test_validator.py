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
