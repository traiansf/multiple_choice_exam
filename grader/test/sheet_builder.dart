import 'package:grader/sheet_geometry.dart' as geom;
import 'package:image/image.dart' as img;

/// Draws a synthetic answer-sheet page: white canvas, black registration
/// squares, bubble outlines, and filled discs for the requested marks.
img.Image buildSheetImage({
  required int rows,
  required int optionsPerQuestion,
  double pxPerMm = 4,
  int numChannels = 3,
  Map<int, List<int>> filledByRow = const {},
  Map<int, double> fillRadiusMmByRow = const {},
  ({double x, double y}) offsetMm = (x: 0, y: 0),
  bool omitTopLeftMark = false,
}) {
  final image = img.Image(
    width: (geom.pageWidthMm * pxPerMm).round(),
    height: (geom.pageHeightMm * pxPerMm).round(),
    numChannels: numChannels,
  );
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);

  final markCenters = geom.registrationMarkCentersMm();
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
  return image;
}
