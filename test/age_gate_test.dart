import 'package:flutter_test/flutter_test.dart';
import 'package:in_range/core/session/age_gate.dart';

void main() {
  test('age gate rejects the day before the eighteenth birthday', () {
    final today = DateTime(2026, 7, 11);
    expect(AgeGate.isAdult(DateTime(2008, 7, 12), onDate: today), isFalse);
    expect(AgeGate.isAdult(DateTime(2008, 7, 11), onDate: today), isTrue);
  });

  test('ISO parser rejects normalized invalid calendar dates', () {
    expect(() => AgeGate.parseIsoDate('2000-02-30'), throwsFormatException);
    expect(AgeGate.format(AgeGate.parseIsoDate('2000-02-29')), '2000-02-29');
  });
}
