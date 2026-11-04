import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trip_cal/controller.dart';
import 'package:trip_cal/domain.dart';
import 'package:trip_cal/screens/trip_form.dart';
import 'package:trip_cal/screens/trip_detail.dart';
import 'package:trip_cal/storage.dart';
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
}
