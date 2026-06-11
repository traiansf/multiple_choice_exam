/// Camera-framing helpers for capturing the answer sheet: the on-screen A4
/// guide rectangle, corner-mark targets, crop-to-guide preprocessing, an
/// exposure gate, and actionable hints when detection fails. Pure logic —
/// no camera plumbing — so everything here is unit-testable.
library;

import 'dart:ui';

import 'package:image/image.dart' as img;

import 'omr.dart';
import 'sheet_geometry.dart' as geom;

/// Largest A4-portrait rectangle centred in [canvas], inset by
/// [marginFraction] of the shortest canvas side.
Rect pageGuideRect(Size canvas, {double marginFraction = 0.05}) {
  final margin = canvas.shortestSide * marginFraction;
  final availableW = canvas.width - 2 * margin;
  final availableH = canvas.height - 2 * margin;
  const aspect = geom.pageWidthMm / geom.pageHeightMm;
  var width = availableW;
  var height = width / aspect;
  if (height > availableH) {
    height = availableH;
    width = height * aspect;
  }
  return Rect.fromLTWH(
    (canvas.width - width) / 2,
    (canvas.height - height) / 2,
    width,
    height,
  );
}

/// Where the four printed registration marks should appear inside [guide]
/// (same order as sheet_geometry: TL, TR, BL, BR). Each target square is
/// twice the printed mark size, giving the user alignment tolerance.
List<Rect> cornerMarkTargets(Rect guide) {
  final scaleX = guide.width / geom.pageWidthMm;
  final scaleY = guide.height / geom.pageHeightMm;
  return [
    for (final c in geom.registrationMarkCentersMm())
      Rect.fromCenter(
        center: Offset(guide.left + c.x * scaleX, guide.top + c.y * scaleY),
        width: 2 * geom.regSizeMm * scaleX,
        height: 2 * geom.regSizeMm * scaleY,
      ),
  ];
}

/// Expresses a guide rect drawn on [canvasSize] as fractions (0..1) of the
/// canvas, so it can be applied to a captured photo of any resolution with
/// the same aspect.
Rect guideAsFraction(Rect guide, Size canvasSize) => Rect.fromLTWH(
  guide.left / canvasSize.width,
  guide.top / canvasSize.height,
  guide.width / canvasSize.width,
  guide.height / canvasSize.height,
);

/// Crops [photo] to the page area indicated by the on-screen guide,
/// expressed as fractions of the photo dimensions. This restores the OMR
/// assumption that the image is (roughly) the page.
img.Image cropToGuideFraction(img.Image photo, Rect guideFraction) {
  final x = (guideFraction.left * photo.width).round().clamp(
    0,
    photo.width - 1,
  );
  final y = (guideFraction.top * photo.height).round().clamp(
    0,
    photo.height - 1,
  );
  final width = (guideFraction.width * photo.width).round().clamp(
    1,
    photo.width - x,
  );
  final height = (guideFraction.height * photo.height).round().clamp(
    1,
    photo.height - y,
  );
  return img.copyCrop(photo, x: x, y: y, width: width, height: height);
}

/// Quick exposure check on a sparse pixel grid; returns a user-facing hint,
/// or null when the exposure looks usable.
///
/// A page image is mostly white paper, so a high mean is normal; "washed
/// out" is instead detected as the near-total absence of dark (ink) pixels —
/// glare that destroys the printed marks also destroys this fraction.
String? exposureHint(img.Image photo, {int step = 8}) {
  var samples = 0;
  var sum = 0.0;
  var dark = 0;
  for (var y = 0; y < photo.height; y += step) {
    for (var x = 0; x < photo.width; x += step) {
      final luminance = photo.getPixel(x, y).luminance;
      sum += luminance;
      if (luminance < 128) dark++;
      samples++;
    }
  }
  final mean = sum / samples;
  if (mean < 70) {
    return 'The image is too dark — add light or move out of the shadow.';
  }
  if (dark / samples < 0.001) {
    return 'The image is washed out — reduce glare or direct light.';
  }
  return null;
}

/// Translates a detection failure into actionable framing guidance.
String framingHintFor(Object error) {
  if (error is OmrException) {
    final text = error.message;
    if (text.contains('registration mark not found')) {
      final corner = RegExp(
        'top-left|top-right|bottom-left|bottom-right',
      ).firstMatch(text)?.group(0);
      return 'The ${corner ?? 'corner'} alignment square was not found.'
          ' Fit the whole sheet inside the frame, with each black corner'
          ' square inside its bracket.';
    }
    if (text.contains('resolution too low')) {
      return 'The sheet is too small in the frame — move closer so the'
          ' sheet fills the guide.';
    }
  }
  return 'Could not read the sheet. Hold the phone flat above the sheet,'
      ' fill the frame, and avoid shadows.';
}
