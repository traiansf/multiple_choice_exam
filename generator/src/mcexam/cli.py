"""mcexam command-line interface: lint, generate, scramble."""

import secrets
from pathlib import Path

import click

from .keyfile import source_fingerprint, write_key
from .model import Exam
from .parser import ParseError
from .qr import QrPayload, QrPayloadV2, encode_payload, qr_png
from .render import render_variant
from .scramble import scramble_exam, to_markdown
from .select import build_plan, variant_seeds
from .validator import ValidationError, load_exam


def _load(input_path: Path) -> tuple[str, Exam]:
    text = input_path.read_text(encoding="utf-8")
    try:
        return text, load_exam(text)
    except (ParseError, ValidationError) as exc:
        raise click.ClickException(f"{input_path}:\n{exc}") from exc


def _split_counts(questions: int) -> dict[str, int]:
    """Default 50/30/20 split; hard takes the rounding remainder."""
    easy = round(questions * 0.5)
    medium = round(questions * 0.3)
    return {"easy": easy, "medium": medium, "hard": questions - easy - medium}


def _resolve_counts(
    easy: int | None, medium: int | None, hard: int | None, questions: int | None
) -> dict[str, int]:
    explicit = (easy, medium, hard)
    if any(value is not None for value in explicit):
        if not all(value is not None for value in explicit):
            raise click.UsageError("--easy, --medium, and --hard must be given together")
        counts = {"easy": easy, "medium": medium, "hard": hard}
        total = sum(counts.values())
        if total == 0:
            raise click.UsageError("at least one question must be requested")
        if questions is not None and questions != total:
            raise click.UsageError(
                f"--questions {questions} does not match --easy+--medium+--hard = {total}"
            )
        return counts
    if questions is None:
        raise click.UsageError("give --questions, or all of --easy/--medium/--hard")
    return _split_counts(questions)


_INPUT_OPTION = click.option(
    "--input",
    "input_path",
    type=click.Path(exists=True, dir_okay=False, path_type=Path),
    required=True,
    help="Exam Markdown file.",
)


@click.group()
@click.version_option(package_name="mcexam")
def main() -> None:
    """Generate, lint, and scramble randomized multiple-choice exams."""


@main.command()
@_INPUT_OPTION
def lint(input_path: Path) -> None:
    """Validate an exam Markdown file."""
    _, exam = _load(input_path)
    if exam.legacy:
        sizes = exam.section_sizes()
        click.echo(
            f"OK: '{exam.title}' — easy {sizes['easy']}, medium {sizes['medium']},"
            f" hard {sizes['hard']}, {exam.options_per_question} options per question"
        )
        return
    parts = ", ".join(
        f"{key} {len(sizes)} unit(s) / {sum(sizes)} question(s)"
        for key, sizes in exam.unit_sizes().items()
    )
    click.echo(f"OK: '{exam.title}' — {parts}, {exam.options_per_question} options per question")


def _parse_count_specs(exam: Exam, specs: tuple[str, ...]) -> dict[str, int]:
    """--count NAME=N, by section name as written in the file ('Easy' for the
    legacy section key 'easy')."""
    key_by_name = {
        part.name: key for key, part in zip(exam.section_keys, exam.ordered_parts, strict=True)
    }
    counts: dict[str, int] = {}
    for spec in specs:
        name, sep, value = spec.rpartition("=")
        if not sep or not name:
            raise click.UsageError(f"--count {spec!r}: expected NAME=N")
        if name not in key_by_name:
            raise click.UsageError(
                f"--count {spec!r}: no section named {name!r} (sections: {', '.join(key_by_name)})"
            )
        if not value.isdigit():
            raise click.UsageError(f"--count {spec!r}: N must be a non-negative integer")
        key = key_by_name[name]
        if key in counts:
            raise click.UsageError(f"--count given twice for section {name!r}")
        counts[key] = int(value)
    missing = [name for name, key in key_by_name.items() if key not in counts]
    if missing:
        raise click.UsageError(
            "every section needs a count; missing: "
            + ", ".join(f"--count '{name}=N'" for name in missing)
        )
    if sum(counts.values()) == 0:
        raise click.UsageError("at least one question must be requested")
    return counts


