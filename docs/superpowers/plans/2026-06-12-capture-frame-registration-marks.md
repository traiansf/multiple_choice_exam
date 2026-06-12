# Capture-Frame Registration Marks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the four registration marks from the page corners to a *capture frame* bounding the answer area (full page width, y = 45–257 mm from the page top), so a photo of just that band is gradable.

**Architecture:** The capture frame becomes a shared-geometry concept mirrored in `render.py` (Python, PDF bottom-left mm) and `sheet_geometry.dart` (Dart, top-left mm). All image-space code in the grader (mark search, synthetic sheets, reference render, framing guide) switches its "the image is the page" assumption to "the image is the capture frame". The OMR's bilinear bubble mapper is untouched — it works in absolute mm against the detected mark quad.

**Tech Stack:** Python (reportlab, pytest), Dart/Flutter (`image` package, flutter_test), `pdftoppm` for the fixture.

**Spec:** `docs/superpowers/specs/2026-06-12-capture-frame-registration-marks-design.md`

**Key numbers** (top-left-origin mm unless said otherwise):

- Capture frame: x 0–210 (full width), y 45–257, height 212.
- Mark centers: (11, 56), (199, 56), (11, 246), (199, 246).
  In PDF bottom-left mm: y = 241 (top pair), y = 51 (bottom pair).
- Capture-relative mark centers: (11, 11), (199, 11), (11, 201), (199, 201).
- Content clearances: name baseline 48, QR bottom 50, column-letter baseline 64, lowest possible bubble edge 240.

## File map

| File | Change |
|---|---|
| `generator/src/mcexam/render.py` | capture-frame constants; new `registration_mark_positions()` |
| `generator/tests/test_render.py` | replace corner-marks test with bound-the-answer-area + clearance tests |
| `grader/lib/sheet_geometry.dart` | `captureTopMm`/`captureHeightMm`/`captureWidthMm`; new mark centers; capture-relative helper |
| `grader/test/sheet_geometry_test.dart` | new expected centers + capture-frame test |
| `grader/lib/omr.dart` | `_findRegistrationMarks` scales by capture frame |
| `grader/test/sheet_builder.dart` | builds capture-frame-sized images |
| `grader/lib/framing.dart` | guide aspect + targets from capture frame; hint copy |
| `grader/lib/sheet_guide_overlay.dart` | hint copy |
| `grader/test/framing_test.dart`, `grader/test/sheet_guide_overlay_test.dart` | updated expectations |
| `grader/lib/sheet_render.dart` | reference sheet renders the capture frame |
| `grader/lib/session.dart` | `_encodeScan` target width uses `captureWidthMm` |
| `grader/test/sheet_render_test.dart` | capture-frame expectations |
| `grader/test/fixtures/variant-001-page1.png` | regenerated from the new renderer |
| `grader/test/omr_fixture_test.dart` | crop page raster to the capture band before `detectMarks` |
| `README.md` | PDF anatomy wording |

---

### Task 1: Generator — marks bound the answer area

**Files:**
- Modify: `generator/src/mcexam/render.py:25-27` (constants) and `:70-77` (`registration_mark_positions`)
- Test: `generator/tests/test_render.py:45-48` (replace `test_four_registration_marks_at_corners`)

- [ ] **Step 1: Replace the corner-marks test with capture-frame tests**

In `generator/tests/test_render.py`, delete `test_four_registration_marks_at_corners` and add (the import line gains `REG_SIZE`; `mm` comes from reportlab):

```python
from reportlab.lib.units import mm

from mcexam.render import (
    GRID_LEFT,
    MARGIN,
    PAGE_H,
    PAGE_W,
    REG_SIZE,
    ROWS_PER_BLOCK,
    bubble_center,
    max_rows,
    registration_mark_positions,
    render_variant,
)
```

