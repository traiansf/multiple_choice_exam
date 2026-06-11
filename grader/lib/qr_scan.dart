/// QR payload codec. Format is produced by generator/src/mcexam/qr.py and
/// documented in README 'QR payload' — bump the version on ANY field change:
/// `v1|<variant_id>|<seed>|<n_easy>|<n_medium>|<n_hard>|<source_fp>`.
/// Camera scanning (mobile_scanner) wires into this in a later milestone.
library;

class QrPayloadException implements Exception {
  QrPayloadException(this.message);

  final String message;

  @override
  String toString() => 'QrPayloadException: $message';
}

class QrPayload {
  const QrPayload({
    required this.variantId,
    required this.seed,
    required this.nEasy,
    required this.nMedium,
    required this.nHard,
    required this.sourceFingerprint,
  });

  static const String supportedVersion = 'v1';
  static final BigInt _two64 = BigInt.one << 64;

  final int variantId;
  final BigInt seed;
  final int nEasy;
  final int nMedium;
  final int nHard;
  final String sourceFingerprint;

  Map<String, int> get counts => {
    'easy': nEasy,
    'medium': nMedium,
    'hard': nHard,
  };

  static QrPayload decode(String text) {
    final parts = text.split('|');
    if (parts.length != 7) {
      throw QrPayloadException(
        'malformed QR payload: expected 7 fields, got ${parts.length}',
      );
    }
    if (parts[0] != supportedVersion) {
      throw QrPayloadException(
        "unsupported QR payload version '${parts[0]}' (this build reads"
        " '$supportedVersion')",
      );
    }
    final seed = BigInt.tryParse(parts[2]);
    if (seed == null || seed < BigInt.zero || seed >= _two64) {
      throw QrPayloadException(
        "seed '${parts[2]}' is not an unsigned 64-bit integer",
      );
    }
    if (parts[6].isEmpty) {
      throw QrPayloadException('source fingerprint field is empty');
    }
    return QrPayload(
      variantId: _count(parts[1], 'variant id'),
      seed: seed,
      nEasy: _count(parts[3], 'n_easy count'),
      nMedium: _count(parts[4], 'n_medium count'),
      nHard: _count(parts[5], 'n_hard count'),
      sourceFingerprint: parts[6],
    );
  }

  static int _count(String text, String what) {
    final value = int.tryParse(text);
    if (value == null || value < 0) {
      throw QrPayloadException("$what '$text' is not a non-negative integer");
    }
    return value;
  }
}
