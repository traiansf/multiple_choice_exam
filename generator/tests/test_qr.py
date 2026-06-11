import pytest

from mcexam.qr import QrPayload, decode_payload, encode_payload, qr_png

PAYLOAD = QrPayload(
    variant_id=3,
    seed=18446744073709551615,  # 2**64 - 1: must survive the round trip
    n_easy=10,
    n_medium=8,
    n_hard=2,
    source_fingerprint="ab12cd34",
)


def test_encode_format_is_pipe_separated_v1() -> None:
    assert encode_payload(PAYLOAD) == "v1|3|18446744073709551615|10|8|2|ab12cd34"


def test_round_trip() -> None:
    assert decode_payload(encode_payload(PAYLOAD)) == PAYLOAD


def test_decode_rejects_wrong_field_count() -> None:
    with pytest.raises(ValueError, match="expected 7 fields"):
        decode_payload("v1|1|2|3")


def test_decode_rejects_unknown_version() -> None:
    with pytest.raises(ValueError, match="version"):
        decode_payload("v9|3|5|10|8|2|ab12cd34")


def test_qr_png_produces_png_bytes() -> None:
    data = qr_png(encode_payload(PAYLOAD))
    assert data.startswith(b"\x89PNG\r\n\x1a\n")
