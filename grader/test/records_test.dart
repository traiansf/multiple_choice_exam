import 'package:flutter_test/flutter_test.dart';
import 'package:grader/records.dart';

void main() {
  final t1 = DateTime.utc(2026, 6, 11, 10, 0);
  final t2 = DateTime.utc(2026, 6, 11, 10, 5);

  test('records are kept sorted by variant id', () {
    final book = GradeBook()
      ..record(GradeRecord(variantId: 7, score: 3, total: 5, recordedAt: t1))
      ..record(GradeRecord(variantId: 2, score: 5, total: 5, recordedAt: t1));
    expect([for (final r in book.records) r.variantId], [2, 7]);
    expect(book.length, 2);
    expect(book.isEmpty, isFalse);
  });

  test('re-recording a variant replaces the previous grade', () {
    final book = GradeBook()
      ..record(GradeRecord(variantId: 3, score: 2, total: 5, recordedAt: t1))
      ..record(GradeRecord(variantId: 3, score: 4, total: 5, recordedAt: t2));
    expect(book.length, 1);
    expect(book.records.single.score, 4);
    expect(book.records.single.recordedAt, t2);
  });

  test('clear empties the book', () {
    final book = GradeBook()
      ..record(GradeRecord(variantId: 1, score: 1, total: 5, recordedAt: t1))
      ..clear();
    expect(book.isEmpty, isTrue);
  });

  test('toCsv produces the exact report format', () {
    final book = GradeBook()
      ..record(GradeRecord(variantId: 12, score: 4, total: 5, recordedAt: t2))
      ..record(
        GradeRecord(
          variantId: 1,
          score: 5,
          total: 5,
          recordedAt: t1,
          manual: true,
          studentName: 'Ada Lovelace',
        ),
      );
    expect(
      book.toCsv(),
      'variant_id,student,score,total,percent,manual,recorded_at\n'
      '1,Ada Lovelace,5,5,100.0,true,2026-06-11T10:00:00.000Z\n'
      '12,,4,5,80.0,false,2026-06-11T10:05:00.000Z\n',
    );
  });

  test('toCsv quotes student names containing commas or quotes', () {
    final book = GradeBook()
      ..record(
        GradeRecord(
          variantId: 1,
          score: 3,
          total: 5,
          recordedAt: t1,
          studentName: 'Smith, Jane',
        ),
      )
      ..record(
        GradeRecord(
          variantId: 2,
          score: 4,
          total: 5,
          recordedAt: t1,
          studentName: 'Pat "Ace" Doe',
        ),
      );
    expect(
      book.toCsv(),
      'variant_id,student,score,total,percent,manual,recorded_at\n'
      '1,"Smith, Jane",3,5,60.0,false,2026-06-11T10:00:00.000Z\n'
      '2,"Pat ""Ace"" Doe",4,5,80.0,false,2026-06-11T10:00:00.000Z\n',
    );
  });

  test('toCsv quotes a bare carriage return in a name', () {
    final book = GradeBook()
      ..record(
        GradeRecord(
          variantId: 1,
          score: 1,
          total: 5,
          recordedAt: t1,
          studentName: 'Bad\rName',
        ),
      );
    expect(book.toCsv(), contains('"Bad\rName"'));
  });

  test('recordFor looks up by variant id', () {
    final book = GradeBook()
      ..record(GradeRecord(variantId: 3, score: 2, total: 5, recordedAt: t1));
    expect(book.recordFor(3)!.score, 2);
    expect(book.recordFor(4), isNull);
  });

  test('percent guards against a zero total', () {
    final record = GradeRecord(
      variantId: 1,
      score: 0,
      total: 0,
      recordedAt: t1,
    );
    expect(record.percent, 0.0);
  });

  test('empty book CSV is the header only', () {
    expect(
      GradeBook().toCsv(),
      'variant_id,student,score,total,percent,manual,recorded_at\n',
    );
  });
}
