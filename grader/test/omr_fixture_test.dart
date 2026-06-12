import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grader/omr.dart';
import 'package:grader/sheet_geometry.dart' as geom;
import 'package:image/image.dart' as img;

/// End-to-end geometry check against the REAL Python renderer output.
///
/// The fixture is page 1 of a generator-produced PDF rasterized at 150 dpi:
///   mcexam generate --input examples/sample-exam.md --variants 1 \
///       --questions 10 --base-seed 7 --out /tmp/omr-fix
///   pdftoppm -png -r 150 -f 1 -l 1 /tmp/omr-fix/variant-001.pdf \
///       grader/test/fixtures/variant-001-page1
///
/// The test stamps student marks onto the real sheet and runs detection. If
/// sheet_geometry.dart ever drifted from render.py, the registration quad
/// would map the bubbles to the wrong pixels and this test would fail.
///
/// Note: [detectMarks] expects the capture band, not the full page. All tests
/// that call [detectMarks] first crop with [cropToCapture] — exactly what the
/// production [cropToGuideFraction] path does.

/// Crops the full-page fixture raster to the capture band — exactly what
/// the production cropToGuideFraction path hands to detectMarks.
img.Image cropToCapture(img.Image page) {
  final pxPerMm = page.width / geom.pageWidthMm;
  return img.copyCrop(
    page,
    x: 0,
    y: (geom.captureTopMm * pxPerMm).round(),
    width: page.width,
    height: (geom.captureHeightMm * pxPerMm).round(),
  );
}

void main() {
  test('detects marks stamped onto the real rendered sheet', () {
    final bytes = File('test/fixtures/variant-001-page1.png').readAsBytesSync();
    final sheet = img.decodePng(bytes)!;
    final pxPerMm = sheet.width / geom.pageWidthMm;
    final black = img.ColorRgb8(0, 0, 0);

    const rows = 10;
    const m = 4;
    final expected = [for (var r = 0; r < rows; r++) r % m];
    for (var row = 0; row < rows; row++) {
      final c = geom.bubbleCenterMm(row, expected[row], m);
      img.fillCircle(
        sheet,
        x: (c.x * pxPerMm).round(),
        y: (c.y * pxPerMm).round(),
        radius: (geom.bubbleRadiusMm * pxPerMm).round(),
        color: black,
      );
    }

    final result = detectMarks(cropToCapture(sheet), rows: rows, optionsPerQuestion: m);
    expect(result.needsReview, isFalse, reason: result.reviewRows.toString());
    expect(result.marks, expected);
    expect(result.rows.every((r) => r.status == RowStatus.marked), isTrue);
  });

  test('printed geometry on the real PNG matches sheet_geometry (anchor)', () {
    // Independent drift anchor: the stamped test above moves its stamps WITH
    // any sheet_geometry constant drift, so it cannot catch one. This test
    // measures the PRINTED ink (drawn by render.py) and compares its position
    // to the Dart geometry directly: the centroid of dark pixels in a small
    // window around each expected position must coincide with the expected
    // position. A 1mm constant drift fails the 0.7mm tolerance.
    final bytes = File('test/fixtures/variant-001-page1.png').readAsBytesSync();
    final sheet = img.decodePng(bytes)!;
    final pxPerMm = sheet.width / geom.pageWidthMm;

    ({double x, double y}) darkCentroid(double xMm, double yMm, double halfMm) {
      var count = 0;
      var sumX = 0.0;
      var sumY = 0.0;
      final half = (halfMm * pxPerMm).round();
      final cx = (xMm * pxPerMm).round();
      final cy = (yMm * pxPerMm).round();
      for (var y = cy - half; y <= cy + half; y++) {
        for (var x = cx - half; x <= cx + half; x++) {
          if (sheet.getPixel(x, y).luminance < 128) {
            count++;
            sumX += x;
            sumY += y;
          }
        }
      }
      expect(count, greaterThan(0));
      return (x: sumX / count / pxPerMm, y: sumY / count / pxPerMm);
    }

    const toleranceMm = 0.7;
    for (final expected in geom.registrationMarkCentersMm()) {
      final got = darkCentroid(expected.x, expected.y, 5);
      expect((got.x - expected.x).abs(), lessThan(toleranceMm));
      expect((got.y - expected.y).abs(), lessThan(toleranceMm));
    }
    // Two printed bubble rims (the ring's centroid is its center): first row
    // first column, and last row last column.
    for (final (row, col) in [(0, 0), (9, 3)]) {
      final expected = geom.bubbleCenterMm(row, col, 4);
      final got = darkCentroid(expected.x, expected.y, 3);
      expect(
        (got.x - expected.x).abs(),
        lessThan(toleranceMm),
        reason: 'bubble ($row,$col) x',
      );
      expect(
        (got.y - expected.y).abs(),
        lessThan(toleranceMm),
        reason: 'bubble ($row,$col) y',
      );
    }
  });

  test('unstamped real sheet reads as fully blank', () {
    final bytes = File('test/fixtures/variant-001-page1.png').readAsBytesSync();
    final sheet = img.decodePng(bytes)!;
    final result = detectMarks(cropToCapture(sheet), rows: 10, optionsPerQuestion: 4);
    expect(result.needsReview, isFalse);
    expect(result.rows.every((r) => r.status == RowStatus.blank), isTrue);
  });
}
