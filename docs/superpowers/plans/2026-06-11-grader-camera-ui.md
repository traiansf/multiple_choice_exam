# Grader Camera UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The grading flow in the app — load `answer-key.json`, scan the QR, capture the bubble sheet with **on-screen framing guides** (A4 frame, corner-mark brackets, actionable hints), run OMR, grade, show the result — with all camera-independent logic pure and unit-tested.

**Architecture:** Three layers. (1) `framing.dart` — pure geometry/image helpers: A4 guide rect, corner-mark targets (positions derived from `sheet_geometry`), crop-to-guide, exposure check, OmrException→hint mapping. (2) `session.dart` — `GraderSession` ChangeNotifier state machine (needKey → needQr → needSheet → result), early fingerprint rejection at QR time, OMR+grade orchestration, reset-on-new-key. (3) Thin screens: `scan_qr_screen.dart` (mobile_scanner), `capture_sheet_screen.dart` (camera + `SheetGuideOverlay` painter), `result_screen.dart`, rewritten `main.dart` home (file_selector key loading). Camera/scanner screens are excluded from widget tests (plugin channels); everything else is tested.

**Tech Stack:** `mobile_scanner` (QR, per CLAUDE.md convention), `camera` (sheet capture), `file_selector` (key file), existing `image`.

**Branch:** `feat/grader-camera-ui`.

**Framing-guide design (the user's explicit ask):**
- Camera preview dimmed outside a centered A4-portrait rectangle (aspect 210:297) with a white border.
- Four bracket squares at the registration-mark positions (relative centers 11/210 and 11/297 from the guide edges, sized 2× the printed 6mm mark for tolerance) — "put each black corner square in its bracket".
- Persistent hint line ("Hold the phone flat above the sheet; fill the frame; avoid shadows").
- After capture: crop to the guide rect (so OMR's image≈page assumption holds), exposure gate ("too dark"/"washed out"), then OMR; an `OmrException` maps to a specific retake hint (which corner is missing, "move closer" for low resolution).

---

### Task 1: Branch + dependencies + permissions

- `git checkout -b feat/grader-camera-ui`
- `flutter pub add mobile_scanner camera file_selector`
- AndroidManifest.xml: `<uses-permission android:name="android.permission.CAMERA"/>`; Info.plist: `NSCameraUsageDescription`.
- Commit.

### Task 2: `lib/framing.dart` (TDD)

Pure helpers; full test list:
- `pageGuideRect(Size)`: A4 aspect (210/297), centered, inset by 5% of shortest side; portrait and landscape canvases.
- `cornerMarkTargets(Rect)`: 4 rects, centers at the registration-mark relative positions (TL target center = guide.topLeft + (11/210·w, 11/297·h)), each 2× regSize scaled.
- `guideAsFraction(Rect, Size)` and `cropToGuideFraction(img.Image, Rect)`: cropping a synthetic photo (page drawn inside a larger gray background at the guide position) yields an image OMR detects correctly end-to-end.
- `exposureHint(img.Image)`: dark image → "too dark" hint; washed-out → "washed out"; a normal synthetic sheet → null.
- `framingHintFor(error)`: corner-not-found OmrException → message naming the corner + bracket instruction; resolution OmrException → "move closer"; unknown error → generic hold-flat hint.

### Task 3: `lib/session.dart` (TDD)

`GraderSession extends ChangeNotifier`:
- `stage`: needKey (no key) → needQr (no payload) → needSheet → result (gradeResult set, or OmrResult flagged needsReview).
- `loadKey(String json) -> bool`: parse; on success **resets payload/omr/gradeResult** (new exam; recorded-grades reset hook for issue #4 lands here later); on KeyfileFormatException sets `lastError`.
- `setQr(String raw) -> bool`: decode; reject fingerprint mismatch ("different exam source") and counts exceeding key sections **at scan time**; resets sheet state.
- `processSheet(img.Image page) -> bool`: exposure gate → `detectMarks` (rows = counts sum, M from key) → needsReview ⇒ result stage exposing `reviewRows`; else `grading.grade(...)` with `marksForGrading`. OmrException → `lastError = framingHintFor(e)`, stays needSheet.
- `retakeSheet()`, `nextSheet()` (clears payload+sheet, back to needQr), `reset()`.

Tests (reuse `test/sheet_builder.dart` + the fixture-anchored seed-0 key/payload from the integration test): full happy flow to a 5/5 grade; wrong fingerprint rejected at QR; counts > sections rejected at QR; double-marked sheet → result stage with reviewRows, gradeResult null; corner-missing image → needSheet with corner hint; dark image → needSheet with exposure hint; loadKey resets an in-flight session; nextSheet returns to needQr keeping the key; invalid key JSON keeps old key and sets lastError.

### Task 4: `lib/sheet_guide_overlay.dart` + widget test

`SheetGuidePainter` (CustomPainter): dim outside `pageGuideRect`, white border, bracket outlines at `cornerMarkTargets`. `SheetGuideOverlay` widget wraps CustomPaint + the hint text. Widget test: pumps overlay at a fixed size, no exceptions, hint text visible (painter geometry itself is covered by framing tests).

### Task 5: Screens + navigation

- `scan_qr_screen.dart`: full-screen `MobileScanner`, centered viewfinder box, torch toggle; on barcode → `session.setQr`; success pops, failure shows the error and keeps scanning.
- `capture_sheet_screen.dart`: `CameraController` preview under `SheetGuideOverlay`; shutter → `takePicture` → decode → `cropToGuideFraction(photo, guideAsFraction(pageGuideRect(photoSize), photoSize))` → `session.processSheet`; failure → SnackBar with `lastError` (retake); success → `ResultScreen`.
- `result_screen.dart`: needsReview ⇒ flagged rows + "retake / review manually" guidance; else score, per-question list (sheet #, section, marked vs correct, color-coded), "Next sheet" → `session.nextSheet`.
- `main.dart`: home shows key status (title, sections, M) and stage-appropriate buttons; "Load answer key" via `file_selector` (confirm dialog when replacing a key mid-session).
- Widget tests for home and result with a session driven directly (no camera).

### Task 6: Verification + PR

`dart format`, `flutter analyze`, `flutter test`; generator pytest sanity; push; PR noting device testing is pending (no emulator in this environment) and the preview-vs-photo aspect caveat (guide fraction computed against the photo dimensions).
