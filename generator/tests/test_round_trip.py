"""Integration backstop: generate a variant plan from a known seed, synthesize a
sheet of known marks, grade it with the documented mapping, assert the score."""

from mcexam.keyfile import build_key
from mcexam.select import build_variant
from mcexam.validator import load_exam
from samples import SAMPLE_MD


def grade(plan, answer_key: list[int], marks: list[int]) -> list[bool]:
    """A mark at sheet position p of row r is correct iff
    plan.sheet[r].option_perm[p] == answer_key[plan.sheet[r].global_index]."""
    return [
        sq.option_perm[marks[row]] == answer_key[sq.global_index]
        for row, sq in enumerate(plan.sheet)
    ]


def test_round_trip_known_marks() -> None:
    exam = load_exam(SAMPLE_MD)
    plan = build_variant(424242, exam.section_sizes(), {"easy": 2, "medium": 2, "hard": 1}, 4)
    answer_key = build_key(exam, "00000000")["answer_key"]

    # Student answers correctly on even sheet rows, deliberately wrong on odd rows.
    marks = []
    for row, sq in enumerate(plan.sheet):
        correct_position = sq.option_perm.index(answer_key[sq.global_index])
        marks.append(correct_position if row % 2 == 0 else (correct_position + 1) % 4)

    results = grade(plan, answer_key, marks)
    assert results == [True, False, True, False, True]
    assert sum(results) == 3


def test_round_trip_all_correct_any_seed() -> None:
    exam = load_exam(SAMPLE_MD)
    for seed in (0, 1, 2**64 - 1, 555):
        plan = build_variant(seed, exam.section_sizes(), {"easy": 3, "medium": 3, "hard": 2}, 4)
        answer_key = build_key(exam, "00000000")["answer_key"]
        marks = [sq.option_perm.index(answer_key[sq.global_index]) for sq in plan.sheet]
        assert all(grade(plan, answer_key, marks))
