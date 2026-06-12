import 'package:flutter_test/flutter_test.dart';
import 'package:grader/omr.dart';
import 'package:grader/sheet_geometry.dart' as geom;
import 'package:grader/sheet_render.dart';
import 'package:image/image.dart' as img;

void main() {
  const correctPositions = [3, 1, 0, 2, 3];

  test('reference sheet round-trips through our own OMR detection', () {
    final sheet = renderReferenceSheet(
      correctPositions: correctPositions,
      optionsPerQuestion: 4,
    );
    final result = detectMarks(sheet, rows: 5, optionsPerQuestion: 4);
    expect(result.needsReview, isFalse);
    expect(result.marks, correctPositions);
  });

  test('reference sheet has capture-frame aspect at the requested resolution',
      () {
    final sheet = renderReferenceSheet(
      correctPositions: correctPositions,
      optionsPerQuestion: 4,
      pxPerMm: 3,
    );
    expect(sheet.width, (geom.captureWidthMm * 3).round());
    expect(sheet.height, (geom.captureHeightMm * 3).round());
  });

  bool stripHasRed(img.Image sheet, int row, int optionsPerQuestion) {
    final pxPerMm = sheet.width / geom.captureWidthMm;
    final first = geom.bubbleCenterMm(row, 0, optionsPerQuestion);
    final last = geom.bubbleCenterMm(
      row,
      optionsPerQuestion - 1,
      optionsPerQuestion,
    );
    for (
      var x = ((first.x - 7) * pxPerMm).round();
      x <= ((last.x + 7) * pxPerMm).round();
      x++
    ) {
      // ±3mm: inside this row's annotation band (±3.15mm) but clear of the
      // neighbouring rows' bands (7mm pitch).
      for (
        var y = ((first.y - geom.captureTopMm - 3) * pxPerMm).round();
        y <= ((first.y - geom.captureTopMm + 3) * pxPerMm).round();
        y++
      ) {
        final pixel = sheet.getPixel(x, y);
        if (pixel.r > 180 && pixel.g < 100 && pixel.b < 100) return true;
      }
    }
    return false;
  }

  test('annotateWrongRows outlines only the wrong rows in red', () {
    final sheet = renderReferenceSheet(
      correctPositions: correctPositions,
      optionsPerQuestion: 4,
    );
    annotateWrongRows(sheet, const [1, 4], 4);
    expect(stripHasRed(sheet, 1, 4), isTrue);
    expect(stripHasRed(sheet, 4, 4), isTrue);
    expect(stripHasRed(sheet, 0, 4), isFalse);
    expect(stripHasRed(sheet, 2, 4), isFalse);
  });

  test('reference sheet round-trips across two bubble blocks (30 rows)', () {
    final positions = List<int>.generate(30, (i) => i % 4);
    final sheet = renderReferenceSheet(
      correctPositions: positions,
      optionsPerQuestion: 4,
    );
    final result = detectMarks(sheet, rows: 30, optionsPerQuestion: 4);
    expect(result.needsReview, isFalse);
    expect(result.marks, positions);
  });

  test('reference sheet round-trips for five options per question', () {
    const positions = [4, 0, 2];
    final sheet = renderReferenceSheet(
      correctPositions: positions,
      optionsPerQuestion: 5,
    );
    final result = detectMarks(sheet, rows: 3, optionsPerQuestion: 5);
    expect(result.marks, positions);
  });

  test('annotateWrongRows reaches second-block rows', () {
    final positions = List<int>.generate(30, (i) => i % 4);
    final sheet = renderReferenceSheet(
      correctPositions: positions,
      optionsPerQuestion: 4,
    );
    annotateWrongRows(sheet, const [25], 4);
    expect(stripHasRed(sheet, 25, 4), isTrue);
    expect(stripHasRed(sheet, 24, 4), isFalse);
    expect(stripHasRed(sheet, 26, 4), isFalse);
  });

  test('annotation does not disturb mark detection', () {
    final sheet = renderReferenceSheet(
      correctPositions: correctPositions,
      optionsPerQuestion: 4,
    );
    annotateWrongRows(sheet, const [0, 1, 2, 3, 4], 4);
    final result = detectMarks(sheet, rows: 5, optionsPerQuestion: 4);
    expect(result.needsReview, isFalse);
    expect(result.marks, correctPositions);
  });
}
