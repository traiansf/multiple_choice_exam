# Grader Visual Scoring Confirmation (issue #5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After grading a sheet, show a side-by-side comparison — a generated reference sheet with the correct answers filled vs the actual scanned sheet, scaled to match, with wrongly-answered rows outlined in red on both — plus the detected score, and require the user to confirm the scoring before moving on (the confirm hook is where issue #4's recording will attach).

**Architecture:** (1) `lib/sheet_render.dart` — pure: `renderReferenceSheet` draws a synthetic page (registration marks, bubble grid, correct answers filled) from `sheet_geometry`; `annotateWrongRows` draws red row outlines on any page image. Tested by feeding the rendered reference back through `detectMarks` (dogfooding) and by pixel checks. (2) `GraderSession` keeps the scanned page image, builds both annotated PNGs when a sheet grades cleanly, and gains `confirmed` + `confirmResult()` (StateError unless a grade exists; reset by retake/next/QR/key). (3) `ResultScreen._GradeView` shows the labeled side-by-side images above the per-question list; the primary button becomes "Confirm — next sheet" (confirm + next), Retake remains the reject path. needsReview keeps the existing notice — no comparison, no confirm.

**Branch:** `feat/grader-confirmation`.

---

### Task 1: `lib/sheet_render.dart` (TDD)

Tests:
- `renderReferenceSheet` round-trips through `detectMarks`: marks == correctPositions, no review flags (the strongest possible check — the reference must be a valid sheet by our own detector).
- Page has A4 aspect at the requested pxPerMm.
- `annotateWrongRows`: red pixels appear inside the wrong row's strip (sample the rect border at the row's y), none on a correct row's strip; original bubbles unchanged (detectMarks still returns the same marks after annotation — red outline stays outside the bubbles).

Implementation: white page, four `fillRect` registration marks, bubble outlines per row/col, `fillCircle` at each row's correct position (all positions from `sheet_geometry`); `annotateWrongRows` derives pxPerMm from image width and draws a red `drawRect` outline spanning the row's bubble strip (from first bubble center − 6mm to last + 6mm, ± 3.2mm vertically).

### Task 2: session additions (TDD)

- Store the page image on success; build `referenceSheetPng` / `scannedSheetPng` (both annotated with the wrong rows, PNG-encoded) only when a grade exists; null while needsReview.
- `confirmed` getter + `confirmResult()` (StateError when `gradeResult == null`); cleared by `retakeSheet`, `nextSheet`, `setQr`, `loadKey`.

Tests: graded sheet → both PNGs non-null and start with PNG magic; review sheet → both null; confirm lifecycle (false → confirm → true → nextSheet → false); confirmResult without a grade throws; retake clears PNGs.

### Task 3: ResultScreen comparison + confirm (widget tests)

- `_GradeView`: under the score, a labeled Row — "Correct answers" `Image.memory(referenceSheetPng)` | "Scanned sheet" `Image.memory(scannedSheetPng)` — fixed height, equal flex (same A4 aspect ⇒ scaled to match); per-question list below.
- Bottom bar: Retake (unchanged) + "Confirm — next sheet" (calls `confirmResult()` then `nextSheet()`, pops 'next'). Review state unchanged.
- Update existing widget tests for the renamed button; new tests: two images render when graded; no images on review; confirm button leaves session confirmed-then-reset at needQr.

### Task 4: Verify + PR

`dart format`, `flutter analyze`, full `flutter test`, generator pytest sanity; push; PR referencing issue #5 (confirm gate is where #4 recording will hook).
