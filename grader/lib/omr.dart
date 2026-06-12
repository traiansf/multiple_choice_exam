/// OMR detection: locate the four registration marks in a capture-band image,
/// map the printed bubble grid onto it, sample each bubble's fill, and
/// classify every row. Ambiguous or multi-marked rows are flagged for manual
/// review, never guessed.
///
/// Assumes the input image frames the capture band — the answer area bounded
/// by the registration marks (full page width, the vertical band around the
/// bubble grid) — roughly axis-aligned. The bilinear mapping over the detected
/// registration quad absorbs translation, scale, and mild skew; strong
/// perspective correction is the camera pipeline's job (later milestone).
library;

import 'package:image/image.dart' as img;

import 'sheet_geometry.dart' as geom;

class OmrException implements Exception {
  OmrException(this.message);

  final String message;

  @override
  String toString() => 'OmrException: $message';
}

enum RowStatus {
  /// Exactly one confidently filled bubble.
  marked,

  /// No filled bubble at all.
  blank,

  /// Multiple filled bubbles, or a fill too faint to call — needs a human.
  needsReview,
}

class OmrRow {
  const OmrRow({
    required this.mark,
    required this.status,
    required this.fillRatios,
  });

  /// Detected bubble position, or null when blank or flagged for review.
  final int? mark;
  final RowStatus status;

  /// Dark-pixel fraction sampled inside each bubble, for diagnostics.
  final List<double> fillRatios;
}

class OmrResult {
  const OmrResult({required this.rows});

  final List<OmrRow> rows;

  /// Raw per-row marks (null = blank or flagged). Diagnostics only — use
  /// [marksForGrading] when feeding grade(), so flagged rows cannot be
  /// silently scored as unanswered.
  List<int?> get marks => [for (final row in rows) row.mark];

  /// Marks safe to pass to grading. Throws [OmrException] when any row needs
  /// manual review: grading such a sheet would silently count the flagged
  /// rows as unanswered, violating the flag-don't-guess contract. Resolve
  /// [reviewRows] by hand first.
  List<int?> get marksForGrading {
    if (needsReview) {
      throw OmrException('sheet has rows needing manual review: $reviewRows');
    }
    return marks;
  }

  bool get needsReview =>
      rows.any((row) => row.status == RowStatus.needsReview);

  /// 1-based sheet row numbers that need manual review.
  List<int> get reviewRows => [
    for (var i = 0; i < rows.length; i++)
      if (rows[i].status == RowStatus.needsReview) i + 1,
  ];
}

class OmrConfig {
  const OmrConfig({
    this.darkLuma = 128,
    this.filledMin = 0.45,
    this.emptyMax = 0.20,
    this.cornerWindowFraction = 0.04,
    this.sampleRadiusFactor = 0.7,
  });

  /// Luminance below which a pixel counts as ink. This is a single global
  /// threshold, tuned for synthetic images and clean print scans; unevenly
  /// lit phone photos will need adaptive thresholding (camera milestone).
  final int darkLuma;

  /// Dark fraction at or above which a bubble counts as filled.
  final double filledMin;

  /// Dark fraction at or below which a bubble counts as empty; values
  /// between [emptyMax] and [filledMin] are ambiguous.
  final double emptyMax;

  /// Half-size of each corner search window as a fraction of the page size.
  /// Kept tight so nearby page content (title text, the QR code) stays out
  /// of the window; a second, mark-sized pass refines the centroid.
  final double cornerWindowFraction;

  /// Bubble sampling radius as a fraction of the printed bubble radius
  /// (samples the interior, staying clear of the printed rim).
  final double sampleRadiusFactor;
}

typedef _Point = ({double x, double y});

