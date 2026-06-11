from mcexam.qr import qr_png
from mcexam.render import (
    GRID_LEFT,
    MARGIN,
    PAGE_H,
    PAGE_W,
    ROWS_PER_BLOCK,
    bubble_center,
    max_rows,
    registration_mark_positions,
    render_variant,
)
from mcexam.select import build_variant
from mcexam.validator import load_exam
from samples import SAMPLE_MD


def test_bubble_centers_increase_with_column() -> None:
    xs = [bubble_center(0, col, 4)[0] for col in range(4)]
    assert xs == sorted(xs)
    assert len(set(xs)) == 4


def test_rows_descend_within_block_and_wrap_to_next_block() -> None:
    x0, y0 = bubble_center(0, 0, 4)
    x1, y1 = bubble_center(1, 0, 4)
    assert x1 == x0 and y1 < y0
    x_wrap, y_wrap = bubble_center(ROWS_PER_BLOCK, 0, 4)
    assert x_wrap > x0 and y_wrap == y0


def test_capacity_for_four_options() -> None:
    assert max_rows(4) >= 50


def test_all_bubbles_inside_page() -> None:
    m = 4
    for row in range(max_rows(m)):
        for col in range(m):
            x, y = bubble_center(row, col, m)
            assert GRID_LEFT <= x <= PAGE_W - MARGIN
            assert MARGIN <= y <= PAGE_H


def test_four_registration_marks_at_corners() -> None:
    positions = registration_mark_positions()
    assert len(positions) == 4
    assert len({(round(x), round(y)) for x, y in positions}) == 4


def test_render_writes_pdf(tmp_path) -> None:
    exam = load_exam(SAMPLE_MD)
    plan = build_variant(1, exam.section_sizes(), {"easy": 2, "medium": 2, "hard": 1}, 4)
    out = tmp_path / "variant-001.pdf"
    pages = render_variant(out, exam, plan, qr_png("v1|1|1|2|2|1|deadbeef"), 1)
    data = out.read_bytes()
    assert data.startswith(b"%PDF")
    assert pages >= 2  # answer sheet + at least one question page
    assert len(data) > 1000


def test_render_long_title_does_not_reach_qr(tmp_path) -> None:
    long_title = (
        "Introduction to Quantum Mechanics and Computational Physics"
        " for Engineers — Midterm Examination, Summer Session"
    )
    text = SAMPLE_MD.replace("# Sample Exam", f"# {long_title}")
    exam = load_exam(text)
    plan = build_variant(1, exam.section_sizes(), {"easy": 2, "medium": 2, "hard": 1}, 4)
    out = tmp_path / "long-title.pdf"
    render_variant(out, exam, plan, qr_png("v1|1|1|2|2|1|deadbeef"), 1)
    assert out.read_bytes().startswith(b"%PDF")


def test_render_rejects_more_options_than_letters(tmp_path) -> None:
    import pytest

    from mcexam.model import Exam, Question

    question = Question("Q?", tuple(f"opt{i}" for i in range(11)), 0)
    exam = Exam(
        title="T",
        sections={"easy": (question,), "medium": (question,), "hard": (question,)},
    )
    plan = build_variant(1, exam.section_sizes(), {"easy": 1, "medium": 1, "hard": 1}, 11)
    with pytest.raises(ValueError, match="option"):
        render_variant(tmp_path / "x.pdf", exam, plan, qr_png("v1|1|1|1|1|1|deadbeef"), 1)


def test_render_unicode_math_content(tmp_path) -> None:
    text = SAMPLE_MD.replace(
        "### Evaluate the integral of 2x from 0 to 3.",
        "### Evaluate ∫₀³ 2x dx — limit as n → ∞ of (1 + 1/n)ⁿ?",
    )
    exam = load_exam(text)
    plan = build_variant(3, exam.section_sizes(), {"easy": 3, "medium": 3, "hard": 2}, 4)
    out = tmp_path / "unicode.pdf"
    pages = render_variant(out, exam, plan, qr_png("v1|1|3|3|3|2|deadbeef"), 1)
    assert pages >= 2
    assert out.read_bytes().startswith(b"%PDF")


def test_render_is_byte_reproducible(tmp_path) -> None:
    exam = load_exam(SAMPLE_MD)
    plan = build_variant(1, exam.section_sizes(), {"easy": 2, "medium": 2, "hard": 1}, 4)
    a, b = tmp_path / "a.pdf", tmp_path / "b.pdf"
    png = qr_png("v1|1|1|2|2|1|deadbeef")
    render_variant(a, exam, plan, png, 1)
    render_variant(b, exam, plan, png, 1)
    assert a.read_bytes() == b.read_bytes()
