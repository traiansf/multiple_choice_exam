/// Application state machine for the grading flow:
/// load key -> scan QR -> capture sheet -> result.
///
/// Pure orchestration over the core modules; screens bind to it via
/// ChangeNotifier. No camera or file-system access lives here, so the whole
/// flow is unit-testable with synthetic images.
library;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'framing.dart';
import 'grading.dart' as grading;
import 'keyfile.dart';
import 'omr.dart';
import 'qr_scan.dart';
import 'select.dart' show sectionKeys;

enum SessionStage {
  /// No answer key loaded yet.
  needKey,

  /// Key loaded; waiting for a student sheet's QR code.
  needQr,

  /// QR decoded; waiting for the bubble-sheet capture.
  needSheet,

  /// A sheet was processed: either graded, or flagged for manual review.
  result,
}

class GraderSession extends ChangeNotifier {
  AnswerKey? _key;
  QrPayload? _payload;
  OmrResult? _omr;
  grading.GradeResult? _grade;
  String? _lastError;

  AnswerKey? get answerKey => _key;
  QrPayload? get qrPayload => _payload;
  OmrResult? get omrResult => _omr;
  grading.GradeResult? get gradeResult => _grade;
  String? get lastError => _lastError;

  SessionStage get stage {
    if (_key == null) return SessionStage.needKey;
    if (_payload == null) return SessionStage.needQr;
    if (_grade != null || (_omr?.needsReview ?? false)) {
      return SessionStage.result;
    }
    return SessionStage.needSheet;
  }

  /// Loads a new answer key. Discards everything belonging to the previous
  /// exam (QR, sheet, result — and, once issue #4 lands, recorded grades:
  /// warn the user there before calling this).
  bool loadKey(String jsonText) {
    final AnswerKey parsed;
    try {
      parsed = AnswerKey.parse(jsonText);
    } on KeyfileFormatException catch (error) {
      _lastError = error.message;
      notifyListeners();
      return false;
    }
    _key = parsed;
    _payload = null;
    _omr = null;
    _grade = null;
    _lastError = null;
    notifyListeners();
    return true;
  }

  /// Decodes a scanned QR payload and validates it against the loaded key.
  /// Mismatches are rejected here, at scan time, so the user learns about a
  /// wrong sheet before photographing it.
  bool setQr(String rawValue) {
    final QrPayload decoded;
    try {
      decoded = QrPayload.decode(rawValue);
    } on QrPayloadException catch (error) {
      _lastError = error.message;
      notifyListeners();
      return false;
    }
    final key = _key!;
    if (decoded.sourceFingerprint != key.sourceFingerprint) {
      _lastError =
          'This sheet belongs to a different exam (QR fingerprint'
          ' ${decoded.sourceFingerprint}, key ${key.sourceFingerprint}).';
      notifyListeners();
      return false;
    }
    for (final section in sectionKeys) {
      if (decoded.counts[section]! > key.sections[section]!) {
        _lastError =
            'QR requests ${decoded.counts[section]} $section questions but'
            ' the key has only ${key.sections[section]}.';
        notifyListeners();
        return false;
      }
    }
    _payload = decoded;
    _omr = null;
    _grade = null;
    _lastError = null;
    notifyListeners();
    return true;
  }

  /// Processes a captured sheet image (already cropped to the page guide).
  /// Returns true when the session reached the result stage — either graded
  /// or flagged for manual review; false keeps needSheet with [lastError]
  /// holding a retake hint.
  bool processSheet(img.Image pageImage) {
    final key = _key!;
    final payload = _payload!;
    final exposure = exposureHint(pageImage);
    if (exposure != null) {
      _lastError = exposure;
      notifyListeners();
      return false;
    }
    final totalRows = payload.counts.values.fold(
      0,
      (sum, count) => sum + count,
    );
    final OmrResult detected;
    try {
      detected = detectMarks(
        pageImage,
        rows: totalRows,
        optionsPerQuestion: key.optionsPerQuestion,
      );
    } on OmrException catch (error) {
      _lastError = framingHintFor(error);
      notifyListeners();
      return false;
    }
    _omr = detected;
    if (detected.needsReview) {
      _grade = null;
      _lastError = null;
      notifyListeners();
      return true;
    }
    try {
      _grade = grading.grade(
        key: key,
        payload: payload,
        marks: detected.marksForGrading,
      );
    } on grading.GradingException catch (error) {
      _omr = null;
      _lastError = error.message;
      notifyListeners();
      return false;
    }
    _lastError = null;
    notifyListeners();
    return true;
  }

  /// Clears the sheet result to recapture the same student's sheet.
  void retakeSheet() {
    _omr = null;
    _grade = null;
    _lastError = null;
    notifyListeners();
  }

  /// Finishes this student and returns to the QR step for the next sheet.
  void nextSheet() {
    _payload = null;
    _omr = null;
    _grade = null;
    _lastError = null;
    notifyListeners();
  }
}