```python
def test_registration_marks_bound_the_answer_area() -> None:
    """Mark centers (PDF bottom-left mm): 11mm inset from the capture-frame
    edges — x at 11/199mm, y at 297-56=241mm (top pair) and 297-246=51mm
    (bottom pair). The capture frame is the band a sheet photo must cover."""
    positions = registration_mark_positions()
    assert len(positions) == 4
    centers = {(x + REG_SIZE / 2, y + REG_SIZE / 2) for x, y in positions}
    assert centers == {
        (11 * mm, 241 * mm),
        (PAGE_W - 11 * mm, 241 * mm),
        (11 * mm, 51 * mm),
        (PAGE_W - 11 * mm, 51 * mm),
    }


def test_registration_marks_clear_the_sheet_content() -> None:
    """The top mark band must sit between the header content (name line at
    48mm from top, QR bottom at 50mm) and the column letters (baseline 64mm
    from top, 9pt); the bottom band must sit below the lowest possible
    bubble. All in PDF bottom-left coordinates here."""
    positions = registration_mark_positions()
    top_band_low = min(y for _, y in positions if y > PAGE_H / 2)
    bottom_band_high = max(y + REG_SIZE for _, y in positions if y < PAGE_H / 2)
    from mcexam.render import BUBBLE_RADIUS, GRID_TOP, ROW_HEIGHT

    letters_ascender_top = GRID_TOP + 6 * mm + 9  # baseline + 9pt ascent bound
    assert top_band_low > letters_ascender_top
    name_descender_bottom = PAGE_H - 48 * mm - 3  # baseline - 12pt descent bound
    qr_bottom = PAGE_H - 22 * mm - 28 * mm
    top_band_high = top_band_low + REG_SIZE
    assert top_band_high < name_descender_bottom
    assert top_band_high < qr_bottom
    lowest_bubble_bottom = GRID_TOP - (ROWS_PER_BLOCK - 1) * ROW_HEIGHT - BUBBLE_RADIUS
    assert bottom_band_high < lowest_bubble_bottom
```

- [ ] **Step 2: Run the new tests, watch them fail**

