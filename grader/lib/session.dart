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
import 'records.dart';
import 'select.dart' show sectionKeys;
import 'sheet_geometry.dart' as geom;
import 'sheet_render.dart';

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
  Uint8List? _referencePng;
  Uint8List? _scannedPng;
  bool _confirmed = false;

  AnswerKey? get answerKey => _key;
  QrPayload? get qrPayload => _payload;
  OmrResult? get omrResult => _omr;
  grading.GradeResult? get gradeResult => _grade;
  String? get lastError => _lastError;

  /// PNG of the generated reference sheet (correct answers filled, wrong
  /// rows outlined in red); null unless the current sheet graded cleanly.
  Uint8List? get referenceSheetPng => _referencePng;

  /// PNG of the scanned page with the same wrong-row outlines.
  Uint8List? get scannedSheetPng => _scannedPng;

  /// Whether the user confirmed the displayed scoring.
  bool get confirmed => _confirmed;

  /// Confirmed grades of the current exam, keyed by variant id. Cleared
  /// (after the UI's warning) when a new answer key is loaded.
  final GradeBook gradeBook = GradeBook();

  List<String> _roster = const [];

  /// The loaded student roster, in file order. Survives [loadKey] — a
  /// roster describes the class, not one exam.
  List<String> get roster => _roster;

  /// Roster names not yet assigned to a grade — except the current
  /// variant's own assignment, which stays selectable for re-grading.
  List<String> get unassignedStudents {
    final current = _payload == null
        ? null
        : gradeBook.recordFor(_payload!.variantId)?.studentName;
    final taken = {
      for (final record in gradeBook.records)
        if (record.studentName != null) record.studentName!,
    };
    return [
      for (final name in _roster)
        if (!taken.contains(name) || name == current) name,
    ];
  }

  /// Loads a roster: one student name per line; blank lines ignored,
  /// duplicates collapsed.
  bool loadRoster(String text) {
    final names = <String>[];
    final seen = <String>{};
    for (final line in text.split('\n')) {
      final name = line.trim();
      if (name.isNotEmpty && seen.add(name)) names.add(name);
    }
    if (names.isEmpty) {
      _lastError = 'The roster file contains no names.';
      notifyListeners();
      return false;
    }
    _roster = List.unmodifiable(names);
    _lastError = null;
    notifyListeners();
    return true;
  }

  SessionStage get stage {
    if (_key == null) return SessionStage.needKey;
    if (_payload == null) return SessionStage.needQr;
    if (_grade != null || (_omr?.needsReview ?? false)) {
      return SessionStage.result;
    }
    return SessionStage.needSheet;
  }

  /// Loads a new answer key. Discards everything belonging to the previous
  /// exam — including the recorded grades, silently. Every call site must
  /// warn the user first when [gradeBook] is non-empty (the home screen's
  /// replace-key dialog does); this method cannot ask.
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
    _referencePng = null;
    _scannedPng = null;
    _confirmed = false;
    gradeBook.clear();
    _lastError = null;
    notifyListeners();
    return true;
  }

  /// Decodes a scanned QR payload and validates it against the loaded key.
  /// Mismatches are rejected here, at scan time, so the user learns about a
  /// wrong sheet before photographing it.
  bool setQr(String rawValue) {
    if (_key == null) {
      throw StateError('setQr called before an answer key was loaded');
    }
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
    _referencePng = null;
    _scannedPng = null;
    _confirmed = false;
    _lastError = null;
    notifyListeners();
    return true;
  }

  /// Processes a captured sheet image (already cropped to the page guide).
  /// Returns true when the session reached the result stage — either graded
  /// or flagged for manual review; false keeps needSheet with [lastError]
  /// holding a retake hint.
  bool processSheet(img.Image pageImage) {
    final key = _key;
    final payload = _payload;
    if (key == null || payload == null) {
      throw StateError(
        'processSheet called before ${key == null ? 'an answer key' : 'a QR'}'
        ' was loaded',
      );
    }
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
      // No reference (nothing was graded), but keep the scan with the
      // flagged rows outlined so the grader can see what the camera saw
      // while grading by hand on the review screen.
      _referencePng = null;
      _scannedPng = _encodeScan(pageImage, [
        for (final row in detected.reviewRows) row - 1,
      ], key.optionsPerQuestion);
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
      // Defensive backstop only: setQr already rejected fingerprint and
      // count mismatches, and detectMarks can only produce in-range marks of
      // the right length, so this is unreachable in the normal flow. Keep it
      // so a future grade() precondition cannot crash the app.
      _omr = null;
      _lastError = error.message;
      notifyListeners();
      return false;
    }
    _buildComparison(pageImage, key.optionsPerQuestion);
    _lastError = null;
    notifyListeners();
    return true;
  }

  /// Builds the side-by-side confirmation images: the generated reference
  /// sheet (correct answers filled) and the scanned page, both with the
  /// wrongly-answered rows outlined in red.
  void _buildComparison(img.Image pageImage, int optionsPerQuestion) {
    final grade = _grade!;
    final wrongRows = [
      for (final question in grade.perQuestion)
        if (!question.correct) question.sheetNumber - 1,
    ];
    final reference = renderReferenceSheet(
      correctPositions: [
        for (final question in grade.perQuestion) question.correctPosition,
      ],
      optionsPerQuestion: optionsPerQuestion,
    );
    annotateWrongRows(reference, wrongRows, optionsPerQuestion);
    _referencePng = Uint8List.fromList(img.encodePng(reference));
    _scannedPng = _encodeScan(pageImage, wrongRows, optionsPerQuestion);
  }

  /// Encodes the scanned page with [highlightRows] (0-based) outlined in
  /// red. Downscales camera-resolution pages first: full-resolution PNG
  /// encodes block the UI thread for hundreds of ms, and the display never
  /// needs more pixels.
  Uint8List _encodeScan(
    img.Image pageImage,
    List<int> highlightRows,
    int optionsPerQuestion,
  ) {
    final targetWidth = (geom.captureWidthMm * referencePxPerMm).round();
    final scanned = pageImage.width > targetWidth
        ? img.copyResize(pageImage, width: targetWidth)
        : pageImage.clone();
    annotateWrongRows(scanned, highlightRows, optionsPerQuestion);
    return Uint8List.fromList(img.encodePng(scanned));
  }

  /// Marks the displayed scoring as user-confirmed and records it in the
  /// grade book (replacing any earlier grade of the same variant — a
  /// re-scan updates the score). [studentName] is the roster name the
  /// grader read off the paper, if any.
  void confirmResult({String? studentName}) {
    final grade = _grade;
    if (grade == null) {
      throw StateError('confirmResult called without a graded sheet');
    }
    _confirmed = true;
    gradeBook.record(
      GradeRecord(
        variantId: _payload!.variantId,
        score: grade.score,
        total: grade.total,
        recordedAt: DateTime.now(),
        studentName: studentName,
      ),
    );
    notifyListeners();
  }

  /// Records a hand-entered score for a review-flagged sheet: the grader
  /// inspected the paper on the review screen and graded it manually. Only
  /// valid while the current sheet needs review — cleanly graded sheets go
  /// through [confirmResult].
  void submitManualGrade(int score, {String? studentName}) {
    final payload = _payload;
    if (payload == null || !(_omr?.needsReview ?? false)) {
      throw StateError(
        'submitManualGrade is only valid for a review-flagged sheet',
      );
    }
    final total = payload.counts.values.fold(0, (sum, count) => sum + count);
    if (score < 0 || score > total) {
      throw ArgumentError.value(score, 'score', 'must be between 0 and $total');
    }
    _confirmed = true;
    gradeBook.record(
      GradeRecord(
        variantId: payload.variantId,
        score: score,
        total: total,
        recordedAt: DateTime.now(),
        manual: true,
        studentName: studentName,
      ),
    );
    notifyListeners();
  }

  /// Clears the sheet result to recapture the same student's sheet.
  void retakeSheet() {
    _omr = null;
    _grade = null;
    _referencePng = null;
    _scannedPng = null;
    _confirmed = false;
    _lastError = null;
    notifyListeners();
  }

  /// Finishes this student and returns to the QR step for the next sheet.
  void nextSheet() {
    _payload = null;
    _omr = null;
    _grade = null;
    _referencePng = null;
    _scannedPng = null;
    _confirmed = false;
    _lastError = null;
    notifyListeners();
  }
}
