"""Shared stems (cases) and free-form sections: format v2."""

import json

import pytest
from click.testing import CliRunner

from mcexam.cli import main
from mcexam.keyfile import build_key
from mcexam.parser import ParseError, parse
from mcexam.qr import QrPayloadV2, decode_payload, encode_payload, qr_png
from mcexam.render import render_variant
from mcexam.scramble import scramble_exam, to_markdown
from mcexam.select import build_plan, source_order_plan
from mcexam.validator import ValidationError, load_exam

CASE_MD = """\
# Case Exam

## Modeling

### Case A: a library

A member asks for a title with **no copies** available.

| Rule | Text |
|------|------|
| R1 | Requests are served in order. |
| R2 | Only the requester may pick up. |

#### Which rule decides who gets the returned copy?
- [x] R1
- [ ] R2
- [ ] Neither
- [ ] Both, equally

#### Who may pick up the reserved copy?
- [ ] Any member
- [x] The requester
- [ ] The librarian
- [ ] Nobody

### A standalone question in the same section?
- [ ] No
- [x] Yes
- [ ] Only in legacy files
- [ ] Only at the end

## Contracts

### Case B: a counter

The counter `n` starts at 0 and only increases.

#### Which is an invariant?
- [x] `n >= 0`
- [ ] `n == 0`
- [ ] `n < 0`
- [ ] `n` is even

### Case C: a queue

- items enter at the back
- items leave at the front

#### Which item leaves first?
- [ ] The newest
- [x] The oldest
- [ ] A random one
- [ ] The largest
"""


def write_case_exam(tmp_path):
    path = tmp_path / "cases.md"
    path.write_text(CASE_MD, encoding="utf-8")
    return path


def test_parse_case_structure() -> None:
    raw = parse(CASE_MD)
    modeling, contracts = raw.sections
    assert [type(unit).__name__ for unit in modeling.units] == ["RawCase", "RawQuestion"]
    case = modeling.cases[0]
    assert case.title == "Case A: a library"
    assert case.stem.startswith("A member asks") and "| R2 |" in case.stem
    assert [q.prompt for q in case.questions] == [
        "Which rule decides who gets the returned copy?",
        "Who may pick up the reserved copy?",
    ]
    assert [c.title for c in contracts.cases] == ["Case B: a counter", "Case C: a queue"]
    assert "- items enter at the back" in contracts.cases[1].stem


def test_question_heading_outside_case_is_error() -> None:
    with pytest.raises(ParseError, match="outside a '###' case"):
        parse("# T\n\n## S\n\n#### Q?\n- [x] a\n- [ ] b\n")


def test_option_in_stem_is_error() -> None:
    with pytest.raises(ParseError, match="option"):
        parse("# T\n\n## S\n\n### Case\n\nStem.\n\n- [x] a\n")


def test_case_without_questions_is_error() -> None:
    with pytest.raises(ValidationError, match="has no '####' questions"):
        load_exam("# T\n\n## S\n\n### Case\n\nOnly a stem.\n")


def test_case_exam_model() -> None:
    exam = load_exam(CASE_MD)
    assert not exam.legacy
    assert exam.section_keys == ("Modeling", "Contracts")
    assert exam.unit_sizes() == {"Modeling": [2, 1], "Contracts": [1, 1]}
    assert exam.answer_key() == [0, 1, 1, 0, 1]
    assert exam.options_per_question == 4


def test_plan_keeps_case_questions_together_in_order() -> None:
    exam = load_exam(CASE_MD)
    sizes = exam.unit_sizes()
    for seed in range(50):
        plan = build_plan(seed, sizes, {"Modeling": 2, "Contracts": 1}, 4)
        modeling = [sq for sq in plan.sheet if sq.section == "Modeling"]
        assert len(modeling) == 3
        case_rows = [sq.index_in_section for sq in modeling if sq.unit_index == 0]
        assert case_rows == [0, 1]  # source order, adjacent
        position = [sq.unit_index for sq in modeling].index(0)
        assert [sq.unit_index for sq in modeling][position : position + 2] == [0, 0]
        assert len([sq for sq in plan.sheet if sq.section == "Contracts"]) == 1
        for sq in plan.sheet:
            assert sorted(sq.option_perm) == [0, 1, 2, 3]


