import 'package:flutter_test/flutter_test.dart';
import 'package:grader/omr.dart';
import 'package:image/image.dart' as img;

import 'sheet_builder.dart';

void main() {
  Map<int, List<int>> cleanMarks(int rows) => {
    for (var row = 0; row < rows; row++) row: [row % 4],
  };

  test('clean sheet: every row detected with the marked column', () {
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      filledByRow: cleanMarks(10),
    );
    final result = detectMarks(sheet, rows: 10, optionsPerQuestion: 4);
    expect(result.needsReview, isFalse);
    expect(result.marks, [for (var r = 0; r < 10; r++) r % 4]);
    expect(result.rows.every((r) => r.status == RowStatus.marked), isTrue);
  });

  test('row without any fill is blank, not flagged', () {
    final marks = cleanMarks(10)..remove(3);
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      filledByRow: marks,
    );
    final result = detectMarks(sheet, rows: 10, optionsPerQuestion: 4);
    expect(result.rows[3].status, RowStatus.blank);
    expect(result.marks[3], isNull);
    expect(result.needsReview, isFalse);
  });

  test('double-marked row is flagged for review', () {
    final marks = cleanMarks(10)..[5] = [1, 2];
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      filledByRow: marks,
    );
    final result = detectMarks(sheet, rows: 10, optionsPerQuestion: 4);
    expect(result.rows[5].status, RowStatus.needsReview);
    expect(result.marks[5], isNull);
    expect(result.needsReview, isTrue);
    expect(result.reviewRows, [6]);
  });

  test('faint partial fill is ambiguous and flagged for review', () {
    final marks = cleanMarks(10);
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      filledByRow: marks,
      fillRadiusMmByRow: {7: 0.8}, // small blob inside the 2mm bubble
    );
    final result = detectMarks(sheet, rows: 10, optionsPerQuestion: 4);
    expect(result.rows[7].status, RowStatus.needsReview);
    expect(result.reviewRows, [8]);
  });

  test('page content offset by 3mm is still detected correctly', () {
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      filledByRow: cleanMarks(10),
      offsetMm: (x: 3, y: 3),
    );
    final result = detectMarks(sheet, rows: 10, optionsPerQuestion: 4);
    expect(result.needsReview, isFalse);
    expect(result.marks, [for (var r = 0; r < 10; r++) r % 4]);
  });

  test('works at a different resolution (3 px/mm)', () {
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      pxPerMm: 3,
      filledByRow: cleanMarks(10),
    );
    final result = detectMarks(sheet, rows: 10, optionsPerQuestion: 4);
    expect(result.marks, [for (var r = 0; r < 10; r++) r % 4]);
  });

  test('second bubble block (row >= 25) is sampled at the shifted x', () {
    final marks = cleanMarks(30);
    final sheet = buildSheetImage(
      rows: 30,
      optionsPerQuestion: 4,
      filledByRow: marks,
    );
    final result = detectMarks(sheet, rows: 30, optionsPerQuestion: 4);
    expect(result.needsReview, isFalse);
    expect(result.marks, [for (var r = 0; r < 30; r++) r % 4]);
  });

  test('pre-grayscale single-channel input works', () {
    final sheet = buildSheetImage(
      rows: 5,
      optionsPerQuestion: 4,
      numChannels: 1,
      filledByRow: cleanMarks(5),
    );
    expect(sheet.numChannels, 1);
    final result = detectMarks(sheet, rows: 5, optionsPerQuestion: 4);
    expect(result.marks, [0, 1, 2, 3, 0]);
  });

  test('marksForGrading throws while any row needs review', () {
    final marks = cleanMarks(10)..[5] = [1, 2];
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      filledByRow: marks,
    );
    final result = detectMarks(sheet, rows: 10, optionsPerQuestion: 4);
    expect(
      () => result.marksForGrading,
      throwsA(
        isA<OmrException>().having(
          (e) => e.message,
          'message',
          contains('[6]'),
        ),
      ),
    );
  });

  test('custom thresholds change the classification boundary', () {
    // A 0.8mm blob is ambiguous under the defaults (see test above); with a
    // permissive filledMin it classifies as a confident mark.
    final sheet = buildSheetImage(
      rows: 2,
      optionsPerQuestion: 4,
      filledByRow: {
        0: [1],
        1: [2],
      },
      fillRadiusMmByRow: {0: 0.8},
    );
    final result = detectMarks(
      sheet,
      rows: 2,
      optionsPerQuestion: 4,
      config: const OmrConfig(filledMin: 0.20, emptyMax: 0.05),
    );
    expect(result.rows[0].status, RowStatus.marked);
    expect(result.marks[0], 1);
  });

  test('rows beyond the sheet capacity are rejected', () {
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      filledByRow: cleanMarks(10),
    );
    expect(
      () => detectMarks(sheet, rows: 76, optionsPerQuestion: 4),
      throwsA(
        isA<OmrException>().having(
          (e) => e.message,
          'message',
          contains('capacity'),
        ),
      ),
    );
  });

  test('too-low resolution is rejected with a clear message', () {
    final sheet = buildSheetImage(
      rows: 2,
      optionsPerQuestion: 4,
      pxPerMm: 1,
      filledByRow: cleanMarks(2),
    );
    expect(
      () => detectMarks(sheet, rows: 2, optionsPerQuestion: 4),
      throwsA(
        isA<OmrException>().having(
          (e) => e.message,
          'message',
          contains('resolution'),
        ),
      ),
    );
  });

  test('inverted image fails safe: flagged for review, never marked', () {
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      filledByRow: cleanMarks(10),
    );
    img.invert(sheet);
    final result = detectMarks(sheet, rows: 10, optionsPerQuestion: 4);
    expect(result.needsReview, isTrue);
    expect(result.rows.every((r) => r.status != RowStatus.marked), isTrue);
  });

  test('marks detected despite header ink near the top windows and offset', () {
    // The name-line stripe (x 8..90mm, capture-y 2.5..4.25mm, 1.75mm tall)
    // places ~376 dark pixels inside the TL coarse window at y≈3.4mm, biasing
    // the coarse centroid ~2.9mm above the true mark centre (y=11mm).
    // Without refinement the TL corner is detected at y≈8mm, shifting the
    // sampled bubble row 0 by ~2mm and dropping the fill ratio to ≈0.41,
    // which is below the 0.45 filled threshold → the row would be classified as
    // ambiguous/blank, failing the test.  With refinement the fine window
    // (±5.4mm around the biased coarse at y≈8mm) still captures most of the
    // mark; the mark's ~600-px mass outweighs the ~273-px ink overlap in the
    // fine window, pulling the fine centroid to y≈8.5mm → bubble error ≈1.7mm
    // → fill ratio ≈0.54 → correctly marked.
    // See buildSheetImage doc for the full geometry derivation.
    final sheet = buildSheetImage(
      rows: 5,
      optionsPerQuestion: 4,
      filledByRow: {0: [2]},
      drawHeaderInk: true,
    );
    final result = detectMarks(sheet, rows: 5, optionsPerQuestion: 4);
    expect(result.rows[0].mark, 2);
    expect(result.rows[0].status, RowStatus.marked);
  });

  test('missing registration mark raises a corner-naming error', () {
    final sheet = buildSheetImage(
      rows: 10,
      optionsPerQuestion: 4,
      filledByRow: cleanMarks(10),
      omitTopLeftMark: true,
    );
    expect(
      () => detectMarks(sheet, rows: 10, optionsPerQuestion: 4),
      throwsA(
        isA<OmrException>().having(
          (e) => e.message,
          'message',
          contains('top-left'),
        ),
      ),
    );
  });
}
