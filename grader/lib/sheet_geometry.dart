/// Printed answer-sheet geometry in millimetres, top-left origin (image
/// convention). Mirror of the layout constants in
/// generator/src/mcexam/render.py, which draws the same layout in PDF
/// bottom-left coordinates. The two must change together — this is the
/// contract the OMR detection relies on; treat the constants as frozen once
/// printed sheets are in the wild.
library;

const double pageWidthMm = 210;
const double pageHeightMm = 297;

/// Corner registration squares: inset from both page edges, side length.
const double regInsetMm = 8;
const double regSizeMm = 6;

/// Bubble grid: row 0 center sits gridTopFromTopMm below the page top
/// (render.py: GRID_TOP = PAGE_H - 70mm); rows run top-down in blocks of
/// [rowsPerBlock], blocks stack left-to-right.
const double gridTopFromTopMm = 70;
const double gridLeftMm = 25; // render.py: MARGIN (15) + 10
const double rowHeightMm = 7;
const double bubbleRadiusMm = 2;
const double bubblePitchMm = 8;
const int rowsPerBlock = 25;
const double blockLabelWidthMm = 10;
const double blockGapMm = 12;

double blockWidthMm(int optionsPerQuestion) =>
    blockLabelWidthMm + optionsPerQuestion * bubblePitchMm + blockGapMm;

/// Centres of the four corner registration squares, top-left origin, in the
/// order [topLeft, topRight, bottomLeft, bottomRight].
List<({double x, double y})> registrationMarkCentersMm() {
  const near = regInsetMm + regSizeMm / 2; // 11mm
  const farX = pageWidthMm - near; // 199mm
  const farY = pageHeightMm - near; // 286mm
  return const [
    (x: near, y: near),
    (x: farX, y: near),
    (x: near, y: farY),
    (x: farX, y: farY),
  ];
}

/// Centre of the bubble at [row], [col] (0-based), top-left origin.
({double x, double y}) bubbleCenterMm(int row, int col, int optionsPerQuestion) {
  final block = row ~/ rowsPerBlock;
  final rowInBlock = row % rowsPerBlock;
  final x = gridLeftMm +
      block * blockWidthMm(optionsPerQuestion) +
      blockLabelWidthMm +
      (col + 0.5) * bubblePitchMm;
  final y = gridTopFromTopMm + rowInBlock * rowHeightMm;
  return (x: x, y: y);
}
