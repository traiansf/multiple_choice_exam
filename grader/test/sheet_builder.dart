import 'package:grader/sheet_geometry.dart' as geom;
import 'package:image/image.dart' as img;

/// Draws a synthetic capture-frame image (the band a correctly framed photo
/// covers): white canvas, black registration squares, bubble outlines, and
/// filled discs for the requested marks.
///
/// When [drawHeaderInk] is true, representative non-mark ink is drawn at its
/// real printed position within the capture frame:
///  - a name-line stripe at capture-y 3mm (page-y 48mm), x 15..90mm,
///  - small column-letter rects at capture-y 19mm (page-y 64mm), centred on
///    each first-block bubble x position.
/// This lets tests verify that the mark detector tolerates ink near the top
/// coarse search windows.
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
      final c = geom.bubbleCenterMm(row, col, optionsPerQuestion);
      final cx = ((c.x + offsetMm.x) * pxPerMm).round();
      // bubbleCenterMm returns page-mm; subtracting captureTopMm converts to
      // capture-frame coordinates (image top = capture top).
      final cy = ((c.y - geom.captureTopMm + offsetMm.y) * pxPerMm).round();
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
    // Name line: a ~0.5mm-tall filled stripe at capture-y 3mm, x 15..90mm.
    // (Corresponds to page-y 48mm, the "Name: ____" underscores.)
    const nameLineCapY = 3.0; // capture-mm
    img.fillRect(
      image,
      x1: ((15.0 + offsetMm.x) * pxPerMm).round(),
      y1: ((nameLineCapY + offsetMm.y) * pxPerMm).round(),
      x2: ((90.0 + offsetMm.x) * pxPerMm).round(),
      y2: ((nameLineCapY + 0.5 + offsetMm.y) * pxPerMm).round(),
      color: black,
    );
    // Column letters: ~1.5mm squares at capture-y 19mm, centred on each
    // first-block bubble x position (page-y 64mm = capture-y 19mm).
    const colLetterCapY = 19.0; // capture-mm
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