def test_plan_shuffles_unit_order_across_seeds() -> None:
    sizes = load_exam(CASE_MD).unit_sizes()
    orders = {
        build_plan(seed, sizes, {"Modeling": 2, "Contracts": 2}, 4).selections["Modeling"]
        for seed in range(30)
    }
    assert orders == {(0, 1), (1, 0)}


def test_key_v2() -> None:
    key = build_key(load_exam(CASE_MD), "deadbeef")
    assert key["version"] == 2
    assert key["sections"] == [
        {"name": "Modeling", "units": [2, 1]},
        {"name": "Contracts", "units": [1, 1]},
    ]
    assert key["answer_key"] == [0, 1, 1, 0, 1]


def test_qr_v2_round_trip() -> None:
    payload = QrPayloadV2(
        variant_id=7, seed=2**64 - 1, counts=(2, 0, 1), source_fingerprint="ab12cd34"
    )
    text = encode_payload(payload)
    assert text == f"v2|7|{2**64 - 1}|ab12cd34|2,0,1"
    assert decode_payload(text) == payload


def test_scramble_round_trip_keeps_cases() -> None:
    exam = load_exam(CASE_MD)
    scrambled = load_exam(to_markdown(scramble_exam(exam, 11)))
    assert scrambled.section_keys == exam.section_keys
    original = {u.case.title: u for p in exam.parts for u in p.units if u.case}
    for part in scrambled.parts:
        for unit in part.units:
            if unit.case is None:
                continue
            source = original[unit.case.title]
            assert unit.case.stem == source.case.stem
            assert [q.prompt for q in unit.questions] == [q.prompt for q in source.questions]
            for q, s in zip(unit.questions, source.questions, strict=True):
                assert q.options[q.answer] == s.options[s.answer]


def test_render_case_variant(tmp_path) -> None:
    exam = load_exam(CASE_MD)
    plan = build_plan(5, exam.unit_sizes(), {"Modeling": 2, "Contracts": 2}, 4)
    out = tmp_path / "case.pdf"
    render_variant(out, exam, plan, qr_png("v2|1|5|deadbeef|2,2"), 1)
    assert out.read_bytes().startswith(b"%PDF")


def test_cli_lint_case_exam(tmp_path) -> None:
    result = CliRunner().invoke(main, ["lint", "--input", str(write_case_exam(tmp_path))])
    assert result.exit_code == 0, result.output
    assert "Modeling 2 unit(s) / 3 question(s)" in result.output


def test_cli_generate_with_counts(tmp_path) -> None:
    out = tmp_path / "build"
    result = CliRunner().invoke(
        main,
        [
            "generate",
            "--input",
            str(write_case_exam(tmp_path)),
            "--count",
            "Modeling=1",
            "--count",
            "Contracts=2",
            "--variants",
            "2",
            "--base-seed",
            "3",
            "--out",
            str(out),
        ],
    )
    assert result.exit_code == 0, result.output
    assert (out / "variant-001.pdf").exists() and (out / "variant-002.pdf").exists()
    assert json.loads((out / "answer-key.json").read_text(encoding="utf-8"))["version"] == 2


@pytest.mark.parametrize(
    "args, message",
    [
        ([], "--count"),
        (["--count", "Modeling=1"], "missing"),
        (["--count", "Nope=1", "--count", "Contracts=1"], "no section named"),
        (["--count", "Modeling=1", "--count", "Contracts=1", "--easy", "1"], "cannot be combined"),
        (["--count", "Modeling=3", "--count", "Contracts=1"], "only 2"),
    ],
)
def test_cli_generate_count_errors(tmp_path, args, message) -> None:
    result = CliRunner().invoke(
        main,
        [
            "generate",
            "--input",
            str(write_case_exam(tmp_path)),
            "--out",
            str(tmp_path / "b"),
            *args,
        ],
    )
    assert result.exit_code != 0
    assert message in result.output


