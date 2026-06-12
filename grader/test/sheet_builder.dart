import 'package:grader/sheet_geometry.dart' as geom;
import 'package:image/image.dart' as img;

/// Draws a synthetic capture-frame image (the band a correctly framed photo
/// covers): white canvas, black registration squares, bubble outlines, and
/// filled discs for the requested marks.
///
/// When [drawHeaderInk] is true, a thick name-line stripe is drawn inside the
/// top-left coarse search window but above the mark centre, to stress-test the
/// refinement pass.  The stripe overlaps the TL coarse window and biases the
/// coarse centroid upward; without the mark-sized refinement pass row 0
/// misreads — verified empirically (commit 975ad85).
img.Image buildSheetImage({
  required int rows,
  required int optionsPerQuestion,
  double pxPerMm = 4,
  int numChannels = 3,
  Map<int, List<int>> filledByRow = const {},
  Map<int, double> fillRadiusMmByRow = const {},
  ({double x, double y}) offsetMm = (x: 0, y: 0),
  bool omitTopLeftMark = false,
  bool drawHeaderInk = false,
}) {
  final image = img.Image(
    width: (geom.captureWidthMm * pxPerMm).round(),
    height: (geom.captureHeightMm * pxPerMm).round(),
    numChannels: numChannels,
  );
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);

  final markCenters = geom.registrationMarkCentersInCaptureMm();
  for (var i = 0; i < 4; i++) {
    if (i == 0 && omitTopLeftMark) continue;
    final c = markCenters[i];
    img.fillRect(
      image,
      x1: ((c.x + offsetMm.x - geom.regSizeMm / 2) * pxPerMm).round(),
      y1: ((c.y + offsetMm.y - geom.regSizeMm / 2) * pxPerMm).round(),
      x2: ((c.x + offsetMm.x + geom.regSizeMm / 2) * pxPerMm).round(),
      y2: ((c.y + offsetMm.y + geom.regSizeMm / 2) * pxPerMm).round(),
      color: black,
    );
  }

  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < optionsPerQuestion; col++) {
      final c = geom.bubbleCenterInCaptureMm(row, col, optionsPerQuestion);
      final cx = ((c.x + offsetMm.x) * pxPerMm).round();
      final cy = ((c.y + offsetMm.y) * pxPerMm).round();
      img.drawCircle(
        image,
        x: cx,
        y: cy,
        radius: (geom.bubbleRadiusMm * pxPerMm).round(),
        color: black,
      );
      if (filledByRow[row]?.contains(col) ?? false) {
        final radiusMm = fillRadiusMmByRow[row] ?? geom.bubbleRadiusMm;
        img.fillCircle(
          image,
          x: cx,
          y: cy,
          radius: (radiusMm * pxPerMm).round(),
          color: black,
        );
      }
    }
  }

  if (drawHeaderInk) {
    // Name-line stripe: 1.75mm tall, x 8..90mm, capture-y 2.5mm.
    const nameLineCapY = 2.5; // capture-mm — top of TL coarse window
    const nameLineHeight = 1.75; // mm — intentionally exaggerated for stress test
    img.fillRect(
      image,
      x1: ((8.0 + offsetMm.x) * pxPerMm).round(),
      y1: ((nameLineCapY + offsetMm.y) * pxPerMm).round(),
      x2: ((90.0 + offsetMm.x) * pxPerMm).round(),
      y2: ((nameLineCapY + nameLineHeight + offsetMm.y) * pxPerMm).round(),
      color: black,
    );
    // Column letters: ~1.5mm squares centred on each first-block bubble x.
    // render.py places letters 6mm above the grid top (GRID_TOP + 6mm offset
    // in page coords); in capture coords that is gridTopFromTopMm - 6 - captureTopMm.
    final colLetterCapY =
        geom.gridTopFromTopMm - 6 - geom.captureTopMm; // == 19.0 mm
    const colLetterHalf = 0.75; // half of 1.5mm
    for (var col = 0; col < optionsPerQuestion; col++) {
      final bx = geom.bubbleCenterMm(0, col, optionsPerQuestion).x;
      img.fillRect(
        image,
        x1: ((bx - colLetterHalf + offsetMm.x) * pxPerMm).round(),
        y1: ((colLetterCapY - colLetterHalf + offsetMm.y) * pxPerMm).round(),
        x2: ((bx + colLetterHalf + offsetMm.x) * pxPerMm).round(),
        y2: ((colLetterCapY + colLetterHalf + offsetMm.y) * pxPerMm).round(),
        color: black,
      );
    }
  }

  return image;
}
