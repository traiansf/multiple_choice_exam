/// In-memory grade records, keyed by the QR's variant id, with CSV export
/// (issue #4). Re-recording a variant replaces its grade — re-scanning a
/// sheet updates the score. Pure data, no UI or storage.
library;

class GradeRecord {
  const GradeRecord({
    required this.variantId,
    required this.score,
    required this.total,
    required this.recordedAt,
    this.manual = false,
  });

  final int variantId;
  final int score;
  final int total;
  final DateTime recordedAt;

  /// True when the grader entered the score by hand (review-flagged sheet)
  /// instead of confirming the automatic OMR grading.
  final bool manual;

  double get percent => total == 0 ? 0 : score / total * 100;
}

class GradeBook {
  final Map<int, GradeRecord> _byVariant = {};

  bool get isEmpty => _byVariant.isEmpty;
  int get length => _byVariant.length;

  /// Grades sorted by variant id.
  List<GradeRecord> get records {
    final sorted = _byVariant.values.toList()
      ..sort((a, b) => a.variantId.compareTo(b.variantId));
    return List.unmodifiable(sorted);
  }

  /// Adds the grade, replacing any earlier record of the same variant.
  void record(GradeRecord grade) => _byVariant[grade.variantId] = grade;

  void clear() => _byVariant.clear();

  /// The report: one row per variant, sorted, ISO-8601 UTC timestamps.
  String toCsv() {
    final buffer = StringBuffer(
      'variant_id,score,total,percent,manual,recorded_at\n',
    );
    for (final r in records) {
      buffer.writeln(
        '${r.variantId},${r.score},${r.total},'
        '${r.percent.toStringAsFixed(1)},${r.manual},'
        '${r.recordedAt.toUtc().toIso8601String()}',
      );
    }
    return buffer.toString();
  }
}