/// Detects the marks on an answer-sheet image with [rows] printed grid rows.
///
/// [rows] must match what was printed (the QR counts); rows requested beyond
/// the printed grid sample empty paper and read back as blank — detection
/// cannot tell an unprinted row from an unanswered one.
OmrResult detectMarks(
  img.Image source, {
  required int rows,
  required int optionsPerQuestion,
  OmrConfig config = const OmrConfig(),
}) {
  if (rows <= 0 || optionsPerQuestion <= 0) {
    throw ArgumentError(
      'rows and optionsPerQuestion must be positive'
      ' (got $rows, $optionsPerQuestion)',
    );
  }
  if (rows > geom.maxRows(optionsPerQuestion)) {
    throw OmrException(
      '$rows rows exceed the printed sheet capacity of'
      ' ${geom.maxRows(optionsPerQuestion)} for $optionsPerQuestion options',
    );
  }
  final gray = source.numChannels == 1 ? source : img.grayscale(source.clone());
  final corners = _findRegistrationMarks(gray, config);

  // px-per-mm estimated from the detected mark spacing, for the sample radius.
  final markCenters = geom.registrationMarkCentersMm();
  final spanXMm = markCenters[1].x - markCenters[0].x;
  final spanYMm = markCenters[2].y - markCenters[0].y;
  final pxPerMm =
      ((corners[1].x - corners[0].x).abs() / spanXMm +
          (corners[2].y - corners[0].y).abs() / spanYMm) /
      2;
  if (pxPerMm < 2) {
    throw OmrException(
      'image resolution too low (${pxPerMm.toStringAsFixed(2)} px/mm);'
      ' at least 2 px/mm is needed to sample bubbles reliably',
    );
  }
  final radiusPx = geom.bubbleRadiusMm * config.sampleRadiusFactor * pxPerMm;

  final mapper = _BilinearMapper(corners);
  final detected = <OmrRow>[];
  for (var row = 0; row < rows; row++) {
    final ratios = <double>[];
    for (var col = 0; col < optionsPerQuestion; col++) {
      final mm = geom.bubbleCenterMm(row, col, optionsPerQuestion);
      final px = mapper.map(mm.x, mm.y);
      ratios.add(_darkFraction(gray, px, radiusPx, config.darkLuma));
    }
    detected.add(_classifyRow(ratios, config));
  }
  return OmrResult(rows: detected);
}

OmrRow _classifyRow(List<double> ratios, OmrConfig config) {
  final filled = <int>[];
  var ambiguous = false;
  for (var col = 0; col < ratios.length; col++) {
    if (ratios[col] >= config.filledMin) {
      filled.add(col);
    } else if (ratios[col] > config.emptyMax) {
      ambiguous = true;
    }
  }
  if (ambiguous || filled.length > 1) {
    return OmrRow(
      mark: null,
      status: RowStatus.needsReview,
      fillRatios: ratios,
    );
  }
  if (filled.isEmpty) {
    return OmrRow(mark: null, status: RowStatus.blank, fillRatios: ratios);
  }
  return OmrRow(
    mark: filled.single,
    status: RowStatus.marked,
    fillRatios: ratios,
  );
}

