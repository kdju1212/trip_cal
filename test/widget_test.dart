import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trip_cal/controller.dart';
import 'package:trip_cal/domain.dart';
import 'package:trip_cal/screens/trip_form.dart';
import 'package:trip_cal/screens/expense_batch_form.dart';
import 'package:trip_cal/screens/trip_detail.dart';
import 'package:trip_cal/screens/checklist.dart';
import 'package:trip_cal/storage.dart';
import 'package:trip_cal/services/rates.dart';
import 'package:trip_cal/widgets/budget_chart.dart';

void main() {
  late Storage store;
  late AppController app;
  sqfliteFfiInit();
  setUp(() async {
    store = await Storage.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
    app = AppController(store);
  });
  tearDown(() async {
    app.dispose();
    app.rates.client.close();
    await store.db.close();
  });
  Widget wrap(Widget child, {bool dark = false, double scale = 1}) =>
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: child,
      );
  testWidgets('해외 준비물에서 통신 항목을 맨 위에 표시한다', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final id = (await tester.runAsync(() => store.createTrip({'name': '일본', 'country': 'JP', 'budget': '100000', 'departure': '2027-01-03', 'end_date': '2027-01-06'})))!;
    await tester.pumpWidget(wrap(ChecklistScreen(app, id, country: countryByCode('JP'), departure: '2027-01-03', endDate: '2027-01-06')));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 100)); });
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('eSIM · 유심 · 로밍 중 필요한 방식 확인')).dy,
        lessThan(tester.getTopLeft(find.text('신분증')).dy));
    expect(find.text('유심 사러가기'), findsOneWidget);
    expect(find.text('eSIM 사러가기'), findsOneWidget);
    await tester.tap(find.text('eSIM 사러가기'));
    await tester.pumpAndSettle();
    expect(find.text('eSIM 사러가기'), findsOneWidget);
    expect(find.text('여행 기간 2027-01-03 ~ 2027-01-06 · 총 4일'), findsOneWidget);
    expect(find.text('일본 eSIM 4일'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('새 여행은 출발일 입력 없이 저장할 수 있다', (tester) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => TripForm(app)),
              ),
              child: const Text('시작'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '서울 휴식');
    await tester.enterText(find.byType(TextFormField).at(1), '200000');
    await tester.ensureVisible(find.text('여행 저장'));
    await tester.tap(find.text('여행 저장'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final trips = await tester.runAsync(store.trips);
    expect(trips, hasLength(1));
    expect(trips!.single['departure'], isNull);
    expect(trips.single['budget'], '200000');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('여행 기간 선택은 하나의 기간 달력을 연다', (tester) async {
    await tester.pumpWidget(wrap(TripForm(app)));
    await tester.ensureVisible(find.text('여행 기간 선택'));
    await tester.tap(find.text('여행 기간 선택'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    expect(find.text('시작일과 종료일 선택'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('국가 검색에서 유로 국가와 일본을 찾는다', (tester) async {
    await tester.pumpWidget(wrap(const Scaffold(body: CountryPicker())));
    await tester.enterText(find.byType(TextField), 'JPY');
    await tester.pumpAndSettle();
    expect(find.text('일본'), findsOneWidget);
    expect(find.text('대한민국'), findsNothing);
    await tester.enterText(find.byType(TextField), 'EUR');
    await tester.pumpAndSettle();
    expect(find.text('프랑스'), findsOneWidget);
    expect(find.text('독일'), findsOneWidget);
  });
  testWidgets('작은 화면과 큰 글씨, 다크모드에서 생성 화면 오류 없음', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(TripForm(app), dark: true, scale: 1.6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('0원과 예산 초과 차트는 음수 섹션 없이 표시된다', (tester) async {
    final expenses = <DbRow>[
      {'category': '숙박비', 'won': '300000'},
    ];
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: ListView(children: [BudgetChart(expenses, BigInt.zero)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('300,000원'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: ListView(
            children: [BudgetChart(expenses, BigInt.from(100000))],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('남은 예산'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('작은 화면의 여행 상세는 광고 없이도 표시된다', (tester) async {
    final id = (await tester.runAsync(
      () => store.createTrip({
        'name': '일본 여행',
        'country': 'JP',
        'budget': '2000000',
      }),
    ))!;
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(TripDetail(app, id), dark: true, scale: 1.4));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('일본 여행'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('이름 입력 없이 같은 항목을 여러 줄에 추가해 한 번에 저장한다', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final id = (await tester.runAsync(
      () => store.createTrip({
        'name': '테스트',
        'country': 'KR',
        'budget': '1000000',
      }),
    ))!;
    final trip = (await tester.runAsync(store.trips))!.single;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ExpenseBatchForm(app, trip),
                ),
              ),
              child: const Text('시작'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('시작'));
    await tester.pumpAndSettle();
    expect(find.text('경비 이름'), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, '500000');
    await tester.ensureVisible(find.text('항목 추가'));
    await tester.tap(find.text('항목 추가'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextFormField).last);
    await tester.enterText(find.byType(TextFormField).last, '200000');
    await tester.ensureVisible(find.text('2개 경비 저장'));
    await tester.tap(find.text('2개 경비 저장'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final rows = (await tester.runAsync(() => store.expenses(id)))!;
    expect(rows, hasLength(2));
    expect(rows.map((e) => e['category']), everyElement('항공권'));
    expect(totalWon(rows), BigInt.from(700000));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('작은 화면에서도 경비 항목과 금액을 한 줄에 나란히 표시한다', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final id = (await tester.runAsync(
      () => store.createTrip({
        'name': '국내 여행',
        'country': 'KR',
        'budget': '1000000',
      }),
    ))!;
    final trip = (await tester.runAsync(
      store.trips,
    ))!.firstWhere((r) => r['id'] == id);
    await tester.pumpWidget(wrap(ExpenseBatchForm(app, trip), scale: 1.3));
    await tester.pumpAndSettle();
    final category = tester.getRect(
      find.byType(DropdownButtonFormField<String>).first,
    );
    final amount = tester.getRect(find.byType(TextFormField).first);
    expect(amount.left, greaterThan(category.left));
    expect(amount.top, category.top);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('각 줄의 통화를 선택하고 취소하면 입력 금액이 유지된다', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    app.dispose();
    app.rates.client.close();
    final client = MockClient(
      (_) async => http.Response(
        '{"base":"JPY","quote":"KRW","rate":9.5,"date":"2026-11-04"}',
        200,
      ),
    );
    app = AppController(store, rates: RateService(store, client: client));
    final trip = {'id': 1, 'country': 'JP', 'budget': '1000000'};
    await tester.pumpWidget(wrap(ExpenseBatchForm(app, trip)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('KRW ₩'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JPY ¥').last);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '30000');
    await tester.pump();
    expect(find.text('원화 환산 285,000원'), findsOneWidget);
    await tester.tap(find.text('항목 추가'));
    await tester.pumpAndSettle();
    expect(find.text('KRW ₩'), findsOneWidget);
    await tester.tap(find.text('JPY ¥').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('KRW ₩').last);
    await tester.pumpAndSettle();
    expect(find.text('통화를 바꿀까요?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('30,000'), findsOneWidget);
    expect(find.text('원화 환산 285,000원'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('저장한 경비를 위에 유지하고 남은 예산을 실시간으로 표시한다', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final id = (await tester.runAsync(() => store.createTrip({'name': '일본', 'country': 'JP', 'budget': '2000000'})))!;
    await tester.runAsync(() async {
      await store.saveExpense(id, {'name':'왕복 항공권','category':'항공권','amount':'500000','currency':'KRW','rate':'1','rate_source':'KRW'});
      await store.saveExpense(id, {'name':'호텔','category':'숙박비','amount':'30000','currency':'JPY','rate':'9.5','rate_date':'2026-11-04','rate_source':'직접 입력'});
    });
    final trip = (await tester.runAsync(store.trips))!.single;
    await tester.pumpWidget(wrap(Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ExpenseBatchForm(app, trip))), child: const Text('시작'))))));
    await tester.tap(find.text('시작'));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 100)); });
    await tester.pumpAndSettle();
    expect(find.text('500,000'), findsOneWidget);
    expect(find.text('30,000'), findsOneWidget);
    expect(find.text('1,215,000원'), findsOneWidget);
    expect(tester.getRect(find.text('남은 예산')).top, lessThan(tester.getRect(find.text('2개 경비 저장')).top));
    await tester.tap(find.text('항목 추가'));
    await tester.pumpAndSettle();
    expect(find.text('금액이나 환율을 입력하지 않은 항목은 제외했어요.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, '100000');
    await tester.pump();
    expect(find.text('1,115,000원'), findsOneWidget);
    await tester.ensureVisible(find.text('3개 경비 저장'));
    await tester.tap(find.text('3개 경비 저장'));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 100)); });
    await tester.pumpAndSettle();
    final saved = (await tester.runAsync(() => store.expenses(id)))!;
    expect(saved, hasLength(3));
    expect(totalWon(saved), BigInt.from(885000));
    expect(saved.where((r) => r['currency'] == 'JPY').single['rate'], '9.5');
    expect(saved.where((r) => r['name'] == '왕복 항공권'), hasLength(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(wrap(ExpenseBatchForm(app, trip)));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 100)); });
    await tester.pumpAndSettle();
    expect(find.text('500,000'), findsOneWidget);
    expect(find.text('30,000'), findsOneWidget);
    expect(find.text('100,000'), findsOneWidget);
    expect(find.text('1,115,000원'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('저장된 외화 경비는 기존 원화 환산액 그대로 남은 예산에 반영한다', (tester) async {
    final id = (await tester.runAsync(() => store.createTrip({'name': '일본', 'country': 'JP', 'budget': '1000000'})))!;
    await tester.runAsync(() async {
      await store.saveExpense(id, {'name':'호텔','category':'숙박비','amount':'30000','currency':'JPY','rate':'9.5','rate_date':'2026-11-04','rate_source':'직접 입력'});
      await store.db.update('expenses', {'won':'287000'}, where:'trip_id = ?', whereArgs:[id]);
    });
    final trip = (await tester.runAsync(store.trips))!.single;
    await tester.pumpWidget(wrap(ExpenseBatchForm(app, trip)));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 100)); });
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('남은 예산'));
    expect(find.text('713,000원'), findsOneWidget);
    expect(find.text('원화 환산 287,000원'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

}
