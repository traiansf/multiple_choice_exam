import 'package:flutter_test/flutter_test.dart';
import 'package:grader/sheet_geometry.dart' as geom;

void main() {
  // All expected values are hand-derived from the constants in
  // generator/src/mcexam/render.py (PDF bottom-left origin) converted to
  // top-left-origin millimetres. If these fail, the two sides of the printed
  // geometry contract have drifted.

  test('registration mark centers bound the answer area', () {
    // order: TL, TR, BL, BR — must match registrationMarkCentersMm() doc
    expect(geom.registrationMarkCentersMm(), [
      (x: 11.0, y: 56.0),
      (x: 199.0, y: 56.0),
      (x: 11.0, y: 246.0),
      (x: 199.0, y: 246.0),
    ]);
  });

  test('capture frame matches render.py CAPTURE_TOP/CAPTURE_HEIGHT', () {
    expect(geom.captureWidthMm, 210.0);
    expect(geom.captureWidthMm, geom.pageWidthMm);
    expect(geom.captureTopMm, 45.0);
    expect(geom.captureHeightMm, 212.0);
    // Relative to the capture frame the marks keep the legacy 11mm inset.
    expect(geom.registrationMarkCentersInCaptureMm(), [
      (x: 11.0, y: 11.0),
      (x: 199.0, y: 11.0),
      (x: 11.0, y: 201.0),
      (x: 199.0, y: 201.0),
    ]);
  });

  test('block width for 4 options is 54mm', () {
    expect(geom.blockWidthMm(4), 54.0);
  });

  test('bubble centers match render.py spot values (M=4)', () {
    expect(geom.bubbleCenterMm(0, 0, 4), (x: 39.0, y: 70.0));
    expect(geom.bubbleCenterMm(0, 3, 4), (x: 63.0, y: 70.0));
    expect(geom.bubbleCenterMm(1, 0, 4), (x: 39.0, y: 77.0));
    // Row 25 wraps into the second block: x shifts by one block width.
    expect(geom.bubbleCenterMm(25, 0, 4), (x: 93.0, y: 70.0));
    expect(geom.bubbleCenterMm(24, 0, 4), (x: 39.0, y: 70.0 + 24 * 7.0));
  });

  test('max rows matches the Python renderer capacity (75 for M=4)', () {
    expect(geom.maxRows(4), 75);
  });

  test('page dimensions are A4', () {
    expect(geom.pageWidthMm, 210.0);
    expect(geom.pageHeightMm, 297.0);
  });

  test('bubbleCenterInCaptureMm subtracts captureTopMm from y', () {
    // bubbleCenterMm(0, 0, 4) == (x: 39.0, y: 70.0); captureTopMm == 45.0
    expect(geom.bubbleCenterInCaptureMm(0, 0, 4), (x: 39.0, y: 25.0));
    // spot-check another row: bubbleCenterMm(1, 0, 4).y == 77.0 → 77 - 45 = 32
    expect(geom.bubbleCenterInCaptureMm(1, 0, 4), (x: 39.0, y: 32.0));
    // x is unchanged
    expect(
      geom.bubbleCenterInCaptureMm(0, 3, 4).x,
      geom.bubbleCenterMm(0, 3, 4).x,
    );
  });
}
