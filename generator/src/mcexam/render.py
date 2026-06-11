"""PDF rendering: fixed-geometry answer sheet + flowing question pages.

The answer-sheet geometry (registration marks, bubble centers, row blocks) is
the contract the grader's OMR detection relies on. Change it only together
with the grader and treat the constants below as frozen once sheets are in
the wild.
"""

import io
from pathlib import Path

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader, simpleSplit
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen.canvas import Canvas

from .model import SECTION_KEYS, SECTION_NAMES, Exam
from .select import VariantPlan

PAGE_W, PAGE_H = A4
MARGIN = 15 * mm

# Registration marks: filled squares at the four page corners.
REG_INSET = 8 * mm
REG_SIZE = 6 * mm

# Bubble grid: rows run top-down in vertical blocks of ROWS_PER_BLOCK,
# blocks stack left-to-right.
GRID_TOP = PAGE_H - 70 * mm
GRID_LEFT = MARGIN + 10 * mm
ROW_HEIGHT = 7 * mm
BUBBLE_RADIUS = 2 * mm
BUBBLE_PITCH = 8 * mm
ROWS_PER_BLOCK = 25
BLOCK_LABEL_WIDTH = 10 * mm
BLOCK_GAP = 12 * mm

OPTION_LETTERS = "ABCDEFGHIJ"

_FONT_PATHS = (
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans.ttf",
)


def block_width(options_per_question: int) -> float:
    return BLOCK_LABEL_WIDTH + options_per_question * BUBBLE_PITCH + BLOCK_GAP


