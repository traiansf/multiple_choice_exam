import json
from pathlib import Path

from click.testing import CliRunner

from mcexam.cli import _split_counts, main
from samples import SAMPLE_MD

EXAMPLE = Path(__file__).resolve().parents[2] / "examples" / "sample-exam.md"


def write_sample(tmp_path: Path) -> Path:
    path = tmp_path / "exam.md"
    path.write_text(SAMPLE_MD, encoding="utf-8")
    return path


def test_split_counts_default_50_30_20() -> None:
    assert _split_counts(20) == {"easy": 10, "medium": 6, "hard": 4}
    assert sum(_split_counts(7).values()) == 7


def test_lint_ok(tmp_path) -> None:
    result = CliRunner().invoke(main, ["lint", "--input", str(write_sample(tmp_path))])
    assert result.exit_code == 0, result.output
    assert "OK" in result.output and "Sample Exam" in result.output


def test_lint_rejects_invalid(tmp_path) -> None:
    path = tmp_path / "bad.md"
    path.write_text(SAMPLE_MD.replace("- [x] 4", "- [ ] 4"), encoding="utf-8")
    result = CliRunner().invoke(main, ["lint", "--input", str(path)])
    assert result.exit_code != 0
    assert "- [x]" in result.output


def test_lint_example_file() -> None:
    result = CliRunner().invoke(main, ["lint", "--input", str(EXAMPLE)])
    assert result.exit_code == 0, result.output


def test_generate_writes_pdfs_and_key(tmp_path) -> None:
    out = tmp_path / "build"
    result = CliRunner().invoke(
        main,
        [
            "generate",
            "--input",
            str(write_sample(tmp_path)),
            "--variants",
            "3",
            "--easy",
            "2",
            "--medium",
            "2",
            "--hard",
            "1",
            "--base-seed",
            "12345",
            "--out",
            str(out),
        ],
    )
    assert result.exit_code == 0, result.output
    assert sorted(p.name for p in out.glob("*.pdf")) == [
        "variant-001.pdf",
        "variant-002.pdf",
        "variant-003.pdf",
    ]
    key = json.loads((out / "answer-key.json").read_text())
    assert key["version"] == 1
    assert key["sections"] == {"easy": 3, "medium": 3, "hard": 2}


def test_generate_reproducible_with_base_seed(tmp_path) -> None:
    exam = write_sample(tmp_path)
    outs = []
    for name in ("one", "two"):
        out = tmp_path / name
        result = CliRunner().invoke(
            main,
            [
                "generate",
                "--input",
                str(exam),
                "--variants",
                "2",
                "--questions",
                "5",
                "--base-seed",
                "777",
                "--out",
                str(out),
            ],
        )
        assert result.exit_code == 0, result.output
        outs.append(out)
    for name in ("variant-001.pdf", "variant-002.pdf", "answer-key.json"):
        assert (outs[0] / name).read_bytes() == (outs[1] / name).read_bytes()


def test_generate_questions_conflicting_with_explicit_counts(tmp_path) -> None:
    result = CliRunner().invoke(
        main,
        [
            "generate",
            "--input",
            str(write_sample(tmp_path)),
            "--questions",
            "9",
            "--easy",
            "2",
            "--medium",
            "2",
            "--hard",
            "1",
        ],
    )
    assert result.exit_code != 0


def test_generate_count_exceeding_section(tmp_path) -> None:
    result = CliRunner().invoke(
        main,
        [
            "generate",
            "--input",
            str(write_sample(tmp_path)),
            "--easy",
            "9",
            "--medium",
            "1",
            "--hard",
            "1",
        ],
    )
    assert result.exit_code != 0
    assert "easy" in result.output


def test_scramble_writes_only_markdown(tmp_path) -> None:
    out = tmp_path / "shuffled.md"
    result = CliRunner().invoke(
        main,
        ["scramble", "--input", str(write_sample(tmp_path)), "--out", str(out), "--seed", "999"],
    )
    assert result.exit_code == 0, result.output
    assert out.exists()
    # only the markdown file is produced - never a key
    produced = {p.name for p in tmp_path.iterdir()} - {"exam.md"}
    assert produced == {"shuffled.md"}
    lint = CliRunner().invoke(main, ["lint", "--input", str(out)])
    assert lint.exit_code == 0, lint.output


def test_scramble_deterministic_with_seed(tmp_path) -> None:
    exam = write_sample(tmp_path)
    texts = []
    for name in ("a.md", "b.md"):
        out = tmp_path / name
        CliRunner().invoke(
            main, ["scramble", "--input", str(exam), "--out", str(out), "--seed", "31"]
        )
        texts.append(out.read_text())
    assert texts[0] == texts[1]
