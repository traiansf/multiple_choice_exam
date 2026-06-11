from mcexam.scramble import scramble_exam, to_markdown
from mcexam.validator import load_exam
from samples import SAMPLE_MD


def test_scramble_preserves_question_multiset_per_section() -> None:
    exam = load_exam(SAMPLE_MD)
    shuffled = scramble_exam(exam, seed=99)
    for key in ("easy", "medium", "hard"):
        assert sorted(q.prompt for q in shuffled.sections[key]) == sorted(
            q.prompt for q in exam.sections[key]
        )
        assert len(shuffled.sections[key]) == len(exam.sections[key])


def test_marker_travels_with_correct_option() -> None:
    exam = load_exam(SAMPLE_MD)
    shuffled = scramble_exam(exam, seed=99)
    originals = {q.prompt: q for key in exam.sections for q in exam.sections[key]}
    for key in shuffled.sections:
        for question in shuffled.sections[key]:
            original = originals[question.prompt]
            assert sorted(question.options) == sorted(original.options)
            assert question.options[question.answer] == original.options[original.answer]


def test_scramble_is_deterministic() -> None:
    exam = load_exam(SAMPLE_MD)
    assert scramble_exam(exam, seed=5) == scramble_exam(exam, seed=5)
    assert scramble_exam(exam, seed=5) != scramble_exam(exam, seed=6)


def test_markdown_round_trip() -> None:
    exam = load_exam(SAMPLE_MD)
    shuffled = scramble_exam(exam, seed=123)
    assert load_exam(to_markdown(shuffled)) == shuffled


def test_to_markdown_of_unscrambled_exam_is_canonical_sample() -> None:
    exam = load_exam(SAMPLE_MD)
    assert load_exam(to_markdown(exam)) == exam