Run: `cd generator && python -m pytest tests/test_render.py -q`
Expected: the two new tests FAIL (marks still at page corners: centers at 286mm/11mm don't match 241mm/51mm); everything else passes.

- [ ] **Step 3: Implement the new mark positions**

In `generator/src/mcexam/render.py` replace the registration-mark constants block (lines 25–27):

```python
# Registration marks bound the *capture frame*: the region a sheet photo
# must cover — the full page width, but only the vertical band around the
# bubble grid. Marks are inset REG_INSET from the capture-frame edges,
# mirroring grader/lib/sheet_geometry.dart (captureTopMm/captureHeightMm).
CAPTURE_TOP = 45 * mm  # capture-frame top, measured from the page top
CAPTURE_HEIGHT = 212 * mm
REG_INSET = 8 * mm
REG_SIZE = 6 * mm
```

and replace `registration_mark_positions()`:

```python
def registration_mark_positions() -> list[tuple[float, float]]:
    """Lower-left corners of the four marks bounding the answer area."""
    top_y = PAGE_H - CAPTURE_TOP - REG_INSET - REG_SIZE
    bottom_y = PAGE_H - CAPTURE_TOP - CAPTURE_HEIGHT + REG_INSET
    return [
        (REG_INSET, top_y),
        (PAGE_W - REG_INSET - REG_SIZE, top_y),
        (REG_INSET, bottom_y),
        (PAGE_W - REG_INSET - REG_SIZE, bottom_y),
    ]
```

(Sanity: top_y = 297−45−8−6 = 238 mm → center 241 mm; bottom_y = 297−45−212+8 = 48 mm → center 51 mm.)

- [ ] **Step 4: Run the full generator suite and lint**

Run: `cd generator && python -m pytest -q && ruff check . && ruff format --check .`
Expected: all pass. (`test_render_writes_pdf` etc. don't assert mark positions.)

- [ ] **Step 5: Commit**

```bash
git add generator/src/mcexam/render.py generator/tests/test_render.py
git commit -m "feat(generator): registration marks bound the answer area"
```

---

### Task 2: Dart geometry — capture-frame constants

**Files:**
- Modify: `grader/lib/sheet_geometry.dart:13-50`
- Test: `grader/test/sheet_geometry_test.dart:10-17`

- [ ] **Step 1: Update the geometry test**

In `grader/test/sheet_geometry_test.dart`, replace the `registration mark centers sit 11mm from each page corner` test with:

```dart
  test('registration mark centers bound the answer area', () {
    expect(geom.registrationMarkCentersMm(), [
      (x: 11.0, y: 56.0),
      (x: 199.0, y: 56.0),
      (x: 11.0, y: 246.0),
      (x: 199.0, y: 246.0),
    ]);
  });

  test('capture frame matches render.py CAPTURE_TOP/CAPTURE_HEIGHT', () {
    expect(geom.captureWidthMm, 210.0);
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
```

- [ ] **Step 2: Run it, watch it fail**

Run: `cd grader && flutter test test/sheet_geometry_test.dart`
Expected: FAIL — `captureWidthMm` etc. undefined (compile error), which is the missing-feature failure.

- [ ] **Step 3: Implement in `sheet_geometry.dart`**

Replace the registration-square comment + `regInsetMm`/`regSizeMm` block (lines 13–15) with:

```dart
/// Registration squares: inset from the *capture frame* edges, side length.
/// The capture frame is the region a sheet photo must cover: the full page
/// width, but only the vertical band around the bubble grid (render.py:
/// CAPTURE_TOP / CAPTURE_HEIGHT).
const double regInsetMm = 8;
const double regSizeMm = 6;
const double captureTopMm = 45;
const double captureHeightMm = 212;
const double captureWidthMm = pageWidthMm;
```

Replace `registrationMarkCentersMm()` (lines 38–50) with:

```dart
/// Centres of the four registration squares in page mm, top-left origin,
/// order [topLeft, topRight, bottomLeft, bottomRight]. They bound the
/// answer area: 11mm inset from the capture-frame edges.
List<({double x, double y})> registrationMarkCentersMm() {
  const near = regInsetMm + regSizeMm / 2; // 11mm
  const farX = pageWidthMm - near; // 199mm
  const topY = captureTopMm + near; // 56mm
  const bottomY = captureTopMm + captureHeightMm - near; // 246mm
  return const [
    (x: near, y: topY),
    (x: farX, y: topY),
    (x: near, y: bottomY),
    (x: farX, y: bottomY),
  ];
}

/// Mark centres relative to the capture frame — where they appear in a
/// correctly framed photo (image top-left = capture-frame top-left).
List<({double x, double y})> registrationMarkCentersInCaptureMm() => [
  for (final c in registrationMarkCentersMm()) (x: c.x, y: c.y - captureTopMm),
];
```

- [ ] **Step 4: Run the geometry test**

Run: `cd grader && flutter test test/sheet_geometry_test.dart`
Expected: PASS. (Other suites are now red until Tasks 3–6 — do NOT run the full suite yet.)

- [ ] **Step 5: Commit**

```bash
git add grader/lib/sheet_geometry.dart grader/test/sheet_geometry_test.dart
git commit -m "feat(grader): capture-frame constants and new mark centers"
```

---

### Task 3: OMR + synthetic sheets assume the capture frame

**Files:**
- Modify: `grader/test/sheet_builder.dart:16-36`
- Modify: `grader/lib/omr.dart:1-10` (doc comment), `:199-205` (`_findRegistrationMarks`)
- Test: `grader/test/omr_test.dart` (existing suite drives this)

- [ ] **Step 1: Make the synthetic sheet builder produce capture-frame images**

In `grader/test/sheet_builder.dart`: image dimensions become the capture frame, and all y coordinates become capture-relative.

```dart
/// Draws a synthetic capture-frame image (the band a correctly framed photo
/// covers): white canvas, black registration squares, bubble outlines, and
/// filled discs for the requested marks.
img.Image buildSheetImage({
  required int rows,
  required int optionsPerQuestion,
  double pxPerMm = 4,
  int numChannels = 3,
  Map<int, List<int>> filledByRow = const {},
  Map<int, double> fillRadiusMmByRow = const {},
  ({double x, double y}) offsetMm = (x: 0, y: 0),
  bool omitTopLeftMark = false,
}) {
  final image = img.Image(
    width: (geom.captureWidthMm * pxPerMm).round(),
    height: (geom.captureHeightMm * pxPerMm).round(),
    numChannels: numChannels,
  );
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);

  final markCenters = geom.registrationMarkCentersInCaptureMm();
  for (var i = 0; i < 4; i++) {
    if (i == 0 && omitTopLeftMark) continue;
    final c = markCenters[i];
    img.fillRect(
      image,
      x1: ((c.x + offsetMm.x - geom.regSizeMm / 2) * pxPerMm).round(),
      y1: ((c.y + offsetMm.y - geom.regSizeMm / 2) * pxPerMm).round(),
      x2: ((c.x + offsetMm.x + geom.regSizeMm / 2) * pxPerMm).round(),
      y2: ((c.y + offsetMm.y + geom.regSizeMm / 2) * pxPerMm).round(),
      color: black,
    );
  }

  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < optionsPerQuestion; col++) {
      final c = geom.bubbleCenterMm(row, col, optionsPerQuestion);
      final cx = ((c.x + offsetMm.x) * pxPerMm).round();
      final cy = ((c.y - geom.captureTopMm + offsetMm.y) * pxPerMm).round();
      // ... rest unchanged (drawCircle / fillCircle on cx, cy)
```

Only the lines shown change; the bubble draw/fill calls keep using `cx`/`cy`.

- [ ] **Step 2: Run the OMR suite, watch it fail**

Run: `cd grader && flutter test test/omr_test.dart`
Expected: FAIL — the builder now produces capture-frame images but `_findRegistrationMarks` still computes expected positions from page dimensions, so the search windows miss the marks ("registration mark not found").

- [ ] **Step 3: Point `_findRegistrationMarks` at the capture frame**

In `grader/lib/omr.dart`, in `_findRegistrationMarks` (line ~199), replace:

```dart
  final centers = geom.registrationMarkCentersMm();
  final scaleX = gray.width / geom.pageWidthMm;
  final scaleY = gray.height / geom.pageHeightMm;
```

with:

```dart
  // The input image is assumed to (roughly) frame the capture band — the
  // answer area bounded by the marks — not the whole page.
  final centers = geom.registrationMarkCentersInCaptureMm();
  final scaleX = gray.width / geom.captureWidthMm;
  final scaleY = gray.height / geom.captureHeightMm;
```

Also update the library doc comment at the top of `omr.dart`: where it says the image is the page, say the image is the capture frame (answer area). The px-per-mm estimate in `detectMarks` (lines 143–149) and `_BilinearMapper` need **no** change: mark spans in mm are frame-independent, and the mapper interpolates absolute mm against the detected quad.

- [ ] **Step 4: Run the OMR suite again**

Run: `cd grader && flutter test test/omr_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add grader/lib/omr.dart grader/test/sheet_builder.dart
git commit -m "feat(grader): OMR detects marks in the capture frame"
```

---

### Task 4: Framing guide and hint copy

**Files:**
- Modify: `grader/lib/framing.dart:13-49,116-135`
- Modify: `grader/lib/sheet_guide_overlay.dart:1-6,29-31,70`
- Test: `grader/test/framing_test.dart`, `grader/test/sheet_guide_overlay_test.dart`

- [ ] **Step 1: Update the framing tests**

In `grader/test/framing_test.dart`:

1. In the three `pageGuideRect` aspect assertions (lines 18, 30, 42) replace
   `geom.pageWidthMm / geom.pageHeightMm` with
   `geom.captureWidthMm / geom.captureHeightMm`.
2. Replace the `cornerMarkTargets` test body with:

```dart
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
```

3. In the `framingHintFor` group, the missing-corner test keeps `contains('top-left')` and `contains('bracket')` but add `expect(hint, contains('answer area'));`.

In `grader/test/sheet_guide_overlay_test.dart`, change both `find.textContaining('corner square')` matchers to `find.textContaining('black square')`.

- [ ] **Step 2: Run them, watch them fail**

Run: `cd grader && flutter test test/framing_test.dart test/sheet_guide_overlay_test.dart`
Expected: FAIL — guide aspect is still A4; targets still page-relative; hints still say "whole sheet"/"corner square".

- [ ] **Step 3: Implement in `framing.dart` and `sheet_guide_overlay.dart`**

`framing.dart`:

```dart
/// Largest capture-frame-aspect rectangle centred in [canvas], inset by
/// [marginFraction] of the shortest canvas side. The capture frame is the
/// answer area bounded by the printed marks — the photo target.
Rect pageGuideRect(Size canvas, {double marginFraction = 0.05}) {
  final margin = canvas.shortestSide * marginFraction;
  final availableW = canvas.width - 2 * margin;
  final availableH = canvas.height - 2 * margin;
  const aspect = geom.captureWidthMm / geom.captureHeightMm;
  // ... rest of the function unchanged
```

```dart
/// Where the four printed registration marks should appear inside [guide]
/// (same order as sheet_geometry: TL, TR, BL, BR). Each target square is
/// twice the printed mark size, giving the user alignment tolerance.
List<Rect> cornerMarkTargets(Rect guide) {
  final scaleX = guide.width / geom.captureWidthMm;
  final scaleY = guide.height / geom.captureHeightMm;
  return [
    for (final c in geom.registrationMarkCentersInCaptureMm())
      Rect.fromCenter(
        center: Offset(guide.left + c.x * scaleX, guide.top + c.y * scaleY),
        width: 2 * geom.regSizeMm * scaleX,
        height: 2 * geom.regSizeMm * scaleY,
      ),
  ];
}
```

In `framingHintFor`, the mark-not-found branch becomes:

```dart
      return 'The ${corner ?? 'corner'} alignment square was not found.'
          ' Fit the answer area inside the frame, with each black'
          ' square inside its bracket.';
```

Also update the `cropToGuideFraction` doc comment ("the image is (roughly) the page" → "the capture frame") and the library doc comment ("A4 guide rectangle" → "answer-area guide rectangle").

`sheet_guide_overlay.dart`: default hint becomes

```dart
              hint ??
                  'Hold the phone flat above the sheet. Fit the answer area'
                      ' in the frame and put each black square in its'
                      ' bracket.',
```

and the library doc comment's "A4 page frame" → "answer-area frame".

- [ ] **Step 4: Run the two suites again**

Run: `cd grader && flutter test test/framing_test.dart test/sheet_guide_overlay_test.dart`
Expected: PASS (the end-to-end crop test in framing_test composites the capture-frame builder image into a photo at the guide rect — aspects now agree).

- [ ] **Step 5: Commit**

```bash
git add grader/lib/framing.dart grader/lib/sheet_guide_overlay.dart grader/test/framing_test.dart grader/test/sheet_guide_overlay_test.dart
git commit -m "feat(grader): framing guide targets the answer area"
```

---

### Task 5: Reference sheet and scan comparison on the capture frame

**Files:**
- Modify: `grader/lib/sheet_render.dart:14-38,66-92`
- Modify: `grader/lib/session.dart:286`
- Test: `grader/test/sheet_render_test.dart:20-31`

- [ ] **Step 1: Update the render test**

In `grader/test/sheet_render_test.dart`:

1. Rename the aspect test and change its expectations:

```dart
  test('reference sheet has capture-frame aspect at the requested resolution',
      () {
    final sheet = renderReferenceSheet(
      correctPositions: correctPositions,
      optionsPerQuestion: 4,
      pxPerMm: 3,
    );
    expect(sheet.width, (geom.captureWidthMm * 3).round());
    expect(sheet.height, (geom.captureHeightMm * 3).round());
  });
```

2. In the `stripHasRed` helper, change the inner-loop y bounds to capture-relative:

```dart
      for (
        var y = ((first.y - geom.captureTopMm - 3) * pxPerMm).round();
        y <= ((first.y - geom.captureTopMm + 3) * pxPerMm).round();
        y++
      ) {
```

(`pxPerMm = sheet.width / geom.pageWidthMm` still holds since capture width = page width; leave it or switch to `captureWidthMm` — same value.)

- [ ] **Step 2: Run it, watch it fail**

Run: `cd grader && flutter test test/sheet_render_test.dart`
Expected: FAIL — height is still page-sized, round-trip tests throw "registration mark not found" (page-framed render, capture-framed detector).

- [ ] **Step 3: Implement in `sheet_render.dart` and `session.dart`**

`renderReferenceSheet`: image dims and y coordinates become capture-relative:

```dart
  final sheet = img.Image(
    width: (geom.captureWidthMm * pxPerMm).round(),
    height: (geom.captureHeightMm * pxPerMm).round(),
  );
  img.fill(sheet, color: img.ColorRgb8(255, 255, 255));
  final black = img.ColorRgb8(0, 0, 0);

  for (final center in geom.registrationMarkCentersInCaptureMm()) {
    // fillRect call unchanged — center.y is already capture-relative
  }

  for (var row = 0; row < correctPositions.length; row++) {
    for (var col = 0; col < optionsPerQuestion; col++) {
      final center = geom.bubbleCenterMm(row, col, optionsPerQuestion);
      final cx = (center.x * pxPerMm).round();
      final cy = ((center.y - geom.captureTopMm) * pxPerMm).round();
      // drawCircle / fillCircle unchanged
```

`annotateWrongRows`: y coordinates become capture-relative (x and pxPerMm unchanged):

```dart
  final pxPerMm = sheet.width / geom.captureWidthMm;
  ...
    img.drawRect(
      sheet,
      x1: ((first.x - 6) * pxPerMm).round(),
      y1: ((first.y - geom.captureTopMm - geom.rowHeightMm / 2 * 0.9) * pxPerMm)
          .round(),
      x2: ((last.x + 6) * pxPerMm).round(),
      y2: ((first.y - geom.captureTopMm + geom.rowHeightMm / 2 * 0.9) * pxPerMm)
          .round(),
```

Update the library doc comment: the rendered image is the capture frame (matches the scanned crop it sits beside). `annotateWrongRows` is also applied to the scanned crop in `session.dart` — that image is capture-framed too, so one convention serves both.

`session.dart:286`: `geom.pageWidthMm` → `geom.captureWidthMm` (same value; keeps the image-space code uniformly capture-frame).

- [ ] **Step 4: Run render + session + omr-integration suites**

Run: `cd grader && flutter test test/sheet_render_test.dart test/session_test.dart test/omr_grading_integration_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add grader/lib/sheet_render.dart grader/lib/session.dart grader/test/sheet_render_test.dart
git commit -m "feat(grader): reference sheet and scan comparison use the capture frame"
```

---

### Task 6: Regenerate the real-render fixture; crop it in the fixture test

**Files:**
- Regenerate: `grader/test/fixtures/variant-001-page1.png`
- Modify: `grader/test/omr_fixture_test.dart`

- [ ] **Step 1: Update the fixture test to crop to the capture band**

In `grader/test/omr_fixture_test.dart` add a helper above `main()`:

```dart
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
```

Then:

1. Test `detects marks stamped onto the real rendered sheet`: keep loading and stamping on the full page in absolute mm (unchanged), then call `detectMarks(cropToCapture(sheet), ...)` instead of `detectMarks(sheet, ...)`.
2. Test `unstamped real sheet reads as fully blank`: `detectMarks(cropToCapture(sheet), ...)`.
3. Test `printed geometry on the real PNG matches sheet_geometry (anchor)`: **unchanged** — it measures printed ink at absolute page positions, and `registrationMarkCentersMm()` now returns the new positions, so it anchors the new layout automatically.
4. Update the file doc comment to mention the crop step.

- [ ] **Step 2: Run the fixture suite, watch it fail**

Run: `cd grader && flutter test test/omr_fixture_test.dart`
Expected: FAIL — the checked-in PNG still has corner marks: the anchor test finds no ink at the new mark positions (`count > 0` fails or centroid is off), and detection on the crop fails.

- [ ] **Step 3: Regenerate the fixture from the new renderer**

```bash
cd generator && pip install -e . -q && cd ..
mcexam generate --input examples/sample-exam.md --variants 1 \
    --questions 10 --base-seed 7 --out /tmp/omr-fix
pdftoppm -png -r 150 -f 1 -l 1 /tmp/omr-fix/variant-001.pdf \
    grader/test/fixtures/variant-001-page1
```

(If the output lands as `variant-001-page1-1.png`, rename it to `variant-001-page1.png` — pdftoppm suffixes page numbers on some versions.)

- [ ] **Step 4: Run the fixture suite again**

Run: `cd grader && flutter test test/omr_fixture_test.dart`
Expected: PASS — printed marks found at the new positions with <0.7mm error; stamped/blank detection works on the cropped band.

- [ ] **Step 5: Commit**

```bash
git add grader/test/omr_fixture_test.dart grader/test/fixtures/variant-001-page1.png
git commit -m "test(grader): fixture regenerated for answer-area marks; crop to capture band"
```

---

### Task 7: Documentation

**Files:**
- Modify: `README.md` (PDF anatomy section, ~line 249)

- [ ] **Step 1: Update README "PDF anatomy"**

Replace the registration-mark sentence in the PDF-anatomy paragraph: the marks are no longer "corner" marks of the page. New wording for the relevant part:

```markdown
fixed **OMR bubble grid** (one row per question, `M` bubbles per row);
**registration marks** bounding the answer area — full page width, only the
band around the grid — so the grading camera needs to frame only that band
(not the whole page, keeping the student name and QR out of the graded
photo); and the **QR code**.
```

Also scan README for other "corner" references to the marks (`grep -n "corner" README.md`) and fix any that describe the printed sheet.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: registration marks bound the answer area"
```

---

### Task 8: Full verification

- [ ] **Step 1: Generator suite**

Run: `cd generator && python -m pytest -q && ruff check . && ruff format --check .`
Expected: all pass, no lint issues.

- [ ] **Step 2: Grader suite**

Run: `cd grader && flutter test && flutter analyze`
Expected: all tests pass (including widget/session suites not touched directly), analyzer clean.

- [ ] **Step 3: Manual sanity render**

```bash
mcexam generate --input examples/sample-exam.md --variants 1 \
    --questions 10 --base-seed 7 --out /tmp/capture-check
```

Open `/tmp/capture-check/variant-001.pdf` and eyeball page 1: four marks bounding the grid band (none at the page corners), no overlap with the name line, QR, column letters, or bubbles.

- [ ] **Step 4: Push and open the PR**

```bash
git push -u origin feat/capture-frame-registration-marks
gh pr create --title "feat: registration marks bound the answer area (capture frame)" --body "..."
```

PR body should summarize: what moved and why, the capture-frame concept, both-suite verification evidence, and that the fixture PNG was regenerated. End the body with the standard generated-with footer.
