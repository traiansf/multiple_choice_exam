/// QR payload codec. Format is produced by generator/src/mcexam/qr.py and
/// documented in README 'QR payload' — bump the version on ANY field change:
/// `v1|<variant_id>|<seed>|<n_easy>|<n_medium>|<n_hard>|<source_fp>`
/// `v2|<variant_id>|<seed>|<source_fp>|<count_1>,<count_2>,...`
/// v1 sheets come from legacy exams (Easy/Medium/Hard, no cases) and count
/// questions; v2 sheets give, per section in key order, the number of units
/// (questions or cases) drawn.
library;

class QrPayloadException implements Exception {
  QrPayloadException(this.message);

  final String message;

  @override
  String toString() => 'QrPayloadException: $message';
}

class QrPayload {
  const QrPayload({
    required this.version,
    required this.variantId,
    required this.seed,
    required this.countList,
    required this.sourceFingerprint,
  });

  static const List<String> supportedVersions = ['v1', 'v2'];
  static final BigInt _two64 = BigInt.one << 64;

  /// 'v1' or 'v2'; must match the key file version (1 or 2).
  final String version;
  final int variantId;
  final BigInt seed;

  /// Units drawn per section, in key order (v1: easy, medium, hard).
  final List<int> countList;
  final String sourceFingerprint;

  int get keyVersion => version == 'v1' ? 1 : 2;

  /// v1 counts by section key (the v1 keys are always easy/medium/hard).
  Map<String, int> get counts => countsFor(const ['easy', 'medium', 'hard']);

  /// Counts by the given section keys, in order.
  Map<String, int> countsFor(List<String> keys) {
    if (keys.length != countList.length) {
      throw QrPayloadException(
        'QR has ${countList.length} section counts but the key has'
        ' ${keys.length} sections',
      );
    }
    return {for (var i = 0; i < keys.length; i++) keys[i]: countList[i]};
  }

  static QrPayload decode(String text) {
    final parts = text.split('|');
    if (parts[0] == 'v2') return _decodeV2(parts);
    if (parts.length != 7) {
      throw QrPayloadException(
        'malformed QR payload: expected 7 fields, got ${parts.length}',
      );
    }
    if (parts[0] != 'v1') {
      throw QrPayloadException(
        "unsupported QR payload version '${parts[0]}' (this build reads"
        " ${supportedVersions.map((v) => "'$v'").join(' and ')})",
      );
    }
    if (parts[6].isEmpty) {
      throw QrPayloadException('source fingerprint field is empty');
    }
    return QrPayload(
      version: 'v1',
      variantId: _count(parts[1], 'variant id'),
      seed: _seed(parts[2]),
      countList: List.unmodifiable([
        _count(parts[3], 'n_easy count'),
        _count(parts[4], 'n_medium count'),
        _count(parts[5], 'n_hard count'),
      ]),
      sourceFingerprint: parts[6],
    );
  }

  static QrPayload _decodeV2(List<String> parts) {
    if (parts.length != 5) {
      throw QrPayloadException(
        'malformed v2 QR payload: expected 5 fields, got ${parts.length}',
      );
    }
    if (parts[3].isEmpty) {
      throw QrPayloadException('source fingerprint field is empty');
    }
    return QrPayload(
      version: 'v2',
      variantId: _count(parts[1], 'variant id'),
      seed: _seed(parts[2]),
      countList: List.unmodifiable([
        for (final count in parts[4].split(',')) _count(count, 'section count'),
      ]),
      sourceFingerprint: parts[3],
    );
  }

  static BigInt _seed(String text) {
    final seed = BigInt.tryParse(text);
    if (seed == null || seed < BigInt.zero || seed >= _two64) {
      throw QrPayloadException(
        "seed '$text' is not an unsigned 64-bit integer",
      );
    }
    return seed;
  }

  static int _count(String text, String what) {
    final value = int.tryParse(text);
    if (value == null || value < 0) {
      throw QrPayloadException("$what '$text' is not a non-negative integer");
    }
    return value;
  }
}
