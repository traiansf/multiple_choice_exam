# Grader Grade Recording & Report Export (issue #4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record each *confirmed* grade in app memory, keyed by the QR's `variant_id` (re-grading the same variant **replaces** the recorded score — user clarification); export the collected grades as a CSV report (share/download); reset the records, behind a warning, when a new `answer-key.json` is loaded.

**Architecture:** (1) `lib/records.dart` — pure `GradeBook`: `record()` upserts by variantId, sorted `records`, `toCsv()` (variant_id, score, total, percent, recorded_at ISO). (2) `GraderSession.confirmResult()` — the hook established in #5 — now also records (variantId from the live payload, score/total from the grade, `DateTime.now()`); `loadKey` clears the book; `nextSheet`/`retakeSheet` do NOT; expose `gradeBook`. Review-flagged sheets remain unrecordable (confirmResult already throws without a grade). (3) UI: home shows the recorded count and an enabled-when-nonempty "Records" entry; `RecordsScreen` lists variant → score rows with an Export button (`share_plus`, `XFile.fromData` CSV — thin, device-tested later); the replace-key dialog warns about discarding recorded grades when the book is non-empty.

**Branch:** `feat/grader-recording`. New dep: `share_plus`.

---

### Task 1: Branch + dep
`git checkout -b feat/grader-recording`; `flutter pub add share_plus`; commit.

### Task 2: `lib/records.dart` (TDD)
Tests: record two variants → sorted by variantId; re-record variant → replaced (length unchanged, new score, new timestamp); `clear()`; `toCsv()` exact golden string (header + rows, percent one decimal, ISO-8601 timestamps); empty book CSV = header only.

### Task 3: Session integration (TDD)
Tests: confirm records the grade (variantId 1, 5/5) with a non-null recordedAt; confirm → nextSheet → re-scan same QR → grade differently → confirm again ⇒ one record with the new score (replacement, full pipeline); records survive nextSheet/retakeSheet; loadKey clears the book; `confirmResult` still throws without a grade (existing).

### Task 4: UI (widget tests where plugin-free)
- Home: "N recorded" line in the key card; "Records" button (disabled when empty) → RecordsScreen.
- Replace-key dialog: when `gradeBook` non-empty, the content mentions the N recorded grades being discarded; test via tapping 'Load a different key' then Cancel (no file_selector call on the Cancel path).
- `RecordsScreen`: ListView (Variant 001 — 4/5 — 80.0%), Export button → `Share.shareXFiles` with the CSV (thin, untested); empty state text.
- Widget tests: count line; records list rows; dialog warning text; disabled Records button when empty.

### Task 5: Verify + PR
format/analyze/full suite; push; PR closing #4 (note device-pass caveat for the share sheet).
