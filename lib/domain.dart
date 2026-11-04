import 'package:decimal/decimal.dart';

class Country {
  const Country(this.code, this.name, this.flag, this.currency, this.symbol, this.fractionDigits);
  final String code, name, flag, currency, symbol;
  final int fractionDigits;
}

const countries = <Country>[
  Country('KR','대한민국','🇰🇷','KRW','₩',0),
  Country('JP','일본','🇯🇵','JPY','¥',0),
  Country('US','미국','🇺🇸','USD','\$',2),
  Country('TH','태국','🇹🇭','THB','฿',2),
  Country('VN','베트남','🇻🇳','VND','₫',0),
  Country('TW','대만','🇹🇼','TWD','NT\$',2),
  Country('CN','중국','🇨🇳','CNY','¥',2),
  Country('PH','필리핀','🇵🇭','PHP','₱',2),
  Country('SG','싱가포르','🇸🇬','SGD','S\$',2),
  Country('MY','말레이시아','🇲🇾','MYR','RM',2),
  Country('ID','인도네시아','🇮🇩','IDR','Rp',2),
  Country('FR','프랑스','🇫🇷','EUR','€',2),
  Country('DE','독일','🇩🇪','EUR','€',2),
  Country('IT','이탈리아','🇮🇹','EUR','€',2),
  Country('ES','스페인','🇪🇸','EUR','€',2),
  Country('GB','영국','🇬🇧','GBP','£',2),
  Country('AU','호주','🇦🇺','AUD','A\$',2),
  Country('CA','캐나다','🇨🇦','CAD','C\$',2),
  Country('NZ','뉴질랜드','🇳🇿','NZD','NZ\$',2),
  Country('CH','스위스','🇨🇭','CHF','Fr',2),
  Country('HK','홍콩','🇭🇰','HKD','HK\$',2),
  Country('IN','인도','🇮🇳','INR','₹',2),
  Country('MX','멕시코','🇲🇽','MXN','MX\$',2),
  Country('AT','오스트리아','🇦🇹','EUR','€',2),
  Country('PT','포르투갈','🇵🇹','EUR','€',2),
  Country('NL','네덜란드','🇳🇱','EUR','€',2),
  Country('FI','핀란드','🇫🇮','EUR','€',2),
  Country('GR','그리스','🇬🇷','EUR','€',2),

];

const categories = <String>['항공권 / 기차','숙박비','식비','교통비','관광 / 액티비티','쇼핑','여행자보험','통신비','기타'];

/// Keep decimal input and exchange rates as strings to avoid floating point loss.
BigInt convertToWon(String amount, String rate, {int fractionDigits = 2}) {
  if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(amount) ||
      !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(rate)) {
    throw const FormatException('숫자를 확인해 주세요.');
  }
  final parts = amount.split('.');
  if (parts.length == 2 && parts[1].length > fractionDigits) {
    throw const FormatException('통화의 소수 자릿수를 확인해 주세요.');
  }
  final a = Decimal.parse(amount);
  final r = Decimal.parse(rate);
  if (r <= Decimal.zero) throw const FormatException('환율은 0보다 커야 합니다.');
  // All values are non-negative; round half up to the nearest won.
  final product = a * r;
  final text = product.toString();
  final segments = text.split('.');
  var result = BigInt.parse(segments[0]);
  if (segments.length > 1 && segments[1].isNotEmpty && int.parse(segments[1][0]) >= 5) {
    result += BigInt.one;
  }
  return result;
}

String formatWon(BigInt value) {
  final negative = value.isNegative;
  final digits = value.abs().toString();
  final result = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) result.write(',');
    result.write(digits[i]);
  }
  return '${negative ? '-' : ''}${result}원';
}

String dDay(DateTime? departure, DateTime now) {
  if (departure == null) return '출발일 미정';
  final date = DateTime.utc(departure.year, departure.month, departure.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final days = date.difference(today).inDays;
  if (days == 0) return 'D-Day';
  return days > 0 ? 'D-$days' : 'D+${-days}';
}

Country countryByCode(String code) => countries.firstWhere((c) => c.code == code);
Country currencyInfo(String code) => countries.firstWhere((c) => c.currency == code);
typedef DataRow = Map<String, Object?>;

BigInt totalWon(Iterable<DataRow> expenses) => expenses.fold(BigInt.zero,
    (sum, row) => sum + BigInt.parse(row['won']! as String));

Map<String, BigInt> categoryTotals(Iterable<DataRow> expenses) {
  final result = <String, BigInt>{};
  for (final row in expenses) {
    final key = row['category']! as String;
    result[key] = (result[key] ?? BigInt.zero) + BigInt.parse(row['won']! as String);
  }
  return result;
}

/// Bounded conversion is only used for display; money remains BigInt/Decimal.
double budgetRatio(BigInt spent, BigInt budget) {
  if (budget <= BigInt.zero) return spent > BigInt.zero ? 1 : 0;
  final basisPoints = spent * BigInt.from(10000) ~/ budget;
  return basisPoints.clamp(BigInt.zero, BigInt.from(100000000)).toDouble() / 10000;
}

DateTime calendarDate(DateTime date) => DateTime.utc(date.year, date.month, date.day);
bool notificationEligible(DataRow trip, DateTime now) => trip['departure'] != null &&
    !calendarDate(DateTime.parse(trip['departure']! as String)).isBefore(calendarDate(now));

String dateText(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

const defaultItems = <String, List<String>>{
  '서류': ['항공권 / 기차표', '숙박 예약 확인'],
  '전자기기': ['휴대폰', '충전기', '보조배터리'],
  '금융': ['현금', '결제 카드'],
  '개인용품': ['의류', '세면도구', '상비약', '개인 위생용품'],
};
const overseasItems = <String, List<String>>{
  '서류': ['여권', '비자 및 입국 조건 확인'],
  '전자기기': ['멀티어댑터'],
  '금융': ['해외 결제 카드', '환전', '여행자보험'],
  '통신 (필요한 방식만 선택)': ['eSIM · 유심 · 로밍 중 필요한 방식 확인'],
};
