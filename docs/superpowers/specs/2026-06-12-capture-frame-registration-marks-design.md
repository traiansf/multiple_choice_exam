# Capture frame: registration marks bound the answer area

**Date:** 2026-06-12
**Status:** approved design, pre-implementation

## Problem

The four registration marks sit at the page corners, so a gradable photo must
frame the entire A4 page even though the bubble grid occupies only the band
between ~70 mm and ~240 mm from the page top. Framing the whole page is
awkward, wastes camera resolution on regions the OMR never reads, and
includes more of the sheet header in every graded photo than necessary.

## Goal

The photo only needs to cover the **answer area**: full page width, but not
the full height. The marks move to bound that region; the grader's framing
guide, crop, and mark detection follow.

Non-goals: supporting previously printed sheets (none exist in the wild);
adapting mark positions to the actual question count (geometry stays fixed
per the contract); any change to RNG, QR payload, or `answer-key.json`.

## Design

### 1. The capture frame (new shared-geometry concept)

The *capture frame* is the region a sheet photo must cover:

- x: the full page width, 0–210 mm.
- y: **45 mm to 257 mm** from the page top (height **212 mm**).
- Aspect ≈ 210/212 ≈ 0.99 — a near-square camera target.

The four registration marks keep their size (6 mm squares) and their 11 mm
center inset, measured from the **capture-frame** edges instead of the page
edges:

| Mark | center x (mm) | center y from page top (mm) |
|------|---------------|------------------------------|
| top-left | 11 | 56 |
| top-right | 199 | 56 |
| bottom-left | 11 | 246 |
| bottom-right | 199 | 246 |

Printed-sheet clearances (top-left-origin mm, from current `render.py`
content):

- Top mark band spans 53–59 mm: ~5 mm below the name-line baseline (48 mm;
  the name line sits at the band's top edge, so descenders may appear at the
  very top of the photo); QR fully above the band (page-y 16..44 mm, ends 1 mm
  above the band top); ~2.8 mm above the column-letter ascenders (≈62 mm,
  baseline 64 mm).
- Bottom mark band spans 243–249 mm: 3 mm below the lowest possible bubble
  edge (240 mm; row 24 center at 238 mm).

The OMR's coarse-centroid + mark-sized-refinement detection already tolerates
stray ink near the search window; the real-render fixture test (below) proves
the clearances suffice.

### 2. Generator (`generator/src/mcexam/render.py`)

`registration_mark_positions()` returns the new positions. In PDF
bottom-left coordinates the mark centers sit at y = 241 mm (top pair) and
y = 51 mm (bottom pair); x insets are unchanged. Express the positions via
named capture-frame constants (`CAPTURE_TOP_MM`, `CAPTURE_HEIGHT_MM`) so the
Python and Dart constants mirror each other 1:1.

The QR was also moved (from page-y 22 mm to 16 mm) so it ends fully above
the capture band. Everything else on the answer sheet is unchanged. Question
pages carry no marks and are unaffected.

### 3. Grader

- **`lib/sheet_geometry.dart`** — add `captureTopMm = 45` and
  `captureHeightMm = 212` (capture left = 0, width = page width).
  `registrationMarkCentersMm()` returns the new absolute-page-mm centers.
  Add `registrationMarkCentersInCaptureFrameMm()` (or equivalent) for
  image-space consumers: same centers with `captureTopMm` subtracted from y.
- **`lib/omr.dart`** — `_findRegistrationMarks` scales expected mark
  positions by capture-frame dimensions instead of page dimensions. The
  input-image assumption becomes **image ≈ capture frame** (was: image ≈
  page). The bilinear bubble mapper is untouched: it maps absolute mm
  against the detected quad, which is position-independent.
- **`lib/framing.dart`** — `pageGuideRect` uses the capture-frame aspect;
  `cornerMarkTargets` scales mark targets against the capture frame;
  `cropToGuideFraction` is unchanged (it crops to whatever the guide
  framed, which is now the capture frame). Rename/adjust doc comments that
  say "A4 page" to "answer area".
- **`lib/sheet_guide_overlay.dart`** — hint copy changes from "fit the
  whole sheet" to fitting the answer area between the four squares; same
  for `framingHintFor` messages in `framing.dart`.

### 4. Tests

- **Python** — replace `test_four_registration_marks_at_corners` with
  assertions that the four marks bound the grid band: x insets at full
  width, top band below the QR/name content, bottom band below the lowest
  possible bubble row, all four inside the page.
- **Dart unit tests** — update geometry expectations (mark centers, guide
  aspect, corner targets).
- **Fixture** — regenerate `grader/test/fixtures/variant-001-page1.png`
  from the new renderer using the command documented in
  `omr_fixture_test.dart`. The fixture test now crops the full-page raster
  to the capture band before calling `detectMarks`, mirroring the
  production `cropToGuideFraction` path.
- **Round-trip / synthetic-sheet tests** — pick up the new geometry
  automatically through the shared constants; assert they still pass.

### 5. Documentation

- README "PDF anatomy": corner registration marks → marks bounding the
  answer area; mention the capture frame (photo needs only the marked
  band).
- The CLAUDE.md geometry-contract bullet stays accurate as written
  (render.py ↔ sheet_geometry.dart change together); no edit needed unless
  wording references "corners".

## Compatibility

Breaking for any previously printed sheet — accepted: nothing is in the
wild. No fallback detection path. The QR payload version is **not** bumped:
it versions the RNG/selection algorithm, which is unchanged; old PDFs are
not expected to exist.

## Error handling

Unchanged in structure: mark-not-found and low-resolution errors keep
flagging for manual review / re-framing. The "registration mark not found"
hint text changes to direct the user to frame the answer area.

## Verified benefit (honest accounting)

- Px/mm gain in a 3:4 portrait photo is modest (~6%) because the frame is
  still full page width.
- Real wins: a near-square, smaller framing target; the title, variant number,
  and QR are fully above the band and stay out of graded photos; the name line
  sits at the band's top edge (its lower pixels may appear at the very top of
  the photo); a tighter registration quad around the bubbles reduces
  lens/perspective error where bubbles are sampled.