@main.command()
@_INPUT_OPTION
@click.option("--variants", default=1, show_default=True, type=click.IntRange(min=1))
@click.option("--easy", type=click.IntRange(min=0), default=None)
@click.option("--medium", type=click.IntRange(min=0), default=None)
@click.option("--hard", type=click.IntRange(min=0), default=None)
@click.option("--questions", type=click.IntRange(min=1), default=None)
@click.option(
    "--count",
    "count_specs",
    multiple=True,
    metavar="NAME=N",
    help="Units (questions or cases) to draw from the section NAME; repeat for"
    " every section. Required for exams with cases or other section names.",
)
@click.option(
    "--base-seed",
    type=click.IntRange(min=0, max=2**64 - 1),
    default=None,
    help="Unsigned 64-bit seed; fix for a reproducible run.",
)
@click.option(
    "--out",
    "out_dir",
    type=click.Path(file_okay=False, path_type=Path),
    default=Path("build"),
    show_default=True,
)
def generate(
    input_path: Path,
    variants: int,
    easy: int | None,
    medium: int | None,
    hard: int | None,
    questions: int | None,
    count_specs: tuple[str, ...],
    base_seed: int | None,
    out_dir: Path,
) -> None:
    """Generate variant PDFs and answer-key.json."""
    text, exam = _load(input_path)
    legacy_flags = (easy, medium, hard, questions)
    if count_specs:
        if any(value is not None for value in legacy_flags):
            raise click.UsageError(
                "--count cannot be combined with --easy/--medium/--hard/--questions"
            )
        counts = _parse_count_specs(exam, count_specs)
    elif exam.legacy:
        counts = _resolve_counts(easy, medium, hard, questions)
    else:
        raise click.UsageError(
            "this exam has cases or named sections: give --count 'NAME=N' for every section"
        )
    unit_sizes = exam.unit_sizes()
    for key in exam.section_keys:
        available = len(unit_sizes[key])
        if counts[key] > available:
            what = "questions" if exam.legacy else "units"
            raise click.ClickException(
                f"requested {counts[key]} {key} {what} but '{input_path}' has only {available}"
            )
    if base_seed is None:
        base_seed = secrets.randbits(64)
    click.echo(f"base seed: {base_seed}")

    try:
        out_dir.mkdir(parents=True, exist_ok=True)
    except (FileExistsError, NotADirectoryError) as exc:
        raise click.ClickException(f"--out {out_dir} exists and is not a directory") from exc
    fingerprint = source_fingerprint(text)
    write_key(out_dir / "answer-key.json", exam, fingerprint)
    for variant_id, seed in enumerate(variant_seeds(base_seed, variants), start=1):
        plan = build_plan(seed, unit_sizes, counts, exam.options_per_question)
        if exam.legacy:
            qr_payload = QrPayload(
                variant_id=variant_id,
                seed=seed,
                n_easy=counts["easy"],
                n_medium=counts["medium"],
                n_hard=counts["hard"],
                source_fingerprint=fingerprint,
            )
        else:
            qr_payload = QrPayloadV2(
                variant_id=variant_id,
                seed=seed,
                counts=tuple(counts[key] for key in exam.section_keys),
                source_fingerprint=fingerprint,
            )
        render_variant(
            out_dir / f"variant-{variant_id:03d}.pdf",
            exam,
            plan,
            qr_png(encode_payload(qr_payload)),
            variant_id,
        )
    click.echo(f"wrote {variants} variant(s) + answer-key.json to {out_dir}/")


@main.command()
@_INPUT_OPTION
@click.option(
    "--out",
    "out_path",
    type=click.Path(dir_okay=False, path_type=Path),
    required=True,
    help="Output Markdown file.",
)
@click.option(
    "--seed",
    type=click.IntRange(min=0, max=2**64 - 1),
    default=None,
    help="Unsigned 64-bit seed; fix for a reproducible shuffle.",
)
def scramble(input_path: Path, out_path: Path, seed: int | None) -> None:
    """Write a shuffled copy of the question bank (Markdown only, never a key)."""
    _, exam = _load(input_path)
    if seed is None:
        seed = secrets.randbits(64)
    click.echo(f"seed: {seed}")
    out_path.write_text(to_markdown(scramble_exam(exam, seed)), encoding="utf-8")
    click.echo(f"wrote {out_path}")