def test_cli_count_works_for_legacy_exams(tmp_path) -> None:
    from samples import SAMPLE_MD

    path = tmp_path / "exam.md"
    path.write_text(SAMPLE_MD, encoding="utf-8")
    out = tmp_path / "build"
    result = CliRunner().invoke(
        main,
        [
            "generate",
            "--input",
            str(path),
            "--out",
            str(out),
            "--base-seed",
            "1",
            "--count",
            "Easy=1",
            "--count",
            "Medium=1",
            "--count",
            "Hard=1",
        ],
    )
    assert result.exit_code == 0, result.output
    assert json.loads((out / "answer-key.json").read_text(encoding="utf-8"))["version"] == 1


def test_cli_generate_romanian_labels(tmp_path) -> None:
    args = [
        "generate",
        "--input",
        str(write_case_exam(tmp_path)),
        "--variants",
        "1",
        "--count",
        "Modeling=1",
        "--count",
        "Contracts=1",
        "--base-seed",
        "3",
    ]
    ro = CliRunner().invoke(main, [*args, "--lang", "ro", "--out", str(tmp_path / "ro")])
    assert ro.exit_code == 0, ro.output
    bad = CliRunner().invoke(main, [*args, "--lang", "xx", "--out", str(tmp_path / "xx")])
    assert bad.exit_code != 0
    assert "xx" in bad.output


PREAMBLE_MD = CASE_MD.replace(
    "# Case Exam\n",
    "# Case Exam\n\nAnswer **every** question.\n\n- 60 minutes\n- no notes\n",
)


def test_preamble_is_kept_and_round_trips() -> None:
    exam = load_exam(PREAMBLE_MD)
    assert exam.preamble == "Answer **every** question.\n\n- 60 minutes\n- no notes"
    assert load_exam(to_markdown(exam)).preamble == exam.preamble
    assert load_exam(CASE_MD).preamble == ""


def test_heading_in_preamble_is_error() -> None:
    with pytest.raises(ParseError, match="preamble"):
        parse("# T\n\n##### not here\n\n## S\n")


def test_render_preamble(tmp_path) -> None:
    exam = load_exam(PREAMBLE_MD)
    plan = build_plan(5, exam.unit_sizes(), {"Modeling": 2, "Contracts": 2}, 4)
    out = tmp_path / "preamble.pdf"
    render_variant(out, exam, plan, qr_png("v2|1|5|deadbeef|2,2"), 1)
    assert out.read_bytes().startswith(b"%PDF")


def test_source_order_plan_keeps_source_order() -> None:
    exam = load_exam(CASE_MD)
    plan = source_order_plan(exam.unit_sizes(), {"Modeling": 2, "Contracts": 1}, 4)
    assert [(q.section, q.index_in_section, q.global_index) for q in plan.sheet] == [
        ("Modeling", 0, 0),
        ("Modeling", 1, 1),
        ("Modeling", 2, 2),
        ("Contracts", 0, 3),
    ]
    assert all(q.option_perm == (0, 1, 2, 3) for q in plan.sheet)


def test_cli_no_shuffle_writes_one_sample(tmp_path) -> None:
    out = tmp_path / "sample"
    args = [
        "generate",
        "--input",
        str(write_case_exam(tmp_path)),
        "--count",
        "Modeling=2",
        "--count",
        "Contracts=2",
    ]
    result = CliRunner().invoke(main, [*args, "--no-shuffle", "--out", str(out)])
    assert result.exit_code == 0, result.output
    assert sorted(p.name for p in out.iterdir()) == ["sample.pdf"]
    many = CliRunner().invoke(main, [*args, "--no-shuffle", "--variants", "2"])
    assert many.exit_code != 0
    assert "--no-shuffle" in many.output
