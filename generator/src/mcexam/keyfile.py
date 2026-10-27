"""answer-key.json writer. Schema is mirrored by grader/lib/keyfile.dart and
documented in README 'Data formats' — change all three together."""

import hashlib
import json
from pathlib import Path

from .model import Exam

KEY_VERSION = 1
KEY_VERSION_V2 = 2


def source_fingerprint(text: str) -> str:
    """First 8 hex chars of sha256 over the newline-normalized source text."""
    normalized = text.replace("\r\n", "\n")
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:8]


def build_key(exam: Exam, fingerprint: str) -> dict:
    """v1 for legacy exams (unchanged schema); v2 otherwise, with the sections
    as an ordered list and the question count of every unit."""
    if not exam.legacy:
        return {
            "version": KEY_VERSION_V2,
            "exam_title": exam.title,
            "source_fingerprint": fingerprint,
            "options_per_question": exam.options_per_question,
            "sections": [{"name": key, "units": sizes} for key, sizes in exam.unit_sizes().items()],
            "answer_key": exam.answer_key(),
        }
    return {
        "version": KEY_VERSION,
        "exam_title": exam.title,
        "source_fingerprint": fingerprint,
        "options_per_question": exam.options_per_question,
        "sections": exam.section_sizes(),
        "answer_key": exam.answer_key(),
    }


def write_key(path: Path, exam: Exam, fingerprint: str) -> None:
    payload = json.dumps(build_key(exam, fingerprint), ensure_ascii=False, indent=2)
    path.write_text(payload + "\n", encoding="utf-8")
