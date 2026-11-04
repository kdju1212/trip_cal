import 'package:flutter_test/flutter_test.dart';
import 'package:trip_cal/domain.dart';

void main() {
  test('혼합 통화 예산은 원래 금액과 적용 환율로 계산한다', () {
    final total = convertToWon('500000', '1', fractionDigits: 0) +
        convertToWon('30000', '9.5', fractionDigits: 0) +
        convertToWon('10000', '9.5', fractionDigits: 0) +
        convertToWon('20000', '1', fractionDigits: 0);
    expect(total, BigInt.from(900000));
    expect(formatWon(BigInt.from(2000000) - total), '1,100,000원');
  });
  test('양수 환율, 통화 소수 자릿수와 반올림을 적용한다', () {
    expect(convertToWon('1.25', '10'), BigInt.from(13));
    expect(() => convertToWon('-1', '1'), throwsFormatException);
    expect(() => convertToWon('1', '0'), throwsFormatException);
    expect(() => convertToWon('1.5', '1', fractionDigits: 0), throwsFormatException);
    expect(convertToWon('999999999999999999', '2', fractionDigits: 0), BigInt.parse('1999999999999999998'));
  });
  test('출발일 없음, 당일, 미래와 과거', () {
    final now = DateTime(2026, 11, 4, 23);
    expect(dDay(null, now), '출발일 미정');
    expect(dDay(DateTime(2026, 11, 4), now), 'D-Day');
    expect(dDay(DateTime(2026, 11, 18), now), 'D-14');
    expect(dDay(DateTime(2026, 11, 3), now), 'D+1');
  });
  test('예산 0과 큰 금액의 시각화 비율은 유한한 값이다', () {
    expect(budgetRatio(BigInt.zero, BigInt.zero), 0);
    expect(budgetRatio(BigInt.one, BigInt.zero), 1);
    expect(budgetRatio(BigInt.from(3), BigInt.from(2)), 1.5);
    expect(budgetRatio(BigInt.parse('999999999999999999999999999'), BigInt.one).isFinite, true);
  });
  test('출발일 없는 여행과 과거 여행은 알림 대상에서 제외한다', () {
    expect(notificationEligible({'departure': null}, DateTime(2026,11,4)), false);
    expect(notificationEligible({'departure': '2026-11-03'}, DateTime(2026,11,4)), false);
    expect(notificationEligible({'departure': '2026-11-04'}, DateTime(2026,11,4,23)), true);
  });
  test('국가 ISO 코드와 통화 연결이 중복되지 않는다', () {
    expect(countries.map((e) => e.code).toSet().length, countries.length);
    for (final c in countries) {
      expect(c.code, matches(RegExp(r'^[A-Z]{2}$')));
      expect(c.currency, matches(RegExp(r'^[A-Z]{3}$')));
    }
  });
  test('유로 국가를 독립적으로 선택할 수 있다', () {
    expect(countries.where((c) => c.currency == 'EUR').length, greaterThanOrEqualTo(4));
    expect(countries.firstWhere((c) => c.code == 'JP').currency, 'JPY');
  });
}
