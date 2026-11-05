import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trip_cal/domain.dart';
import 'package:trip_cal/storage.dart';

void main() {
  late Storage store;
  sqfliteFfiInit();
  setUp(() async {
    store = await Storage.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });
  tearDown(() async => store.db.close());
  Future<int> trip({String country = 'JP'}) => store.createTrip({
    'name': '테스트 여행',
    'country': country,
    'budget': '2000000',
    'departure': null,
  });
  DbRow expense(String name, String amount, String currency, String rate) => {
    'name': name,
    'category': '숙박비',
    'amount': amount,
    'currency': currency,
    'rate': rate,
    'rate_date': '2026-11-04',
    'rate_source': '직접 입력',
  };

  test('출발일 없이 생성, 수정 후 원래 경비 통화 유지', () async {
    final id = await trip();
    await store.saveExpense(id, expense('호텔', '30000', 'JPY', '9.5'));
    await store.updateTrip(id, {
      'name': '미국으로 변경',
      'country': 'US',
      'budget': '3000000',
    });
    final row = (await store.trips()).single;
    expect(row['departure'], isNull);
    expect(row['country'], 'US');
    final e = (await store.expenses(id)).single;
    expect(e['currency'], 'JPY');
    expect(e['won'], '285000');
  });
  test('독립된 혼합 통화 합계, 경비 편집 삭제와 예산 초과', () async {
    final id = await trip();
    await store.saveExpense(
      id,
      expense('항공', '500000', 'KRW', '100'),
    ); // KRW always rate=1.
    await store.saveExpense(id, expense('호텔', '30000', 'JPY', '9.5'));
    await store.saveExpense(id, expense('식사', '10000', 'JPY', '9.5'));
    await store.saveExpense(id, expense('보험', '20000', 'KRW', '1'));
    expect(totalWon(await store.expenses(id)), BigInt.from(900000));
    final e = (await store.expenses(id)).first;
    await store.saveExpense(
      id,
      expense('변경', '3000000', 'KRW', '1'),
      id: e['id']! as int,
    );
    expect(
      totalWon(await store.expenses(id)),
      greaterThan(BigInt.from(2000000)),
    );
    await store.db.delete('expenses', where: 'id = ?', whereArgs: [e['id']]);
    expect(totalWon(await store.expenses(id)), BigInt.from(880000));
  });
  test('복제는 경비와 준비물, 구매 선택을 독립 복사하며 삭제는 cascade', () async {
    final id = await trip();
    await store.saveExpense(id, expense('호텔', '100', 'JPY', '9.5'));
    final item = (await store.checklist(id)).first;
    await store.db.update(
      'checklist',
      {'checked': 1},
      where: 'id = ?',
      whereArgs: [item['id']],
    );
    await store.db.insert('purchases', {
      'trip_id': id,
      'item': 'esim',
      'needed': 1,
    });
    final copy = await store.duplicateTrip(id);
    expect((await store.checklist(copy)).first['checked'], 1);
    await store.db.update(
      'checklist',
      {'checked': 0},
      where: 'trip_id = ?',
      whereArgs: [copy],
    );
    expect((await store.checklist(id)).first['checked'], 1);
    await store.setSetting('notificationTrip', id);
    await store.setSetting('notificationEnabled', true);
    await store.deleteTrip(id);
    expect(await store.expenses(id), isEmpty);
    expect(await store.checklist(id), isEmpty);
    expect(await store.setting('notificationEnabled', true), false);
    expect((await store.expenses(copy)).length, 1);
    expect(
      await store.db.query(
        'purchases',
        where: 'trip_id = ?',
        whereArgs: [copy],
      ),
      hasLength(1),
    );
  });
  test('국내 준비물에는 해외 전용 준비물이 없다', () async {
    final id = await trip(country: 'KR');
    final names = (await store.checklist(id)).map((e) => e['name']);
    expect(names, containsAll(['숙박 예약 확인', '충전기', '개인 위생용품']));
    expect(names, isNot(contains('여권')));
    expect(names, isNot(contains('멀티어댑터')));
  });
  test('환율 재계산은 원본 금액을 보존하고 반복해도 중복 환산하지 않는다', () async {
    final id = await trip();
    await store.saveExpense(id, expense('호텔', '30000', 'JPY', '9.5'));
    final e = (await store.expenses(id)).single;
    final preview = {...e, 'rate': '10', 'rate_date': '2026-11-05'};
    await store.recalculate(id, [preview]);
    await store.recalculate(id, [preview]);
    final updated = (await store.expenses(id)).single;
    expect(updated['amount'], '30000');
    expect(updated['won'], '300000');
  });
  test('재계산 미리보기 후 경비가 수정되면 오래된 계산을 적용하지 않는다', () async {
    final id = await trip();
    await store.saveExpense(id, expense('호텔', '100', 'JPY', '9'));
    final old = (await store.expenses(id)).single;
    await store.saveExpense(
      id,
      expense('호텔', '200', 'JPY', '9'),
      id: old['id']! as int,
    );
    await expectLater(
      store.recalculate(id, [
        {...old, 'rate': '10'},
      ]),
      throwsFormatException,
    );
    final current = (await store.expenses(id)).single;
    expect(current['amount'], '200');
    expect(current['won'], '1800');
  });
  test('DB 재연결 후 데이터와 설정 유지', () async {
    final path =
        '${await databaseFactoryFfi.getDatabasesPath()}/trip_cal_persistence_test.db';
    await databaseFactoryFfi.deleteDatabase(path);
    final first = await Storage.open(factory: databaseFactoryFfi, path: path);
    await first.createTrip({'name': '유지 여행', 'country': 'KR', 'budget': '0'});
    await first.setSetting('theme', 'dark');
    await first.db.close();
    final second = await Storage.open(factory: databaseFactoryFfi, path: path);
    expect((await second.trips()).single['name'], '유지 여행');
    expect(await second.setting('theme', 'system'), 'dark');
    await second.db.close();
    await databaseFactoryFfi.deleteDatabase(path);
  });
  test('v1 DB 마이그레이션은 기존 여행과 경비를 보존한다', () async {
    final path =
        '${await databaseFactoryFfi.getDatabasesPath()}/trip_cal_migration_test.db';
    await databaseFactoryFfi.deleteDatabase(path);
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE trips (id INTEGER PRIMARY KEY, name TEXT NOT NULL, country TEXT NOT NULL, departure TEXT, budget TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE expenses (id INTEGER PRIMARY KEY, trip_id INTEGER, name TEXT, category TEXT, amount TEXT, currency TEXT, rate TEXT, won TEXT, rate_date TEXT, rate_source TEXT)',
          );
          await db.execute(
            'CREATE TABLE checklist (id INTEGER PRIMARY KEY, trip_id INTEGER, name TEXT, checked INTEGER DEFAULT 0)',
          );
          await db.insert('trips', {
            'id': 1,
            'name': '기존 여행',
            'country': 'JP',
            'budget': '0',
          });
          await db.insert('checklist', {
            'trip_id': 1,
            'name': '여권',
            'checked': 1,
          });
        },
      ),
    );
    await old.close();
    final upgraded = await Storage.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    expect((await upgraded.trips()).single['name'], '기존 여행');
    expect((await upgraded.checklist(1)).single['checked'], 1);
    expect((await upgraded.checklist(1)).single['category'], '직접 추가');
    await upgraded.setSetting('theme', 'dark');
    await upgraded.db.close();
    await databaseFactoryFfi.deleteDatabase(path);
  });
  test('여러 경비를 한 번에 저장하고 오류가 있으면 모두 취소한다', () async {
    final id = await trip();
    await store.saveExpenses(id, [
      expense('항공권', '500000', 'KRW', '1'),
      expense('숙박비', '30000', 'JPY', '9.5'),
    ]);
    expect((await store.expenses(id)).length, 2);
    expect(totalWon(await store.expenses(id)), BigInt.from(785000));
    await expectLater(
      store.saveExpenses(id, [
        expense('식비', '10000', 'KRW', '1'),
        expense('숙박비', '-1', 'JPY', '9.5'),
      ]),
      throwsFormatException,
    );
    expect((await store.expenses(id)).length, 2);
  });
}
