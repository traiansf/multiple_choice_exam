"""PDF rendering: fixed-geometry answer sheet + flowing question pages.

The answer-sheet geometry (registration marks, bubble centers, row blocks) is
the contract the grader's OMR detection relies on. Change it only together
with the grader and treat the constants below as frozen once sheets are in
the wild.
"""

import io
import os
from pathlib import Path

from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader, simpleSplit
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.pdfmetrics import registerFontFamily
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen.canvas import Canvas
from reportlab.platypus import Flowable, Frame, Paragraph

from .markup import StemRenderer, inline_markup, spacer
from .model import Exam
from .select import VariantPlan

PAGE_W, PAGE_H = A4
MARGIN = 15 * mm

# Registration marks bound the *capture frame*: the region a sheet photo
# must cover — the full page width, but only the vertical band around the
# bubble grid. Marks are inset REG_INSET from the capture-frame edges,
# mirroring grader/lib/sheet_geometry.dart (captureTopMm/captureHeightMm).
#
# Whole-mm ints keep position arithmetic exact (byte-reproducible PDFs).
# CAPTURE_TOP_MM / CAPTURE_HEIGHT_MM are the grader-facing contract values
# mirrored by grader/lib/sheet_geometry.dart as captureTopMm/captureHeightMm.
# REG_INSET and REG_SIZE are point-valued and used in registration_mark_positions
# and _draw_answer_sheet.
_PAGE_H_MM = 297  # A4 page height in whole mm; kept as int for exact arithmetic
CAPTURE_TOP_MM = 45  # capture-frame top, measured from the page top (mm)
CAPTURE_HEIGHT_MM = 212  # capture-frame height (mm)
_REG_INSET_MM = 8  # inset from capture-frame edges (mm)
_REG_SIZE_MM = 6  # mark square side length (mm)
REG_INSET = _REG_INSET_MM * mm
REG_SIZE = _REG_SIZE_MM * mm

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

# Answer-sheet header geometry (all in PDF points from page top).
NAME_LINE_TOP = 48 * mm  # baseline of the "Name: ___" line
QR_TOP = 16 * mm  # distance from page top to top of answer-sheet QR
# QR spans page-y 16..44 mm, fully above the capture band (top at 45 mm),
# so QR ink stays out of the graded photo and out of the OMR's top-right
# mark-search window (page-y 47.5..64.5 mm).
QR_SIZE = 28 * mm  # side length of the answer-sheet QR image

OPTION_LETTERS = "ABCDEFGHIJ"

# The fixed words printed on every variant, per sheet language (--lang).
# Changing them changes only text, never the geometry the grader reads.
LABELS = {
    "en": {"name": "Name", "variant": "Variant"},
    "ro": {"name": "Nume", "variant": "Varianta"},
}
DEFAULT_LANG = "en"

# Directories searched for the DejaVu family (full Unicode, including
# diacritics and math symbols); MCEXAM_FONT_DIR, if set, comes first.
_FONT_DIRS = (
    "/usr/share/fonts/truetype/dejavu",
    "/usr/share/fonts/TTF",
    "/usr/share/fonts/dejavu",
)
_FONT_FILES = {
    "ExamBody": "DejaVuSans.ttf",
    "ExamBody-Bold": "DejaVuSans-Bold.ttf",
    "ExamBody-Italic": "DejaVuSans-Oblique.ttf",
    "ExamBody-BoldItalic": "DejaVuSans-BoldOblique.ttf",
    "ExamMono": "DejaVuSansMono.ttf",
}


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
    """Lower-left corners of the four marks bounding the answer area."""
    # Integer mm arithmetic first, then a single multiply by mm, to avoid
    # floating-point accumulation from chaining n*mm subtraction operations.
    top_y = (_PAGE_H_MM - CAPTURE_TOP_MM - _REG_INSET_MM - _REG_SIZE_MM) * mm
    bottom_y = (_PAGE_H_MM - CAPTURE_TOP_MM - CAPTURE_HEIGHT_MM + _REG_INSET_MM) * mm
    return [
        (REG_INSET, top_y),
        (PAGE_W - REG_INSET - REG_SIZE, top_y),
        (REG_INSET, bottom_y),
        (PAGE_W - REG_INSET - REG_SIZE, bottom_y),
    ]


