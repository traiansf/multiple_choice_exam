/// Printed answer-sheet geometry in millimetres, top-left origin (image
/// convention). Mirror of the layout constants in
/// generator/src/mcexam/render.py, which draws the same layout in PDF
/// bottom-left coordinates. The two must change together — this is the
/// contract the OMR detection relies on; treat the constants as frozen once
/// printed sheets are in the wild.
///
/// Registration marks bound the answer area (the capture frame), not the
/// page corners.
library;

/// Dimensions of the printed sheet. Detection works inside the capture frame
/// (captureWidthMm × captureHeightMm), so neither constant is consumed by OMR
/// code; only x-axis logic uses pageWidthMm (which equals captureWidthMm).
const double pageWidthMm = 210;
const double pageHeightMm = 297;
const double pageMarginMm = 15; // render.py: MARGIN

/// Registration squares: inset from the *capture frame* edges, side length.
/// The capture frame is the region a sheet photo must cover: the full page
/// width, but only the vertical band around the bubble grid (render.py:
/// CAPTURE_TOP / CAPTURE_HEIGHT).
const double regInsetMm = 8;
const double regSizeMm = 6;
const double captureTopMm = 45;
const double captureHeightMm = 212;
const double captureWidthMm = pageWidthMm;

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

/// Maximum grid rows that fit on the page (mirror of render.py max_rows).
int maxRows(int optionsPerQuestion) {
  const usable = pageWidthMm - pageMarginMm - gridLeftMm;
  return (usable / blockWidthMm(optionsPerQuestion)).floor() * rowsPerBlock;
}

/// Centres of the four registration squares in page mm, top-left origin,
/// order [topLeft, topRight, bottomLeft, bottomRight]. They bound the
/// answer area: 11mm inset from the capture-frame edges.
List<({double x, double y})> registrationMarkCentersMm() {
  const near = regInsetMm + regSizeMm / 2; // 11mm
  const farX = pageWidthMm - near; // 199mm
  const topY = captureTopMm + near; // 56mm
  const bottomY = captureTopMm + captureHeightMm - near; // 246mm
  return const [
    (x: near, y: topY),
    (x: farX, y: topY),
    (x: near, y: bottomY),
    (x: farX, y: bottomY),
  ];
}

/// Mark centres relative to the capture frame — where they appear in a
/// correctly framed photo (image top-left = capture-frame top-left).
List<({double x, double y})> registrationMarkCentersInCaptureMm() => [
  for (final c in registrationMarkCentersMm()) (x: c.x, y: c.y - captureTopMm),
];

/// Centre of the bubble at [row], [col] (0-based), top-left origin.
({double x, double y}) bubbleCenterMm(
  int row,
  int col,
  int optionsPerQuestion,
) {
  final block = row ~/ rowsPerBlock;
  final rowInBlock = row % rowsPerBlock;
  final x =
      gridLeftMm +
      block * blockWidthMm(optionsPerQuestion) +
      blockLabelWidthMm +
      (col + 0.5) * bubblePitchMm;
  final y = gridTopFromTopMm + rowInBlock * rowHeightMm;
  return (x: x, y: y);
}
