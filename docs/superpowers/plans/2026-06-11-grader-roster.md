# Grader Student Roster & Assignment (issue #8) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upload a student roster (text file, one name per line); when confirming a grade — automatic or manual — let the grader assign a student by picking the name they read off the paper; the name is recorded with the grade and exported in the CSV report.

**Architecture:** (1) `records.dart`: `GradeRecord.studentName` (nullable) + a `student` CSV column with **RFC-4180 quoting** (names contain commas — the forward-dependency comment from #4 comes due); `recordFor(variantId)` lookup. (2) `session.dart`: `roster` list + `loadRoster(text)` (trim, drop blanks, dedupe; error when empty; **survives `loadKey`** — a roster is about the class, not the exam); `unassignedStudents` (roster minus names already assigned to *other* variants, so re-grading keeps the current assignment selectable); `confirmResult({studentName})` and `submitManualGrade(score, {studentName})` carry the name into the record. (3) UI: home gets "Load student roster" (file_selector, .txt/.csv) + a count line; the result screen (both the grade view and the review notice) gets a student dropdown (— no student — plus available names, preselecting the variant's existing assignment); records screen shows the name.

**Branch:** `feat/grader-roster`. No new deps.

---

### Task 1: records.dart (TDD)
Tests: CSV golden with a student column, including a name containing a comma (quoted) and a name containing a quote (doubled); record without a name → empty field; `recordFor` hit/miss. Implement `_csvField` quoting helper.

### Task 2: session roster + assignment (TDD)
Tests: `loadRoster` parses/trims/dedupes and rejects empty; roster survives `loadKey` while grades clear; `unassignedStudents` excludes names assigned to other variants but keeps the current variant's name; `confirmResult(studentName: ...)` and `submitManualGrade(..., studentName: ...)` record the name; re-grading the variant with a different student replaces the assignment.

### Task 3: UI + widget tests
Home: roster button + "M students" line. Result screen: `DropdownButtonFormField<String?>` in both views, default = existing assignment or none; selection threads into the confirm/submit calls. Records screen: subtitle shows the student name (alongside "graded manually" when both). Widget tests: dropdown lists only unassigned names; select + confirm → record carries the name; records screen shows it.

### Task 4: Verify + PR
format/analyze/full suite; push; PR closing #8.