def title_lines(title: str, font: str, size: float, width: float) -> list[str]:
    """Wrap the title to at most two lines that each fit in `width`; if it
    needs more, trim the second line until it fits with a trailing ellipsis."""
    lines = simpleSplit(title, font, size, width)
    if len(lines) <= 2:
        return lines
    second = lines[1].rstrip()
    while second and pdfmetrics.stringWidth(second + " …", font, size) > width:
        second = second[:-1].rstrip()
    return [lines[0], second + " …"]


def clamp_line(text: str, font: str, size: float, width: float) -> str:
    """A single line that fits in `width`, ellipsized when trimmed."""
    if pdfmetrics.stringWidth(text, font, size) <= width:
        return text
    trimmed = text
    while trimmed and pdfmetrics.stringWidth(trimmed + " …", font, size) > width:
        trimmed = trimmed[:-1].rstrip()
    return trimmed + " …"


def _font_dirs() -> list[Path]:
    override = os.environ.get("MCEXAM_FONT_DIR")
    return ([Path(override)] if override else []) + [Path(d) for d in _FONT_DIRS]


def _body_font() -> str:
    """DejaVu Sans if available (full Unicode for math symbols), else Helvetica.
    Registers the bold/italic/mono companions used by the question pages."""
    if "ExamBody" in pdfmetrics.getRegisteredFontNames():
        return "ExamBody"
    for directory in _font_dirs():
        if not (directory / _FONT_FILES["ExamBody"]).exists():
            continue
        for name, file in _FONT_FILES.items():
            found = directory / file
            # A missing companion falls back to the regular face.
            source = found if found.exists() else directory / _FONT_FILES["ExamBody"]
            pdfmetrics.registerFont(TTFont(name, str(source)))
        registerFontFamily(
            "ExamBody",
            normal="ExamBody",
            bold="ExamBody-Bold",
            italic="ExamBody-Italic",
            boldItalic="ExamBody-BoldItalic",
        )
        return "ExamBody"
    return "Helvetica"


def _mono_font(body: str) -> str:
    return "ExamMono" if body == "ExamBody" else "Courier"


def render_variant(
    path: Path,
    exam: Exam,
    plan: VariantPlan,
    qr_png_bytes: bytes,
    variant_id: int,
    lang: str = DEFAULT_LANG,
) -> int:
    """Write the variant PDF; returns the page count."""
    if lang not in LABELS:
        raise ValueError(f"unknown sheet language {lang!r}; known: {', '.join(LABELS)}")
    labels = LABELS[lang]
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
    _draw_answer_sheet(canvas, exam.title, variant_id, rows, m, qr_png_bytes, font, labels)
    canvas.showPage()
    _draw_questions(canvas, exam, plan, variant_id, font, qr_png_bytes, labels)
    pages = canvas.getPageNumber()
    canvas.save()
    return pages


def _draw_answer_sheet(
    canvas: Canvas,
    title: str,
    variant_id: int,
    rows: int,
    m: int,
    qr_png_bytes: bytes,
    font: str,
    labels: dict[str, str],
) -> None:
    for x, y in registration_mark_positions():
        canvas.rect(x, y, REG_SIZE, REG_SIZE, stroke=0, fill=1)
    canvas.drawImage(
        ImageReader(io.BytesIO(qr_png_bytes)),
        PAGE_W - MARGIN - QR_SIZE,
        PAGE_H - QR_TOP - QR_SIZE,
        QR_SIZE,
        QR_SIZE,
    )
    # Keep the title clear of the QR region: wrap into the space left of it,
    # at most two lines, ellipsize the rest.
    title_width = PAGE_W - 2 * MARGIN - QR_SIZE - 6 * mm
    canvas.setFont(font, 16)
    y_title = PAGE_H - 25 * mm
    for line in title_lines(title, font, 16, title_width):
        canvas.drawString(MARGIN, y_title, line)
        y_title -= 7 * mm
    canvas.setFont(font, 12)
    canvas.drawString(MARGIN, y_title - 1 * mm, f"{labels['variant']} {variant_id:03d}")
    canvas.drawString(MARGIN, PAGE_H - NAME_LINE_TOP, f"{labels['name']}: " + "_" * 40)

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


QUESTION_PAGE_QR_SIZE = 18 * mm


