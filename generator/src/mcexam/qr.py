"""QR payload codec (format mirrored by grader/lib/qr_scan.dart) and QR rendering.

Payload format (README 'QR payload') — bump QR_VERSION on ANY field change:
    v1|<variant_id>|<seed>|<n_easy>|<n_medium>|<n_hard>|<source_fp>
"""

import io
from dataclasses import dataclass

import segno

QR_VERSION = "v1"


@dataclass(frozen=True)
class QrPayload:
    variant_id: int
    seed: int
    n_easy: int
    n_medium: int
    n_hard: int
    source_fingerprint: str


def encode_payload(payload: QrPayload) -> str:
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


def decode_payload(text: str) -> QrPayload:
    parts = text.split("|")
    if len(parts) != 7:
        raise ValueError(f"malformed QR payload: expected 7 fields, got {len(parts)}")
    if parts[0] != QR_VERSION:
        raise ValueError(
            f"unsupported QR payload version {parts[0]!r} (this build reads {QR_VERSION!r})"
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
