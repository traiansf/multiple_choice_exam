import 'package:flutter_test/flutter_test.dart';
import 'package:grader/sheet_geometry.dart' as geom;

void main() {
  // All expected values are hand-derived from the constants in
  // generator/src/mcexam/render.py (PDF bottom-left origin) converted to
  // top-left-origin millimetres. If these fail, the two sides of the printed
  // geometry contract have drifted.

  test('registration mark centers sit 11mm from each page corner', () {
    expect(geom.registrationMarkCentersMm(), [
      (x: 11.0, y: 11.0),
      (x: 199.0, y: 11.0),
      (x: 11.0, y: 286.0),
      (x: 199.0, y: 286.0),
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

  test('page dimensions are A4', () {
    expect(geom.pageWidthMm, 210.0);
    expect(geom.pageHeightMm, 297.0);
  });
}
