import 'package:flutter_test/flutter_test.dart';
import 'package:grader/omr.dart';
import 'package:grader/sheet_geometry.dart' as geom;
import 'package:image/image.dart' as img;

/// Draws a synthetic answer-sheet page: white canvas, black registration
/// squares, bubble outlines, and filled discs for the requested marks.
img.Image buildSheetImage({
  required int rows,
  required int optionsPerQuestion,
  double pxPerMm = 4,
  Map<int, List<int>> filledByRow = const {},
  Map<int, double> fillRadiusMmByRow = const {},
  ({double x, double y}) offsetMm = (x: 0, y: 0),
  bool omitTopLeftMark = false,
}) {
  final image = img.Image(
    width: (geom.pageWidthMm * pxPerMm).round(),
    height: (geom.pageHeightMm * pxPerMm).round(),
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

void main() {
  Map<int, List<int>> cleanMarks(int rows) => {
        for (var row = 0; row < rows; row++) row: [row % 4],
      };

  test('clean sheet: every row detected with the marked column', () {
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      filledByRow: cleanMarks(10),
    );
    final result = detectMarks(sheet, rows: 10, optionsPerQuestion: 4);
    expect(result.needsReview, isFalse);
    expect(result.marks, [for (var r = 0; r < 10; r++) r % 4]);
    expect(result.rows.every((r) => r.status == RowStatus.marked), isTrue);
  });

  test('row without any fill is blank, not flagged', () {
    final marks = cleanMarks(10)..remove(3);
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      filledByRow: marks,
    );
    final result = detectMarks(sheet, rows: 10, optionsPerQuestion: 4);
    expect(result.rows[3].status, RowStatus.blank);
    expect(result.marks[3], isNull);
    expect(result.needsReview, isFalse);
  });

  test('double-marked row is flagged for review', () {
    final marks = cleanMarks(10)..[5] = [1, 2];
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      filledByRow: marks,
    );
    final result = detectMarks(sheet, rows: 10, optionsPerQuestion: 4);
    expect(result.rows[5].status, RowStatus.needsReview);
    expect(result.marks[5], isNull);
    expect(result.needsReview, isTrue);
    expect(result.reviewRows, [6]);
  });

  test('faint partial fill is ambiguous and flagged for review', () {
    final marks = cleanMarks(10);
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      filledByRow: marks,
      fillRadiusMmByRow: {7: 0.8}, // small blob inside the 2mm bubble
    );
    final result = detectMarks(sheet, rows: 10, optionsPerQuestion: 4);
    expect(result.rows[7].status, RowStatus.needsReview);
    expect(result.reviewRows, [8]);
  });

  test('page content offset by 3mm is still detected correctly', () {
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      filledByRow: cleanMarks(10),
      offsetMm: (x: 3, y: 3),
    );
    final result = detectMarks(sheet, rows: 10, optionsPerQuestion: 4);
    expect(result.needsReview, isFalse);
    expect(result.marks, [for (var r = 0; r < 10; r++) r % 4]);
  });

  test('works at a different resolution (3 px/mm)', () {
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      pxPerMm: 3,
      filledByRow: cleanMarks(10),
    );
    final result = detectMarks(sheet, rows: 10, optionsPerQuestion: 4);
    expect(result.marks, [for (var r = 0; r < 10; r++) r % 4]);
  });

  test('second bubble block (row >= 25) is sampled at the shifted x', () {
    final marks = cleanMarks(30);
    final sheet = buildSheetImage(
      rows: 30,
      optionsPerQuestion: 4,
      filledByRow: marks,
    );
    final result = detectMarks(sheet, rows: 30, optionsPerQuestion: 4);
    expect(result.needsReview, isFalse);
    expect(result.marks, [for (var r = 0; r < 30; r++) r % 4]);
  });

  test('missing registration mark raises a corner-naming error', () {
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      filledByRow: cleanMarks(10),
      omitTopLeftMark: true,
    );
    expect(
      () => detectMarks(sheet, rows: 10, optionsPerQuestion: 4),
      throwsA(
        isA<OmrException>().having(
          (e) => e.message,
          'message',
          contains('top-left'),
        ),
      ),
    );
  });
}
