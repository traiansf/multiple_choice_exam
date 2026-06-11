import json

from samples import SAMPLE_MD

from mcexam.keyfile import build_key, source_fingerprint, write_key
from mcexam.validator import load_exam


def test_fingerprint_is_8_hex_chars_and_stable() -> None:
    fp = source_fingerprint(SAMPLE_MD)
    assert len(fp) == 8
    int(fp, 16)  # raises if not hex
    assert fp == source_fingerprint(SAMPLE_MD)
    assert fp != source_fingerprint(SAMPLE_MD + "x")


def test_fingerprint_normalizes_crlf() -> None:
    assert source_fingerprint("a\r\nb") == source_fingerprint("a\nb")


def test_build_key_schema() -> None:
    exam = load_exam(SAMPLE_MD)
    key = build_key(exam, "ab12cd34")
    assert key == {
        "version": 1,
        "exam_title": "Sample Exam",
        "source_fingerprint": "ab12cd34",
        "options_per_question": 4,
        "sections": {"easy": 3, "medium": 3, "hard": 2},
        "answer_key": [1, 2, 2, 1, 0, 2, 1, 1],
    }


def test_write_key_round_trips(tmp_path) -> None:
    exam = load_exam(SAMPLE_MD)
    path = tmp_path / "answer-key.json"
    write_key(path, exam, "ab12cd34")
    assert json.loads(path.read_text()) == build_key(exam, "ab12cd34")
