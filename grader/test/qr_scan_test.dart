import 'package:flutter_test/flutter_test.dart';
import 'package:grader/qr_scan.dart';

void main() {
  test('decodes a valid v1 payload including max seed', () {
    final p = QrPayload.decode('v1|3|18446744073709551615|10|8|2|ab12cd34');
    expect(p.variantId, 3);
    expect(p.seed, BigInt.parse('18446744073709551615'));
    expect(p.counts, {'easy': 10, 'medium': 8, 'hard': 2});
    expect(p.sourceFingerprint, 'ab12cd34');
  });

  void expectRejects(String text, Pattern message) {
    expect(
      () => QrPayload.decode(text),
      throwsA(
        isA<QrPayloadException>().having(
          (e) => e.message,
          'message',
          contains(message),
        ),
      ),
    );
  }

  test('rejects wrong field count', () {
    expectRejects('v1|1|2|3', 'expected 7 fields');
  });

  test('rejects unknown version', () {
    expectRejects('v9|3|5|10|8|2|ab12cd34', 'version');
  });

  test('rejects non-numeric and negative fields', () {
    expectRejects('v1|x|5|10|8|2|ab12cd34', 'variant id');
    expectRejects('v1|3|-5|10|8|2|ab12cd34', 'seed');
    expectRejects('v1|3|5|-1|8|2|ab12cd34', 'count');
  });

  test('rejects seed exceeding 64 bits', () {
    expectRejects('v1|3|18446744073709551616|10|8|2|ab12cd34', 'seed');
  });
}
