import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trip_cal/services/rates.dart';
import 'package:trip_cal/storage.dart';

void main() {
  late Storage store;
  sqfliteFfiInit();
  setUp(() async => store = await Storage.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
  tearDown(() => store.db.close());
  test('정상 응답 저장, 중복 요청 합치기, 오프라인 캐시', () async {
    var calls = 0;
    final gate = Completer<void>();
    final service = RateService(store, client: MockClient((req) async {
      calls++;
      expect(req.url.toString(), 'https://api.frankfurter.dev/v2/rate/JPY/KRW');
      await gate.future;
      return http.Response('{"base":"JPY","quote":"KRW","rate":9.5,"date":"2026-11-04"}', 200);
    }));
    final a = service.latest('JPY'), b = service.latest('JPY');
    gate.complete();
    expect((await a).rate, '9.5');
    expect((await b).date, '2026-11-04');
    expect(calls, 1);
    final offline = RateService(store, client: MockClient((r) async => throw http.ClientException('offline')));
    final q = await offline.latest('JPY');
    expect(q.cached, true);
    expect(q.source, 'Frankfurter');
    expect(q.date, '2026-11-04');
  });
  test('캐시가 없으면 수동 입력을 안내하고 잘못된 응답은 저장하지 않는다', () async {
    final s = RateService(store, client: MockClient((r) async => http.Response('{"base":"USD","quote":"KRW","rate":0,"date":"2026-11-04"}', 200)));
    await expectLater(s.latest('JPY'), throwsFormatException);
    expect(await s.cached('JPY'), isNull);
    await expectLater(s.manual('JPY', '0', '2026-11-04'), throwsFormatException);
    await expectLater(s.manual('JPY', '-1', '2026-11-04'), throwsFormatException);
    final manual = await s.manual('JPY', '9.25', '2026-11-04');
    expect(manual.source, '직접 입력');
    expect((await s.cached('JPY'))!.rate, '9.25');
  });
  test('환율 조회만으로 저장된 경비 금액을 변경하지 않는다', () async {
    final id = await store.createTrip({'name': '일본', 'country': 'JP', 'budget': '0'});
    await store.saveExpense(id, {'name': '호텔', 'category': '숙박비', 'amount': '100', 'currency': 'JPY', 'rate': '9', 'rate_source': '직접 입력'});
    final s = RateService(store, client: MockClient((r) async => http.Response('{"base":"JPY","quote":"KRW","rate":10,"date":"2026-11-04"}', 200)));
    await s.latest('JPY');
    expect((await store.expenses(id)).single['won'], '900');
  });
}
