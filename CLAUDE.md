# CLAUDE.md

Guidance for working in this repository. Read [README.md](README.md) for the
user-facing overview and the canonical data-format definitions; this file
focuses on the invariants and workflows that are easy to break.

## What this is

Two programs plus a shared contract:

- **`generator/`** — Python CLI `mcexam` (`lint`, `generate`, `scramble`).
  Parses an exam Markdown file, validates it, and emits print-ready PDF variants
  + `answer-key.json`.
- **`grader/`** — Flutter app. Loads `answer-key.json`, scans a QR for the seed,
  scans an OMR bubble sheet, and grades — **without the original questions**.
- **`shared/test-vectors.json`** — the fixture that keeps the Python and Dart
  randomization byte-for-byte identical.

## The determinism contract (most important thing here)

The QR carries only a seed; the grader rebuilds the variant from it. This only
works if **the Python generator and the Dart grader produce identical selections
and option scrambles from the same seed.** Treat that as a hard invariant.

The algorithm (specified fully in README → *Determinism & reproducibility*):

1. `splitmix64(seed)` PRNG; bounded ints via **rejection sampling** (no modulo bias).
2. Per section in fixed order **[Easy, Medium, Hard]**: Fisher–Yates shuffle the
   section index array, take the first `n_section` as the selection.
3. Sheet order = Easy selection ++ Medium ++ Hard.
4. Per selected question (sheet order): Fisher–Yates shuffle its `M` option
   indices. Position `p` shows original option `perm[p]`; correct iff
   `perm[p] == answer_key[q]`.

RNG stream is consumed in exactly that order: **all section selections first,
then all option scrambles.** Do not reorder, batch, or lazily-evaluate it
differently in one language than the other.

Rules when touching anything related to randomization:

- **`rng.py` and `rng.dart` must implement the same algorithm.** Any change to
  one requires the same change to the other.
- **`shared/test-vectors.json` is the source of truth.** Both test suites assert
  against it. If you change the algorithm on purpose, regenerate the vectors
  **and bump the QR payload version** (`v1` → `v2`) so old PDFs are detectable.
- Never seed the PRNG from wall-clock time inside the algorithm. Seeds come from
  `--base-seed` (or a recorded per-variant value) so runs are reproducible.
- Don't use language built-in RNGs (`random`, `dart:math` `Random`) for
  selection/scramble — they are not cross-language stable. Use the shared
  splitmix64 implementation.

## Single sources of truth

When you change one of these, update **all** the listed mirrors in the same change:

- **MD structure** → `generator/src/mcexam/validator.py` is the executable spec.
  Mirrors: README "exam Markdown format", `examples/sample-exam.md`, the Flutter
  app only if it ever parses MD (it normally does not).
- **`answer-key.json` schema** → `keyfile.py` (write) **and** `keyfile.dart`
  (read). Mirrors: README "Data formats".
- **QR payload** → `qr.py` (encode) **and** `qr_scan.dart` (decode). Mirrors:
  README "QR payload", and bump `version` on any field change.
- **The algorithm** → `rng.py` + `select.py`, `rng.dart` + `select.dart`,
  `shared/test-vectors.json`, README.

`lint`, `generate`, and `scramble` all validate through the **same** `validator.py`
— don't add a second, divergent validation path.

## Invariants to preserve

- **Uniform option count `M`** across every question (the bubble grid is fixed).
  Reject non-uniform input at lint time; never silently pad or truncate.
- **Exactly one `- [x]`** per question.
- All three sections (`Easy`, `Medium`, `Hard`) present; `##` sections, `###`
  questions, single `#` title.
- `scramble` emits **only** a Markdown file (markers travel with options) —
  never an answer key. The key file is a `generate`-only artifact.
- Grader inputs are exactly: `answer-key.json` + the QR + the scanned sheet.
  Do not make the grader depend on the original exam text.
- Fail fast with actionable messages; for the grader, **flag for manual review**
  (low-confidence OMR, unreadable QR, `source_fingerprint` mismatch) rather than
  guessing a grade.

## Commands

```bash
# Generator (run from generator/)
pip install -e ".[dev]"
pytest                         # parser, validator, determinism vs fixture, round-trip
ruff check . && ruff format --check .

# Grader (run from grader/)
flutter pub get
flutter test                   # includes rng_test replaying shared/test-vectors.json
flutter analyze
```

## Testing expectations

- Behavior changes need tests, not just updated strings. In particular:
  - **Determinism test** (both languages) must keep asserting against
    `shared/test-vectors.json`.
  - **Round-trip test**: generate from a known seed → synthesize a sheet of known
    marks → grade → assert the expected score and per-question correctness.
  - Validator tests should cover each rejection case (no/extra title, missing
    section, zero/multiple `- [x]`, mixed option counts).
- Run lint/format/typecheck and the full suite before claiming work is done.
  Green is necessary, not sufficient — reason about whether the grader would
  still grade real, slightly-skewed phone photos correctly.

## Conventions

- **Python:** package `mcexam` under `generator/src/`, `ruff` for lint+format,
  type hints throughout, `click` for the CLI, `segno` for QR, `reportlab` for
  precise bubble/registration-mark placement.
- **Dart/Flutter:** `flutter analyze` clean; `mobile_scanner` for QR; keep OMR
  detection isolated in `omr.dart` so it can be tested against fixture images.
- Keep modules small and single-purpose (parser ≠ validator ≠ renderer ≠ rng).
- This project is GPL v3; keep new files compatible.
