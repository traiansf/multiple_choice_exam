# Multiple-Choice Exam Generator & Grader

Generate randomized, print-ready multiple-choice exams from a single Markdown
question bank, and grade the filled-in answer sheets from your phone.

You write one Markdown file containing your questions (with the correct answer
marked). The **generator** produces any number of exam *variants* — each one
draws a random subset of questions and scrambles the order of every question's
options — as print-ready PDFs with an embedded QR code and an OMR (optical mark
recognition) bubble grid. The **grading app** scans the QR to recover the
randomization seed, scans the bubble sheet, and computes the grade against an
answer key — without ever needing the original questions.

> **Status:** early development. This README describes the intended system and
> its contracts; components are being built against this spec.

---

## How it works

```
        exam.md  (your question bank, correct answers marked)
           │
           ▼
   ┌─────────────────┐   generate --variants V
   │  mcexam (Python)│ ─────────────────────────────►  variant-001.pdf … variant-V.pdf
   │   CLI generator │                                  (questions + bubble grid + QR)
   └─────────────────┘ ─────────────────────────────►  answer-key.json
           │                                                  │
           │ each PDF's QR encodes only a tiny seed payload   │ (key vector + structure)
           ▼                                                  ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │  Flutter grading app                                               │
   │   1. load answer-key.json once                                     │
   │   2. per exam: scan QR  → seed + per-section selected counts       │
   │   3. replay the SAME selection + option scramble from the seed     │
   │   4. scan the bubble sheet (OMR) → detected marks                  │
   │   5. map marks back to original questions → grade                  │
   └──────────────────────────────────────────────────────────────────┘
```

