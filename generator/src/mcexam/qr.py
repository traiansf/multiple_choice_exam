"""QR payload codec (format mirrored by grader/lib/qr_scan.dart) and QR rendering.

Payload formats (README 'QR payload') — bump the version on ANY field change:
    v1|<variant_id>|<seed>|<n_easy>|<n_medium>|<n_hard>|<source_fp>
    v2|<variant_id>|<seed>|<source_fp>|<count_1>,<count_2>,...
v1 is written for legacy exams (Easy/Medium/Hard, no cases) and counts
questions; v2 is written for every other exam and gives, per section in key
order, the number of units (questions or cases) drawn.
"""

import io
from dataclasses import dataclass

import segno

QR_VERSION = "v1"
QR_VERSION_V2 = "v2"


@dataclass(frozen=True)
class QrPayload:
    variant_id: int
    seed: int
    n_easy: int
    n_medium: int
    n_hard: int
    source_fingerprint: str


@dataclass(frozen=True)
class QrPayloadV2:
    variant_id: int
    seed: int
    counts: tuple[int, ...]  # units drawn per section, in key order
    source_fingerprint: str


def encode_payload(payload: QrPayload | QrPayloadV2) -> str:
    if isinstance(payload, QrPayloadV2):
        return "|".join(
            [
                QR_VERSION_V2,
                str(payload.variant_id),
                str(payload.seed),
                payload.source_fingerprint,
                ",".join(str(count) for count in payload.counts),
            ]
        )
    return "|".join(
        [
            QR_VERSION,
            str(payload.variant_id),
            str(payload.seed),
            str(payload.n_easy),
            str(payload.n_medium),
            str(payload.n_hard),
            payload.source_fingerprint,
        ]
    )


def decode_payload(text: str) -> QrPayload | QrPayloadV2:
    parts = text.split("|")
    if parts[0] == QR_VERSION_V2:
        if len(parts) != 5:
            raise ValueError(f"malformed v2 QR payload: expected 5 fields, got {len(parts)}")
        return QrPayloadV2(
            variant_id=int(parts[1]),
            seed=int(parts[2]),
            counts=tuple(int(count) for count in parts[4].split(",")),
            source_fingerprint=parts[3],
        )
    if len(parts) != 7:
        raise ValueError(f"malformed QR payload: expected 7 fields, got {len(parts)}")
    if parts[0] != QR_VERSION:
        raise ValueError(
            f"unsupported QR payload version {parts[0]!r}"
            f" (this build reads {QR_VERSION!r} and {QR_VERSION_V2!r})"
        )
    return QrPayload(
        variant_id=int(parts[1]),
        seed=int(parts[2]),
        n_easy=int(parts[3]),
        n_medium=int(parts[4]),
        n_hard=int(parts[5]),
        source_fingerprint=parts[6],
    )


def qr_png(payload: str, scale: int = 8) -> bytes:
    """Render the payload as a PNG (error level M, 2-module quiet zone)."""
    buffer = io.BytesIO()
    segno.make(payload, error="m", micro=False).save(buffer, kind="png", scale=scale, border=2)
    return buffer.getvalue()
