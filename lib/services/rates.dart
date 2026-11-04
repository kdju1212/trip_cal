import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../storage.dart';

class RateQuote {
  const RateQuote(this.currency, this.rate, this.date, this.source, {this.cached = false});
  final String currency, rate, date, source;
  final bool cached;
  factory RateQuote.fromMap(Map<String, Object?> row, {bool cached = false}) =>
      RateQuote(row['currency']! as String, row['rate']! as String, row['date']! as String, row['source']! as String, cached: cached);
}
class RateService {
  RateService(this.storage, {http.Client? client}) : client = client ?? http.Client();
  final Storage storage;
  final http.Client client;
  final _inflight = <String, Future<RateQuote>>{};
  Future<RateQuote?> cached(String code) async {
    if (code == 'KRW') return const RateQuote('KRW', '1', '', 'KRW');
    final rows = await storage.db.query('rates', where: 'currency = ?', whereArgs: [code]);
    return rows.isEmpty ? null : RateQuote.fromMap(rows.single, cached: true);
  }
  Future<RateQuote> latest(String code) {
    if (code == 'KRW') return Future.value(const RateQuote('KRW', '1', '', 'KRW'));
    return _inflight.putIfAbsent(code, () => _fetch(code).whenComplete(() => _inflight.remove(code)));
  }
  Future<RateQuote> _fetch(String code) async {
    try {
      final response = await client.get(Uri.https('api.frankfurter.dev', '/v2/rate/$code/KRW')).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw const FormatException('환율 응답 오류');
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['base'] != code || body['quote'] != 'KRW') throw const FormatException('통화 불일치');
      // Preserve the numeric JSON token instead of passing money through double.
      final token = RegExp(r'"rate"\s*:\s*(\d+(?:\.\d+)?)(?=\s*[,}])').firstMatch(response.body);
      if (token == null) throw const FormatException('환율 숫자 형식 오류');
      final rate = token.group(1)!;
      _validateRate(rate);
      final date = body['date'] as String;
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) || DateTime.tryParse(date) == null) throw const FormatException('날짜 오류');
      final quote = RateQuote(code, rate, date, 'Frankfurter');
      await _save(quote);
      return quote;
    } catch (_) {
      final saved = await cached(code);
      if (saved != null) return saved;
      throw const FormatException('환율을 가져오지 못했어요. 인터넷 연결을 확인하거나 환율을 직접 입력해 주세요.');
    }
  }
  void _validateRate(String rate) {
    if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(rate) || rate.length > 40 || Decimal.parse(rate) <= Decimal.zero) {
      throw const FormatException('0보다 큰 환율을 입력해 주세요.');
    }
  }
  Future<RateQuote> manual(String code, String rate, String date) async {
    _validateRate(rate);
    final quote = RateQuote(code, rate, date, '직접 입력');
    await _save(quote);
    return quote;
  }
  Future<void> _save(RateQuote q) async {
    await storage.db.insert('rates', {'currency': q.currency, 'rate': q.rate, 'date': q.date, 'source': q.source}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