The generator and the grader share **one deterministic algorithm**: given a
seed they reproduce the exact same question selection and option scramble. That
is why the QR only needs to carry a seed — the grader rebuilds the variant from
it. See [Determinism & reproducibility](#determinism--reproducibility).

---

## Components

| Component | Tech | Role |
|-----------|------|------|
| `mcexam`  | Python CLI | Lint, scramble, and generate exam variants (PDF) + answer key |
| Grading app | Flutter (Android/iOS) | Scan QR + bubble sheet, grade against the key |
| `shared/test-vectors.json` | JSON fixture | Pins the deterministic algorithm so both sides stay in sync |

---

## The exam Markdown format

A valid exam file is ordinary, renderable Markdown:

```markdown
# Calculus 101 — Midterm

## Easy

### What is 2 + 2?
- [ ] 3
- [x] 4
- [ ] 5
- [ ] 6

### Which symbol denotes a derivative?
- [x] d/dx
- [ ] ∫
- [ ] Σ
- [ ] √

## Medium

### What is the derivative of sin(x)?
- [ ] -sin(x)
- [x] cos(x)
- [ ] -cos(x)
- [ ] sin(x)

## Hard

### Evaluate ∫₀^π sin(x) dx.
- [ ] 0
- [x] 2
- [ ] 1
- [ ] π
```

Rules (enforced by `mcexam lint`):

1. **Exactly one `#` title** — the exam name, first heading in the file.
2. **Sections are `##` headings** named exactly `Easy`, `Medium`, and `Hard`.
   All three must be present.
3. **Questions are `###` headings** under a section. The heading text is the
   question prompt.
4. **Options are GitHub task-list items**: `- [ ]` for a distractor, `- [x]`
   (or `- [X]`) for the correct answer. **Exactly one checked option per
   question.**
5. **Uniform option count.** Every question has the *same* number of options
   `M`, with `2 ≤ M ≤ 10` (required by the fixed OMR bubble grid, labeled
   A–J). The linter rejects mixed counts and out-of-range counts.

Because the correct answer is marked inline, a Markdown file is *self-documenting*
— which is why `scramble` (below) needs no separate key file.

---

## Installation

### Generator (`mcexam`)

```bash
cd generator
python -m venv .venv && source .venv/bin/activate
pip install -e .
mcexam --help
```

### Grading app

```bash
cd grader
flutter pub get
flutter run            # on a connected device/emulator
```

---

## Usage

### Lint a question bank

Validate structure before doing anything else (CI / pre-commit friendly):

```bash
mcexam lint --input exam.md
```

Fails fast with an actionable message on: missing/extra title, missing section,
a question with zero or multiple `- [x]`, non-uniform option counts, or malformed
Markdown.

### Generate exam variants

```bash
# Explicit per-difficulty counts (n = 10 + 8 + 2 = 20 questions per variant):
mcexam generate --input exam.md --variants 30 \
    --easy 10 --medium 8 --hard 2 \
    --out build/

# Or give a total and use the default 50/30/20 split:
mcexam generate --input exam.md --variants 30 --questions 20 --out build/

# Reproducible run (fixed base seed):
mcexam generate --input exam.md --variants 30 --questions 20 --base-seed 12345
```

Produces in `--out` (default `build/`):

- `variant-001.pdf … variant-NNN.pdf` — one print-ready PDF per variant.
- `answer-key.json` — the grader's single input file (see below).

**Selection rules.** Within each section the requested number of questions is
drawn at random (seeded). On the sheet, questions appear grouped in
**Easy → Medium → Hard** order; the order *within* each group is the seeded
selection order. Each question's options are independently scrambled.

If `--easy/--medium/--hard` are given they define `n`; if `--questions` is also
given it must equal their sum. Requesting more questions than a section contains
is an error.

### Scramble the question bank itself

Emit a new Markdown file that is a shuffled version of the original — questions
reordered within each section and every question's options shuffled. Correct
answers stay marked inline, so the result is a valid, self-documenting exam MD
(useful for producing a randomized master copy):

```bash
mcexam scramble --input exam.md --out shuffled.md [--seed 999]
```

`scramble` does **not** emit an answer key — the `- [x]` markers move with the
options, so the shuffled file already records the answers. Run `generate` on it
later if you need a key for grading.

### Grade

In the Flutter app:

1. **Load** `answer-key.json` once for the exam. Optionally load a **student
   roster** — a plain text file with one student name per line — to assign
   names to graded sheets.
2. For each student sheet: **scan the QR** (recovers the seed and per-section
   selected counts), then **scan the bubble sheet**.
3. The app replays the selection + scramble from the seed, maps the detected
   marks back to the original questions, and shows the **score** plus a
   per-question breakdown next to a generated reference sheet. Low-confidence
   bubbles and unreadable QRs are flagged for manual review (with a hand-entry
   fallback) rather than guessed.
4. Confirmed grades are recorded per variant — optionally with the student
   picked from the roster — and exported as a CSV report.

---

## Data formats

### `answer-key.json` (grader input)

The only file the grading app needs about the exam. It never sees the questions.

```json
{
  "version": 1,
  "exam_title": "Calculus 101 — Midterm",
  "source_fingerprint": "ab12cd34",
  "options_per_question": 4,
  "sections": { "easy": 30, "medium": 25, "hard": 15 },
  "answer_key": [1, 0, 2, 3, "...70 entries, original order: easy then medium then hard"]
}
```

- `answer_key[i]` is the **0-based index of the correct option** for the *i*-th
  original question, in source order (all Easy, then Medium, then Hard).
- `sections` gives the size of each section, so the grader knows the partition.
- `source_fingerprint` lets the app warn if a QR was produced from a different
  source than this key.

### QR payload (in each PDF)

Deliberately tiny and seed-centric:

```
v1 | <variant_id> | <seed> | <n_easy> | <n_medium> | <n_hard> | <source_fp>
```

Everything else the grader needs (`M`, the full key, section sizes) comes from
`answer-key.json`. Only the per-variant facts the key file can't hold — the seed
and how many questions were drawn from each section — live in the QR.

### PDF anatomy

Each variant PDF contains: the exam title and variant id; the selected questions
(in Easy→Medium→Hard order, but without printed section headings — students
shouldn't see where the difficulty changes) with their scrambled options
labeled A, B, C…; a
fixed **OMR bubble grid** (one row per question, `M` bubbles per row); corner
**registration marks** so the grading camera can locate and deskew the grid; and
the **QR code**. The QR and the variant number are printed on **every page** —
the answer sheet and each question page — so separated sheets can always be
re-identified.

---

## Determinism & reproducibility

The whole system rests on one promise: **the same seed yields the same exam,
in both Python and Dart, forever.** The algorithm is fully specified so the two
implementations cannot drift:

1. Seed a **splitmix64** PRNG with the QR's `seed`.
2. For each section in fixed order **[Easy, Medium, Hard]**: Fisher–Yates–shuffle
   the section's index array `[0 … N_section-1]` and take the first `n_section`
   indices as the selection (in shuffled order).
3. The sheet order is the Easy selection, then Medium, then Hard.
4. For each selected question, in sheet order: Fisher–Yates–shuffle its option
   index array `[0 … M-1]`. Bubble position `p` then shows original option
   `perm[p]`; a mark at `p` is correct iff `perm[p] == answer_key[q]`.

Bounded random integers use rejection sampling (no modulo bias). The RNG stream
is consumed in exactly this order (all selections, then all option scrambles).

This is locked down by **`shared/test-vectors.json`**: a fixture mapping inputs
(`seed, sections, n_easy/n_medium/n_hard, M`) to the expected selection and
permutations. Both the Python test suite and the Dart test suite assert against
it, so any change to either implementation that breaks cross-language agreement
fails CI immediately. Changing the algorithm requires regenerating the vectors
**and** bumping the QR payload version.

---

## Repository layout

```
.
├── generator/              # Python package `mcexam`
│   ├── src/mcexam/         # cli, parser, validator, model, rng, select, render, qr, keyfile
│   └── tests/              # parser/validator/rng/round-trip tests
├── grader/                 # Flutter grading app
│   ├── lib/                # core: rng, select, qr_scan, omr, sheet_geometry, sheet_render, keyfile, grading
│   │                       # app: session, framing, records, sheet_guide_overlay, scan/capture/result/records screens, main
│   └── test/               # vector replay, OMR fixtures, session/framing/widget tests
├── shared/
│   └── test-vectors.json   # cross-language determinism fixture (source of truth)
├── examples/
│   └── sample-exam.md
├── README.md
├── CLAUDE.md
└── LICENSE                 # GNU GPL v3
```

---

## Development

```bash
# Generator
cd generator && pip install -e ".[dev]"
pytest                       # includes determinism + round-trip tests
ruff check . && ruff format --check .

# Grader
cd grader && flutter test    # includes the cross-language vector test
flutter analyze
```

The round-trip test is the integration backstop: generate a variant from a known
seed, simulate a sheet of known marks, grade it, and assert the expected score.

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
