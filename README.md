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

Rules (enforced by `mcexam lint`; see the next section for cases and named
sections, which relax rule 2):

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

Prompts and options may use inline Markdown (`**bold**`, `*italic*`,
`` `code` ``); each stays on its heading or list-item line.

Text between the `#` title and the first `##` section is the **preamble**:
instructions printed once, at the top of the first question page. It takes the
same Markdown as a case stem (no headings, no `- [ ]` items).

### Shared stems (cases) and named sections

Several questions can share one stem — a scenario, a table, a code excerpt.
Such a group is a **case**: a `###` heading with the case title, then the stem
(any Markdown except headings and `- [ ]`/`- [x]` items: paragraphs, lists,
pipe tables, code blocks, quotes), then the case's questions as `####`
headings with their options. A `###` heading followed directly by options is
still a standalone question, and both can be mixed in a section.

```markdown
# Software Design — Final

## Requirements

### Case: a lending library

| Rule | Text |
|------|------|
| R1 | A returned copy is reserved for the oldest pending request. |
| R2 | Only the requester may pick up the reserved copy. |

#### A copy is returned while two requests are pending. Which one gets it?
- [ ] The most recent one
- [x] The oldest one
- [ ] Whichever member arrives first
- [ ] Neither

#### Another member tries to pick up the reserved copy. What happens?
- [ ] The pickup succeeds
- [x] The pickup is refused
- [ ] The reservation is cancelled
- [ ] The request is closed

### Which kind of requirement is "searches answer within 2 seconds"?
- [ ] Functional
- [ ] Domain rule
- [x] Quality attribute
- [ ] Constraint
```

A file with a case, or with any section name other than `Easy`/`Medium`/`Hard`,
uses **named sections**: any non-empty, distinct `##` names, kept in source
order, each with at least one question or case. Selection draws whole
**units** — a standalone question or a case — so a case's questions always
appear together, in source order, under its title and stem; only their
options are shuffled. Variants differ in which units they draw, in the order
of the units within each section, and in the option order. Options must not
refer to one another by letter or position ("all of the above", "A and B"),
since the letters change in every variant. See `examples/case-exam.md`.

Files with only `Easy`/`Medium`/`Hard` and no cases are unchanged: same rules,
same `--easy/--medium/--hard/--questions` flags, same key file and QR (v1), so
existing PDFs stay gradable.

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

For an exam with cases or named sections, give the number of **units**
(standalone questions or whole cases) to draw from every section with a
repeatable `--count NAME=N`, using the section name as written after `##`:

```bash
mcexam generate --input examples/case-exam.md --variants 30 \
    --count Requirements=2 --count Contracts=1 --out build/
```

The sheet then lists the sections in source order; the number of answer rows
is the total number of questions in the drawn units. `--count` also works for
an Easy/Medium/Hard file (`--count Easy=10 ...`) and cannot be combined with
the per-difficulty flags.

**Sample sheet.** `--no-shuffle` writes a single `sample.pdf` instead: the
first `N` units of every section in source order (with `--count`, or the
per-difficulty flags), options in source order, so the letters match a key
written for the source file. It has no QR code and no `answer-key.json` is
written: no seed reproduces it, so it cannot be graded. Use it to publish a
practice paper that looks like the real sheets; it cannot be combined with
`--variants` or `--base-seed`.

**Sheet language.** `--lang` sets the language of the few fixed words the
tool prints itself — the name line and the variant number on the answer
sheet and on every question page: `en` (default: `Name:`, `Variant 001`) or
`ro` (`Nume:`, `Varianta 001`). The exam's own text comes from the Markdown
file as written. The language changes only these words: the answer-sheet
geometry, the QR and `answer-key.json` stay the same. To add a language, add
an entry to `LABELS` in `generator/src/mcexam/render.py`.

### Scramble the question bank itself

Emit a new Markdown file that is a shuffled version of the original — questions
(or cases) reordered within each section and every question's options shuffled;
the questions inside a case keep their order. Correct
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

Exams with cases or named sections get **version 2** (shown here for
`examples/case-exam.md`), where `sections` is an
ordered list giving each section's name and the question count of every unit
(`1` for a standalone question, the number of `####` questions for a case):

```json
{
  "version": 2,
  "exam_title": "Software Design — Final",
  "source_fingerprint": "947aebb0",
  "options_per_question": 4,
  "sections": [
    { "name": "Requirements", "units": [2, 1] },
    { "name": "Contracts", "units": [2] }
  ],
  "answer_key": [1, 2, 2, 0, 1]
}
```

`answer_key` follows the same source order: sections in order, then units, then
the questions of each unit.

### QR payload (in each PDF)

Deliberately tiny and seed-centric:

```
v1 | <variant_id> | <seed> | <n_easy> | <n_medium> | <n_hard> | <source_fp>
```

Everything else the grader needs (`M`, the full key, section sizes) comes from
`answer-key.json`. Only the per-variant facts the key file can't hold — the seed
and how many questions were drawn from each section — live in the QR.

Exams with a version-2 key carry a version-2 QR, with the number of units drawn
from each section, in section order:

```
v2 | <variant_id> | <seed> | <source_fp> | <count_1>,<count_2>,...
```

The grader reads both versions; the QR version must match the key file version.

### PDF anatomy

Each variant PDF contains: the exam title and variant id; the selected questions
(in Easy→Medium→Hard order, but without printed section headings — students
shouldn't see where the difficulty changes) with their scrambled options
labeled A, B, C… — a case prints its title and stem once, kept on the same page
as its first question; a
fixed **OMR bubble grid** (one row per question, `M` bubbles per row);
**registration marks** bounding the answer area — full page width, only the
band around the grid — so the grading camera needs to frame only that band
(not the whole page); and the **QR code**. With the band framed on the marks,
the graded photo excludes the title, variant number, and QR (all above the
band); the printed name line sits just inside the band top, so the line itself
and the bottom few millimetres of any handwritten name appear at the very top
of the photo. The QR and the variant number are printed on **every page** —
the answer sheet and each question page — so separated sheets can always be
re-identified.

---

## Determinism & reproducibility

The whole system rests on one promise: **the same seed yields the same exam,
in both Python and Dart, forever.** The algorithm is fully specified so the two
implementations cannot drift:

1. Seed a **splitmix64** PRNG with the QR's `seed`.
2. For each section in key order (**[Easy, Medium, Hard]** for version-1 exams,
   source order otherwise): Fisher–Yates–shuffle the section's **unit** index
   array `[0 … U_section-1]` and take the first `n_section` indices as the
   selection (in shuffled order). In a version-1 exam every unit is one
   question, so this is the question selection.
3. The sheet order is the first section's selection, then the next, and so on;
   a selected case contributes its questions in source order.
4. For each sheet question, in sheet order: Fisher–Yates–shuffle its option
   index array `[0 … M-1]`. Bubble position `p` then shows original option
   `perm[p]`; a mark at `p` is correct iff `perm[p] == answer_key[q]`.

Bounded random integers use rejection sampling (no modulo bias). The RNG stream
is consumed in exactly this order (all selections, then all option scrambles).

This is locked down by **`shared/test-vectors.json`**: a fixture mapping inputs
(`seed, sections, n_easy/n_medium/n_hard, M`, and for `unit_plans` the unit
sizes and per-section counts) to the expected selection and permutations. Both the Python test suite and the Dart test suite assert against
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
│   ├── sample-exam.md
│   └── case-exam.md       # cases (shared stems) and named sections
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
