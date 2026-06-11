# Grader OMR Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `grader/lib/omr.dart` — detect the four registration marks in an answer-sheet image, map the printed bubble grid onto it, sample each bubble's fill, classify rows (marked / blank / needs-review), tested against synthetic images AND a real page rasterized from the Python renderer.

**Architecture:** Two new modules. `sheet_geometry.dart` holds the printed-layout constants in mm, top-left origin — a 1:1 mirror of `render.py`'s geometry (a new cross-component contract, to be recorded in CLAUDE.md). `omr.dart` does detection only: corner-window centroid search for registration marks, bilinear mm→px mapping over the detected quad (absorbs translation/scale/mild skew), interior disc sampling per bubble, threshold classification. Ambiguous or multi-marked rows are flagged for review, never guessed. Assumes the image is roughly the cropped page (flatbed scan / deskewed photo); perspective correction belongs to the camera milestone.

**Tech Stack:** `package:image` (pure Dart) added as a dependency; `flutter_test`.

**Branch:** `feat/grader-omr`. Fixture: `grader/test/fixtures/variant-001-page1.png` generated from the real generator output (`mcexam generate --base-seed 7 --questions 10` → `pdftoppm -r 150`).

**Geometry derivation (from render.py, PDF bottom-left → image top-left mm):**
- Reg mark centers: inset 8mm + size 6mm → centers at 11mm from each edge: TL(11,11), TR(199,11), BL(11,286), BR(199,286).
- `GRID_TOP = PAGE_H − 70mm` → row 0 center at 70mm from top; row r in block: y = 70 + (r%25)·7.
- x = 25 + block·blockWidth(M) + 10 + (col+0.5)·8, blockWidth(M) = 10 + 8M + 12.
- Spot values for tests (M=4): bubble(0,0)=(39,70), bubble(0,3)=(63,70), bubble(1,0)=(39,77), bubble(25,0)=(93,70), blockWidth=54.

---

### Task 1: Branch + dependency

- [ ] `git checkout -b feat/grader-omr`
- [ ] `cd grader && $HOME/development/flutter/bin/flutter pub add image`
- [ ] Commit `chore: add image package for OMR`.

### Task 2: `lib/sheet_geometry.dart` (TDD)

Test `test/sheet_geometry_test.dart` with the hand-derived spot values above (reg centers, the four bubble positions, block width). Implementation: constants + `blockWidthMm`, `registrationMarkCentersMm()`, `bubbleCenterMm(row, col, m)` as derived. Doc comment states it mirrors render.py and both must change together. Commit `feat: sheet geometry (mirror of render.py layout contract)`.

### Task 3: `lib/omr.dart` + synthetic-image tests (TDD)

Test helper `buildSheetImage(...)` draws a synthetic page with `package:image`: white canvas at `pxPerMm`, black reg squares (optionally omitting one, optionally offset by a few mm), bubble outline circles, filled discs for chosen (row, col) marks (optionally with a smaller radius to create ambiguity).

Tests:
1. Clean sheet (10 rows, M=4, mark col = row%4) → all `RowStatus.marked`, `marks` correct, `needsReview` false.
2. A row with no fill → `mark == null`, `RowStatus.blank`.
3. A double-marked row → `RowStatus.needsReview`, `reviewRows` contains its 1-based number, mark null.
4. A faint/partial fill (0.8mm disc inside a 2mm bubble) → ambiguous → `needsReview`.
5. Whole page offset by 3mm → still detected correctly (bilinear mapping absorbs it).
6. Different resolution (3 px/mm vs 4) → still correct.
7. Missing top-left reg mark → `OmrException` naming the corner.

Implementation as designed in the architecture note: `OmrConfig` thresholds (darkLuma 128, filledMin 0.45, emptyMax 0.20, cornerWindowFraction 0.06, sampleRadiusFactor 0.7), `_findRegistrationMarks` (centroid of dark pixels in each corner window, minimum-area guard), `_BilinearMapper`, `_darkFraction` interior disc sampling, `_classifyRow`. Commit `feat: OMR detection (registration marks, grid mapping, bubble classification)`.

### Task 4: Real-renderer fixture test

- [ ] Generate fixture: `mcexam generate --input examples/sample-exam.md --variants 1 --questions 10 --base-seed 7 --out /tmp/omr-fix && pdftoppm -png -r 150 -f 1 -l 1 /tmp/omr-fix/variant-001.pdf grader/test/fixtures/variant-001-page1` (document the command in the test).
- [ ] Test: load the PNG, stamp filled discs at bubble centers (row%4) using `width/210` as px-per-mm, run `detectMarks`, assert all 10 marks and no review flags. This closes the loop: render.py geometry → real PDF → raster → Dart geometry + detection.
- [ ] Commit `test: OMR fixture from the real generator rendering`.

### Task 5: CLAUDE.md contract note + final verification

- [ ] Add to CLAUDE.md "Single sources of truth": sheet geometry → `render.py` (draw) and `grader/lib/sheet_geometry.dart` (read).
- [ ] `flutter test`, `flutter analyze`, `dart format`; generator pytest sanity.
- [ ] Push, open PR (summary + limitation: assumes page-cropped, roughly axis-aligned input; perspective handling arrives with the camera milestone).
