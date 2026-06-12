/// Renders the synthetic reference answer sheet (correct answers filled) and
/// the red wrong-row annotations for the visual scoring-confirmation view.
/// Pure image code over sheet_geometry — no UI, fully unit-testable.
///
/// The rendered image is the capture-frame band (full page width, vertical
/// extent captureTopMm..captureTopMm+captureHeightMm), matching the scanned
/// crop it sits beside in the side-by-side scoring-confirmation view.
/// [annotateWrongRows] is applied to both the reference and the scanned crop,
/// so the single capture-frame convention serves both images.
library;

import 'package:image/image.dart' as img;

import 'sheet_geometry.dart' as geom;

/// Resolution of the rendered reference sheet (and the downscale target for
/// the displayed scan).
const double referencePxPerMm = 4;

/// Draws a clean answer-sheet page with the bubble at
/// `correctPositions[row]` filled on every row — what a perfect submission
/// of this variant would look like.
img.Image renderReferenceSheet({
  required List<int> correctPositions,
  required int optionsPerQuestion,
  double pxPerMm = referencePxPerMm,
}) {
  final sheet = img.Image(
    width: (geom.captureWidthMm * pxPerMm).round(),
    height: (geom.captureHeightMm * pxPerMm).round(),
  );
  img.fill(sheet, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);

  for (final center in geom.registrationMarkCentersInCaptureMm()) {
    img.fillRect(
      sheet,
      x1: ((center.x - geom.regSizeMm / 2) * pxPerMm).round(),
      y1: ((center.y - geom.regSizeMm / 2) * pxPerMm).round(),
      x2: ((center.x + geom.regSizeMm / 2) * pxPerMm).round(),
      y2: ((center.y + geom.regSizeMm / 2) * pxPerMm).round(),
      color: black,
    );
  }

  for (var row = 0; row < correctPositions.length; row++) {
    for (var col = 0; col < optionsPerQuestion; col++) {
      final center = geom.bubbleCenterInCaptureMm(row, col, optionsPerQuestion);
      final cx = (center.x * pxPerMm).round();
      final cy = (center.y * pxPerMm).round();
      img.drawCircle(
        sheet,
        x: cx,
        y: cy,
        radius: (geom.bubbleRadiusMm * pxPerMm).round(),
        color: black,
      );
      if (col == correctPositions[row]) {
        img.fillCircle(
          sheet,
          x: cx,
          y: cy,
          radius: (geom.bubbleRadiusMm * pxPerMm).round(),
          color: black,
        );
      }
    }
  }
  return sheet;
}

/// Outlines each 0-based row in [wrongRows] with a red rectangle spanning
/// the row's bubble strip. The outline stays clear of the bubbles, so a
/// previously detectable sheet stays detectable.
void annotateWrongRows(
  img.Image sheet,
  Iterable<int> wrongRows,
  int optionsPerQuestion,
) {
  final pxPerMm = sheet.width / geom.captureWidthMm;
  final red = img.ColorRgb8(220, 30, 30);
  for (final row in wrongRows) {
    final first = geom.bubbleCenterInCaptureMm(row, 0, optionsPerQuestion);
    final last = geom.bubbleCenterInCaptureMm(
      row,
      optionsPerQuestion - 1,
      optionsPerQuestion,
    );
    img.drawRect(
      sheet,
      x1: ((first.x - 6) * pxPerMm).round(),
      y1: ((first.y - geom.rowHeightMm / 2 * 0.9) * pxPerMm).round(),
      x2: ((last.x + 6) * pxPerMm).round(),
      y2: ((first.y + geom.rowHeightMm / 2 * 0.9) * pxPerMm).round(),
      color: red,
      thickness: (0.4 * pxPerMm).clamp(1, 6),
    );
  }
}