def _draw_questions(
    canvas: Canvas,
    exam: Exam,
    plan: VariantPlan,
    variant_id: int,
    font: str,
    qr_png_bytes: bytes,
    labels: dict[str, str],
) -> None:
    width = PAGE_W - 2 * MARGIN
    qr_image = ImageReader(io.BytesIO(qr_png_bytes))
    y = PAGE_H - MARGIN

    def page_header() -> None:
        """Issue #9: every question page re-identifies its variant — header
        text plus a small QR top-right — so separated pages stay gradable."""
        nonlocal y
        canvas.drawImage(
            qr_image,
            PAGE_W - MARGIN - QUESTION_PAGE_QR_SIZE,
            PAGE_H - MARGIN - QUESTION_PAGE_QR_SIZE,
            QUESTION_PAGE_QR_SIZE,
            QUESTION_PAGE_QR_SIZE,
        )
        header_width = PAGE_W - 2 * MARGIN - QUESTION_PAGE_QR_SIZE - 4 * mm
        canvas.setFont(font, 14)
        canvas.drawString(
            MARGIN,
            PAGE_H - MARGIN - 14,
            clamp_line(exam.title, font, 14, header_width),
        )
        # The variant number is its own unconditional line: a long title must
        # never swallow the page's human-readable identification.
        canvas.setFont(font, 12)
        canvas.drawString(MARGIN, PAGE_H - MARGIN - 30, f"{labels['variant']} {variant_id:03d}")
        # Content starts below whichever is taller: the QR or the header.
        y = PAGE_H - MARGIN - QUESTION_PAGE_QR_SIZE - 8

    page_header()
    frame = _new_frame(y)
    for group in _question_groups(exam, plan, font):
        height = sum(_height(f, width, canvas) for f in group)
        if height > _available(frame) and not frame._atTop:
            canvas.showPage()
            page_header()
            frame = _new_frame(y)
        pending = list(group)
        while pending:
            flowable = pending[0]
            if frame.add(flowable, canvas):
                pending.pop(0)
                continue
            pieces = frame.split(flowable, canvas)
            if len(pieces) > 1 and frame.add(pieces[0], canvas):
                pending[0:1] = pieces[1:]
            elif frame._atTop:
                raise ValueError("a question or case stem block is taller than a page")
            canvas.showPage()
            page_header()
            frame = _new_frame(y)


def _new_frame(top: float) -> Frame:
    return Frame(
        MARGIN,
        MARGIN,
        PAGE_W - 2 * MARGIN,
        top - MARGIN,
        leftPadding=0,
        rightPadding=0,
        topPadding=0,
        bottomPadding=0,
    )


def _available(frame: Frame) -> float:
    return frame._y - frame._y1p


def _height(flowable: Flowable, width: float, canvas: Canvas) -> float:
    _, height = flowable.wrapOn(canvas, width, PAGE_H)
    return height + flowable.getSpaceBefore() + flowable.getSpaceAfter()


def _question_groups(exam: Exam, plan: VariantPlan, font: str) -> list[list[Flowable]]:
    """Flowables per block that should start on one page: each standalone
    question; for a case, its title and stem together with its first question,
    then each further question."""
    mono = _mono_font(font)
    prompt_style = ParagraphStyle("prompt", fontName=font, fontSize=11, leading=14)
    option_style = ParagraphStyle(
        "option", fontName=font, fontSize=11, leading=13, leftIndent=8 * mm
    )
    case_title = ParagraphStyle("case-title", fontName=font, fontSize=12, leading=15, spaceAfter=4)
    stem_style = ParagraphStyle("stem", fontName=font, fontSize=11, leading=14, spaceAfter=4)
    stems = StemRenderer(stem_style, mono)
    units = exam.units_by_key()

    groups: list[list[Flowable]] = []
    previous_unit: tuple[str, int] | None = None
    for number, sheet_question in enumerate(plan.sheet, start=1):
        unit = units[sheet_question.section][sheet_question.unit_index]
        question = exam.sections[sheet_question.section][sheet_question.index_in_section]
        group: list[Flowable] = []
        current_unit = (sheet_question.section, sheet_question.unit_index)
        if unit.case is not None and current_unit != previous_unit:
            group.append(Paragraph(f"<b>{inline_markup(unit.case.title, mono)}</b>", case_title))
            group += stems.blocks(unit.case.stem)
            group.append(spacer(4))
        previous_unit = current_unit
        group.append(Paragraph(f"{number}. {inline_markup(question.prompt, mono)}", prompt_style))
        for position, original_index in enumerate(sheet_question.option_perm):
            text = inline_markup(question.options[original_index], mono)
            group.append(Paragraph(f"{OPTION_LETTERS[position]}) {text}", option_style))
        group.append(spacer(10))
        groups.append(group)
    return groups
