import 'package:grader/sheet_geometry.dart' as geom;
import 'package:image/image.dart' as img;

/// Draws a synthetic capture-frame image (the band a correctly framed photo
/// covers): white canvas, black registration squares, bubble outlines, and
/// filled discs for the requested marks.
///
/// When [drawHeaderInk] is true, a thick name-line stripe is drawn inside the
/// top-left coarse search window but above the mark centre, to stress-test the
/// refinement pass:
///
///  - a name-line stripe at capture-y 2.5..4.25mm (page-y 47.5..49.25mm),
///    x 8..90mm — this is 1.75mm tall, representative of heavy text ink near
///    the top of the printed answer area (intentionally thicker than a real
///    0.3mm stroke; this is a stress test, not a fidelity check).
///  - small column-letter rects at capture-y 19mm (page-y 64mm), centred on
///    each first-block bubble x position.
///
/// Geometry derivation (at 4 px/mm, no offsetMm):
///  - TL coarse window: halfW=halfH=34px = 8.5mm, centred at (11,11)mm,
///    covering x=y∈[2.5..19.5mm].  The stripe (x=8..90mm, y=2.5..4.25mm)
///    enters the window from x=8mm to x=19.5mm = 47px wide, 8 rows
///    (y=10..17px) → ~376 dark px at centre y≈13.5px = 3.4mm.
///  - Coarse centroid y ≈ (625×11mm + 376×3.4mm) / 1001 ≈ 8.1mm
///    → ~2.9mm upward bias from the true mark centre at y=11mm.
///  - Without refinement (fine=coarse) the TL corner is detected ~2.9mm too
///    high; bilinear weight at bubble row 0 col 2 ≈ 0.71, so the sampling
///    centre shifts ~2.0mm above the filled disc, dropping fill ratio to
///    ≈0.41 < 0.45 (filledMin) → row is ambiguous/blank → test fails.
///  - Fine-window half = 6mm×0.9 = 5.4mm; centred on biased coarse (~8.1mm)
///    it covers y≈[2.75..13.75mm].  The stripe (top at y=2.5mm) contributes
///    ~273 of its 376 px to the fine window, but the 600-px mark mass pulls
///    the fine centroid back to y≈8.5mm → bubble error ≈1.7mm → fill ratio
///    ≈0.54 > 0.45 → row is correctly classified as marked → test passes.
///
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
    // Name-line stripe: 1.75mm tall, x 8..90mm, capture-y 2.5..4.25mm.
    // Starts at the top of the TL coarse window (y=2.5mm) and spans into it.
    // See class doc for the exact centroid-bias derivation.
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
    // Column letters: ~1.5mm squares at capture-y 19mm, centred on each
    // first-block bubble x position (page-y 64mm = capture-y 19mm).
    // Bubble x positions start at ~39mm — all outside the TL window (x≤19.5mm).
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
