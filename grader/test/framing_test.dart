import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:grader/framing.dart';
import 'package:grader/omr.dart';
import 'package:grader/sheet_geometry.dart' as geom;
import 'package:image/image.dart' as img;

import 'sheet_builder.dart';

void main() {
  group('pageGuideRect', () {
    test('portrait canvas: capture-frame aspect, centered, inset', () {
      const canvas = Size(400, 800);
      final guide = pageGuideRect(canvas);
      expect(
        guide.width / guide.height,
        closeTo(geom.captureWidthMm / geom.captureHeightMm, 1e-9),
      );
      expect(guide.center.dx, closeTo(200, 1e-9));
      expect(guide.center.dy, closeTo(400, 1e-9));
      expect(guide.left, greaterThanOrEqualTo(400 * 0.05 - 1e-9));
    });

    test('short landscape canvas: height-bound', () {
      const canvas = Size(800, 400);
      final guide = pageGuideRect(canvas);
      expect(
        guide.width / guide.height,
        closeTo(geom.captureWidthMm / geom.captureHeightMm, 1e-9),
      );
      expect(guide.height, lessThanOrEqualTo(400));
      expect(guide.top, greaterThanOrEqualTo(400 * 0.05 - 1e-9));
    });
  });

  test('pageGuideRect on a square canvas stays inside with capture-frame aspect', () {
    const canvas = Size(500, 500);
    final guide = pageGuideRect(canvas);
    expect(
      guide.width / guide.height,
      closeTo(geom.captureWidthMm / geom.captureHeightMm, 1e-9),
    );
    expect(guide.top, greaterThanOrEqualTo(0));
    expect(guide.bottom, lessThanOrEqualTo(500));
  });

  test('cropToGuideFraction clamps a rect extending beyond the photo', () {
    final photo = img.Image(width: 100, height: 100);
    img.fill(photo, color: img.ColorRgb8(128, 128, 128));
    const oversized = Rect.fromLTWH(-0.1, -0.1, 1.4, 1.4);
    final cropped = cropToGuideFraction(photo, oversized);
    expect(cropped.width, inInclusiveRange(1, 100));
    expect(cropped.height, inInclusiveRange(1, 100));
  });

  test('exposureHint samples even images smaller than the step', () {
    // The grid loop always samples (0,0), so a tiny image is still judged
    // (and the samples==0 guard only matters for zero-dimension inputs).
    final tiny = img.Image(width: 4, height: 4);
    img.fill(tiny, color: img.ColorRgb8(0, 0, 0));
    expect(exposureHint(tiny), contains('dark'));
  });

  test('cornerMarkTargets sit at capture-relative mark positions', () {
    final guide = Rect.fromLTWH(100, 50, 210, 212); // 1px per mm
    final targets = cornerMarkTargets(guide);
    expect(targets, hasLength(4));
    expect(targets[0].center.dx, closeTo(100 + 11, 0.01));
    expect(targets[0].center.dy, closeTo(50 + 11, 0.01));
    expect(targets[1].center.dx, closeTo(100 + 199, 0.01));
    expect(targets[3].center.dy, closeTo(50 + 201, 0.01));
    // 2x the printed mark size for alignment tolerance
    expect(targets[0].width, closeTo(2 * geom.regSizeMm, 0.01));
  });

  test('crop to guide makes an off-page photo detectable end-to-end', () {
    // Simulate a camera photo: the page occupies the guide region of a
    // larger gray scene, exactly as a user framing with the overlay would.
    final page = buildSheetImage(
      rows: 5,
      optionsPerQuestion: 4,
      filledByRow: {
        for (var r = 0; r < 5; r++) r: [r % 4],
      },
    );
    const photoW = 1200, photoH = 1600;
    final photo = img.Image(width: photoW, height: photoH);
    img.fill(photo, color: img.ColorRgb8(200, 200, 200)); // desk surround
    final guide = pageGuideRect(const Size(photoW * 1.0, photoH * 1.0));
    final scaled = img.copyResize(
      page,
      width: guide.width.round(),
      height: guide.height.round(),
    );
    img.compositeImage(
      photo,
      scaled,
      dstX: guide.left.round(),
      dstY: guide.top.round(),
    );

    final fraction = guideAsFraction(
      guide,
      const Size(photoW * 1.0, photoH * 1.0),
    );
    final cropped = cropToGuideFraction(photo, fraction);
    final result = detectMarks(cropped, rows: 5, optionsPerQuestion: 4);
    expect(result.needsReview, isFalse);
    expect(result.marks, [0, 1, 2, 3, 0]);

    // Without the crop, the photo violates the image-is-the-page assumption.
    expect(
      () => detectMarks(photo, rows: 5, optionsPerQuestion: 4),
      throwsA(isA<OmrException>()),
    );
  });

  group('exposureHint', () {
    test('normal sheet has no hint', () {
      final sheet = buildSheetImage(rows: 3, optionsPerQuestion: 4);
      expect(exposureHint(sheet), isNull);
    });

    test('dark image hints too dark', () {
      final dark = img.Image(width: 200, height: 200);
      img.fill(dark, color: img.ColorRgb8(30, 30, 30));
      expect(exposureHint(dark), contains('dark'));
    });

    test('blown-out image hints washed out', () {
      final bright = img.Image(width: 200, height: 200);
      img.fill(bright, color: img.ColorRgb8(250, 250, 250));
      expect(exposureHint(bright), contains('washed out'));
    });
  });

  group('framingHintFor', () {
    test('missing corner names the corner and the brackets', () {
      final hint = framingHintFor(
        OmrException('registration mark not found in the top-left corner'),
      );
      expect(hint, contains('top-left'));
      expect(hint, contains('bracket'));
      expect(hint, contains('answer area'));
    });

    test('low resolution suggests moving closer', () {
      final hint = framingHintFor(
        OmrException('image resolution too low (1.00 px/mm)'),
      );
      expect(hint.toLowerCase(), contains('closer'));
    });

    test('unknown errors get the generic hold-flat hint', () {
      expect(framingHintFor(StateError('boom')), contains('flat'));
    });
  });

  test('captureFractionOfPage pins top, height, left, width', () {
    // top = captureTopMm / pageHeightMm = 45 / 297
    // height = captureHeightMm / pageHeightMm = 212 / 297
    // left = 0, width = 1
    final f = captureFractionOfPage();
    expect(f.left, closeTo(0, 1e-9));
    expect(f.width, closeTo(1, 1e-9));
    expect(f.top, closeTo(45 / 297, 1e-9));
    expect(f.height, closeTo(212 / 297, 1e-9));
  });
}