def max_rows(options_per_question: int) -> int:
    usable = PAGE_W - MARGIN - GRID_LEFT
    return int(usable // block_width(options_per_question)) * ROWS_PER_BLOCK


def bubble_center(row: int, col: int, options_per_question: int) -> tuple[float, float]:
    block, row_in_block = divmod(row, ROWS_PER_BLOCK)
    x = (
        GRID_LEFT
        + block * block_width(options_per_question)
        + BLOCK_LABEL_WIDTH
        + (col + 0.5) * BUBBLE_PITCH
    )
    y = GRID_TOP - row_in_block * ROW_HEIGHT
    return x, y


def registration_mark_positions() -> list[tuple[float, float]]:
    """Lower-left corners of the four corner squares."""
    return [
        (REG_INSET, PAGE_H - REG_INSET - REG_SIZE),
        (PAGE_W - REG_INSET - REG_SIZE, PAGE_H - REG_INSET - REG_SIZE),
        (REG_INSET, REG_INSET),
        (PAGE_W - REG_INSET - REG_SIZE, REG_INSET),
    ]


def _body_font() -> str:
    """DejaVu Sans if available (full Unicode for math symbols), else Helvetica."""
    if "ExamBody" in pdfmetrics.getRegisteredFontNames():
        return "ExamBody"
    for path in _FONT_PATHS:
        if Path(path).exists():
            pdfmetrics.registerFont(TTFont("ExamBody", path))
            return "ExamBody"
    return "Helvetica"


def render_variant(
    path: Path, exam: Exam, plan: VariantPlan, qr_png_bytes: bytes, variant_id: int
) -> int:
    """Write the variant PDF; returns the page count."""
    rows = len(plan.sheet)
    m = exam.options_per_question
    if m > len(OPTION_LETTERS):
        raise ValueError(
            f"{m} options per question exceed the {len(OPTION_LETTERS)} option"
            " labels the bubble grid supports (A-J)"
        )
    if rows > max_rows(m):
        raise ValueError(
            f"{rows} questions exceed the single-page answer sheet capacity of"
            f" {max_rows(m)} rows for {m} options per question"
        )
    font = _body_font()
    canvas = Canvas(str(path), pagesize=A4, invariant=1, pageCompression=0)
    _draw_answer_sheet(canvas, exam.title, variant_id, rows, m, qr_png_bytes, font)
    canvas.showPage()
    _draw_questions(canvas, exam, plan, variant_id, font)
    pages = canvas.getPageNumber()
    canvas.save()
    return pages


def _draw_answer_sheet(
    canvas: Canvas, title: str, variant_id: int, rows: int, m: int, qr_png_bytes: bytes, font: str
) -> None:
    for x, y in registration_mark_positions():
        canvas.rect(x, y, REG_SIZE, REG_SIZE, stroke=0, fill=1)
    qr_size = 28 * mm
    canvas.drawImage(
        ImageReader(io.BytesIO(qr_png_bytes)),
        PAGE_W - MARGIN - qr_size,
        PAGE_H - 22 * mm - qr_size,
        qr_size,
        qr_size,
    )
    # Keep the title clear of the QR region: wrap into the space left of it,
    # at most two lines, ellipsize the rest.
    title_width = PAGE_W - 2 * MARGIN - qr_size - 6 * mm
    title_lines = simpleSplit(title, font, 16, title_width)
    if len(title_lines) > 2:
        title_lines = [title_lines[0], title_lines[1].rstrip() + " …"]
    canvas.setFont(font, 16)
    y_title = PAGE_H - 25 * mm
    for line in title_lines:
        canvas.drawString(MARGIN, y_title, line)
        y_title -= 7 * mm
    canvas.setFont(font, 12)
    canvas.drawString(MARGIN, y_title - 1 * mm, f"Variant {variant_id:03d}")
    canvas.drawString(MARGIN, PAGE_H - 48 * mm, "Name: " + "_" * 40)

    canvas.setFont(font, 9)
    blocks = (rows + ROWS_PER_BLOCK - 1) // ROWS_PER_BLOCK
    for block in range(blocks):
        for col in range(m):
            x, _ = bubble_center(block * ROWS_PER_BLOCK, col, m)
            canvas.drawCentredString(x, GRID_TOP + 6 * mm, OPTION_LETTERS[col])
    for row in range(rows):
        x_first, y = bubble_center(row, 0, m)
        canvas.drawRightString(x_first - 0.5 * BUBBLE_PITCH - 2 * mm, y - 3, str(row + 1))
        for col in range(m):
            x, y = bubble_center(row, col, m)
            canvas.circle(x, y, BUBBLE_RADIUS, stroke=1, fill=0)


def _draw_questions(
    canvas: Canvas, exam: Exam, plan: VariantPlan, variant_id: int, font: str
) -> None:
    section_titles = dict(zip(SECTION_KEYS, SECTION_NAMES, strict=True))
    width = PAGE_W - 2 * MARGIN
    y = PAGE_H - MARGIN

    def ensure_space(needed: float) -> None:
        nonlocal y
        if y - needed < MARGIN:
            canvas.showPage()
            y = PAGE_H - MARGIN

    canvas.setFont(font, 14)
    canvas.drawString(MARGIN, y - 14, f"{exam.title} — Variant {variant_id:03d}")
    y -= 30

    current_section = None
    for number, sheet_question in enumerate(plan.sheet, start=1):
        question = exam.sections[sheet_question.section][sheet_question.index_in_section]
        prompt_lines = simpleSplit(f"{number}. {question.prompt}", font, 11, width)
        option_lines: list[str] = []
        for position, original_index in enumerate(sheet_question.option_perm):
            text = f"{OPTION_LETTERS[position]}) {question.options[original_index]}"
            option_lines.extend(simpleSplit(text, font, 11, width - 8 * mm))
        needed = 14 * len(prompt_lines) + 13 * len(option_lines) + 10
        if sheet_question.section != current_section:
            needed += 26
        ensure_space(needed)
        if sheet_question.section != current_section:
            current_section = sheet_question.section
            canvas.setFont(font, 13)
            canvas.drawString(MARGIN, y - 13, section_titles[current_section])
            y -= 26
        canvas.setFont(font, 11)
        for line in prompt_lines:
            canvas.drawString(MARGIN, y - 11, line)
            y -= 14
        for line in option_lines:
            canvas.drawString(MARGIN + 8 * mm, y - 11, line)
            y -= 13
        y -= 10
