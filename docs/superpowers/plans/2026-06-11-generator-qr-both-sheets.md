# Generator: QR + Variant Number on Both Sheets (issue #9) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Print the QR code and the variant number on the exam (questions) pages too — on **every** page, so any separated page re-identifies its variant — keeping the answer sheet (page 1) byte-identical (the OMR geometry contract and the committed grader fixture must not move).

**Architecture:** `render.py` only. `_draw_questions` gains the QR bytes and draws a per-page header — `"<title> — Variant NNN"` plus a small QR (18mm) at the top-right — via a helper invoked on the first page and after every page break (`ensure_space`). Content starts below the header/QR band. No QR payload change (same code, more places), no Dart change (the grader never reads question pages), no geometry-contract change (page 1 untouched).

**Branch:** `feat/generator-qr-both-sheets`.

**Tests (TDD):**
1. New: every page draws exactly one QR image — with uncompressed streams (`pageCompression=0`), each image placement is one `Do` operator: `data.count(b' Do') == pages`. (Currently only page 1 has it — test fails first.)
2. New: page 1 of the new output is byte-identical in its answer-sheet content — assert the OMR fixture test still passes (no regeneration) and existing byte-reproducibility tests stay green.
3. Existing suite green; visual check of page 2 via pdftoppm (header + QR top-right, no text collision).
4. README "PDF anatomy" updated: QR + variant id on every page.