List<_Point> _findRegistrationMarks(img.Image gray, OmrConfig config) {
  const cornerNames = ['top-left', 'top-right', 'bottom-left', 'bottom-right'];
  // The input image is assumed to (roughly) frame the capture band — the
  // answer area bounded by the marks — not the whole page.
  final centers = geom.registrationMarkCentersInCaptureMm();
  final scaleX = gray.width / geom.captureWidthMm;
  final scaleY = gray.height / geom.captureHeightMm;
  final halfW = (gray.width * config.cornerWindowFraction).round();
  final halfH = (gray.height * config.cornerWindowFraction).round();

  final expectedArea = geom.regSizeMm * scaleX * geom.regSizeMm * scaleY;
  final found = <_Point>[];
  for (var i = 0; i < 4; i++) {
    // Coarse pass: centroid of ink in a window around the expected position.
    final coarse = _darkCentroid(
      gray,
      cx: (centers[i].x * scaleX).round(),
      cy: (centers[i].y * scaleY).round(),
      halfW: halfW,
      halfH: halfH,
      darkLuma: config.darkLuma,
    );
    if (coarse == null || coarse.count < expectedArea * 0.25) {
      throw OmrException(
        'registration mark not found in the ${cornerNames[i]} corner',
      );
    }
    // Refinement pass: recenter a mark-sized window on the coarse centroid so
    // stray ink at the window edge cannot bias the result.
    final refineHalfW = (geom.regSizeMm * 0.9 * scaleX).round();
    final refineHalfH = (geom.regSizeMm * 0.9 * scaleY).round();
    final fine = _darkCentroid(
      gray,
      cx: coarse.x.round(),
      cy: coarse.y.round(),
      halfW: refineHalfW,
      halfH: refineHalfH,
      darkLuma: config.darkLuma,
    );
    if (fine == null || fine.count < expectedArea * 0.25) {
      throw OmrException(
        'registration mark not found in the ${cornerNames[i]} corner',
      );
    }
    found.add((x: fine.x, y: fine.y));
  }
  return found;
}

({double x, double y, int count})? _darkCentroid(
  img.Image gray, {
  required int cx,
  required int cy,
  required int halfW,
  required int halfH,
  required int darkLuma,
}) {
  var darkCount = 0;
  var sumX = 0.0;
  var sumY = 0.0;
  for (var y = cy - halfH; y <= cy + halfH; y++) {
    if (y < 0 || y >= gray.height) continue;
    for (var x = cx - halfW; x <= cx + halfW; x++) {
      if (x < 0 || x >= gray.width) continue;
      if (gray.getPixel(x, y).r < darkLuma) {
        darkCount++;
        sumX += x;
        sumY += y;
      }
    }
  }
  if (darkCount == 0) return null;
  return (x: sumX / darkCount, y: sumY / darkCount, count: darkCount);
}

double _darkFraction(
  img.Image gray,
  _Point center,
  double radius,
  int darkLuma,
) {
  var total = 0;
  var dark = 0;
  final r2 = radius * radius;
  for (
    var y = (center.y - radius).floor();
    y <= (center.y + radius).ceil();
    y++
  ) {
    if (y < 0 || y >= gray.height) continue;
    for (
      var x = (center.x - radius).floor();
      x <= (center.x + radius).ceil();
      x++
    ) {
      if (x < 0 || x >= gray.width) continue;
      final dx = x - center.x;
      final dy = y - center.y;
      if (dx * dx + dy * dy > r2) continue;
      total++;
      if (gray.getPixel(x, y).r < darkLuma) dark++;
    }
  }
  if (total == 0) {
    throw OmrException(
      'bubble sample at (${center.x.toStringAsFixed(1)},'
      ' ${center.y.toStringAsFixed(1)}) lies outside the image',
    );
  }
  return dark / total;
}

/// Maps page millimetres to image pixels by bilinear interpolation over the
/// quad of detected registration-mark centers (order: tl, tr, bl, br).
class _BilinearMapper {
  _BilinearMapper(this._cornersPx) : _mm = geom.registrationMarkCentersMm();

  final List<_Point> _cornersPx;
  final List<({double x, double y})> _mm;

  _Point map(double xMm, double yMm) {
    final u = (xMm - _mm[0].x) / (_mm[1].x - _mm[0].x);
    final v = (yMm - _mm[0].y) / (_mm[2].y - _mm[0].y);
    final x =
        (1 - u) * (1 - v) * _cornersPx[0].x +
        u * (1 - v) * _cornersPx[1].x +
        (1 - u) * v * _cornersPx[2].x +
        u * v * _cornersPx[3].x;
    final y =
        (1 - u) * (1 - v) * _cornersPx[0].y +
        u * (1 - v) * _cornersPx[1].y +
        (1 - u) * v * _cornersPx[2].y +
        u * v * _cornersPx[3].y;
    return (x: x, y: y);
  }
}
