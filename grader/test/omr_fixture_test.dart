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

    final result = detectMarks(sheet, rows: rows, optionsPerQuestion: m);
    expect(result.needsReview, isFalse, reason: result.reviewRows.toString());
    expect(result.marks, expected);
    expect(result.rows.every((r) => r.status == RowStatus.marked), isTrue);
  });

  test('unstamped real sheet reads as fully blank', () {
    final bytes = File('test/fixtures/variant-001-page1.png').readAsBytesSync();
    final sheet = img.decodePng(bytes)!;
    final result = detectMarks(sheet, rows: 10, optionsPerQuestion: 4);
    expect(result.needsReview, isFalse);
    expect(result.rows.every((r) => r.status == RowStatus.blank), isTrue);
  });
}
