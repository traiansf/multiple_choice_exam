"""Markdown -> reportlab Platypus flowables for the question pages.

Prompts and options are inline Markdown (bold, italic, code); a case stem is
block Markdown: paragraphs, bullet and numbered lists, pipe tables, code
blocks, block quotes, and thematic breaks. Raw HTML is not interpreted.
"""

import re

from markdown_it import MarkdownIt
from markdown_it.tree import SyntaxTreeNode
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (
    Flowable,
    HRFlowable,
    Indenter,
    ListFlowable,
    ListItem,
    Paragraph,
    Preformatted,
    Spacer,
    Table,
    TableStyle,
)

_MD = MarkdownIt("commonmark", {"html": False}).enable("table")

# markdown-it's inline HTML -> reportlab paragraph markup. Anything else is
# dropped, keeping its text.
_TAGS = {
    "strong": "b",
    "em": "i",
}
_TAG_RE = re.compile(r"<(/?)([a-z0-9]+)[^>]*>")


def plain_markup(text: str) -> str:
    """Text taken literally, as reportlab paragraph markup."""
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


_ALT_RE = re.compile(r'\salt="([^"]*)"')


def inline_markup(text: str, mono_font: str) -> str:
    """One line of inline Markdown as reportlab paragraph markup."""
    rendered = _MD.renderInline(text)

    def tag(match: re.Match) -> str:
        closing, name = match.group(1), match.group(2)
        if name == "img":
            alt = _ALT_RE.search(match.group(0))
            return alt.group(1) if alt else ""
        if name in _TAGS:
            return f"<{closing}{_TAGS[name]}>"
        if name == "code":
            return "</font>" if closing else f'<font face="{mono_font}">'
        if name == "br":
            return "<br/>"
        return ""

    # markdown-it escapes &, <, > and quotes; reportlab understands the same
    # entities except &#39; and &quot; inside text, which we turn back.
    markup = _TAG_RE.sub(tag, rendered)
    return markup.replace("&quot;", '"').replace("&#39;", "'")


class StemRenderer:
    def __init__(self, body: ParagraphStyle, mono_font: str) -> None:
        self.body = body
        self.mono_font = mono_font
        self.cell = ParagraphStyle("cell", parent=body, spaceBefore=0, spaceAfter=0)
        self.code = ParagraphStyle(
            "code",
            parent=body,
            fontName=mono_font,
            fontSize=body.fontSize - 1,
            leading=body.leading - 1,
        )

    def _inline(self, inline: SyntaxTreeNode) -> str:
        """inline: the 'inline' node under a paragraph or table cell."""
        return inline_markup(inline.content, self.mono_font)

    def blocks(self, markdown: str) -> list[Flowable]:
        return self._nodes(SyntaxTreeNode(_MD.parse(markdown)).children)

    def _nodes(self, nodes: list[SyntaxTreeNode]) -> list[Flowable]:
        out: list[Flowable] = []
        for node in nodes:
            out += self._node(node)
        return out

    def _node(self, node: SyntaxTreeNode) -> list[Flowable]:
        if node.type == "paragraph":
            return [Paragraph(self._inline(node.children[0]), self.body)]
        if node.type in ("bullet_list", "ordered_list"):
            items = []
            for item in node.children:
                flowables = self._list_item(item)
                items.append(ListItem(flowables))
            kwargs = {"bulletType": "bullet", "start": "•"}
            if node.type == "ordered_list":
                kwargs = {"bulletType": "1", "start": int(node.attrs.get("start", 1))}
            return [
                ListFlowable(
                    items,
                    leftIndent=6 * mm,
                    bulletFontName=self.body.fontName,
                    bulletFontSize=self.body.fontSize,
                    spaceAfter=self.body.spaceAfter,
                    **kwargs,
                )
            ]
        if node.type == "table":
            return [self._table(node)]
        if node.type in ("fence", "code_block"):
            return [Preformatted(node.content.rstrip("\n"), self.code)]
        if node.type == "blockquote":
            return [Indenter(left=6 * mm), *self._nodes(node.children), Indenter(left=-6 * mm)]
        if node.type == "hr":
            return [HRFlowable(width="100%", thickness=0.5, color=colors.grey, spaceAfter=4)]
        return []

    def _list_item(self, item: SyntaxTreeNode) -> list[Flowable]:
        flowables: list[Flowable] = []
        for child in item.children:
            if child.type == "paragraph":
                style = ParagraphStyle("li", parent=self.body, spaceAfter=1)
                flowables.append(Paragraph(self._inline(child.children[0]), style))
            else:
                flowables += self._node(child)
        return flowables

    def _table(self, node: SyntaxTreeNode) -> Table:
        rows: list[list[Paragraph]] = []
        header_rows = 0
        for section in node.children:  # thead, tbody
            for row in section.children:
                cells = []
                for cell in row.children:
                    markup = self._inline(cell.children[0]) if cell.children else ""
                    if cell.type == "th":
                        markup = f"<b>{markup}</b>"
                    cells.append(Paragraph(markup, self.cell))
                rows.append(cells)
                if section.type == "thead":
                    header_rows += 1
        table = Table(rows, hAlign="LEFT", repeatRows=header_rows, spaceAfter=4)
        table.setStyle(
            TableStyle(
                [
                    ("GRID", (0, 0), (-1, -1), 0.4, colors.grey),
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                    ("TOPPADDING", (0, 0), (-1, -1), 2),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
                    ("LEFTPADDING", (0, 0), (-1, -1), 4),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ]
                + (
                    [("BACKGROUND", (0, 0), (-1, header_rows - 1), colors.whitesmoke)]
                    if header_rows
                    else []
                )
            )
        )
        return table


def spacer(height: float) -> Spacer:
    return Spacer(0, height)
