import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trip_cal/services/sim_ads.dart';
import 'package:trip_cal/domain.dart';
import 'package:trip_cal/screens/sim_shopping.dart';

void main() {
  testWidgets('여행 기간에 맞는 업체 상품을 광고로 표시한다', (tester) async {
    final client = MockClient((request) async => http.Response('[{"merchant_name":"판매점","title":"일본 데이터","description":"하루 1GB","duration_days":3,"price_krw":5000,"purchase_url":"https://example.com/item","image_url":null}]', 200, headers: {'content-type': 'application/json; charset=utf-8'}));
    final service = SimAdsService(client: client, url: 'https://example.supabase.co', anonKey: 'public-key');
    await tester.pumpWidget(MaterialApp(home: SimShoppingScreen(country: countryByCode('JP'), isEsim: true, departure: '2027-01-01', endDate: '2027-01-03', adsService: service)));
    await tester.pumpAndSettle();
    expect(find.text('광고 · 판매점'), findsOneWidget);
    expect(find.text('일본 데이터'), findsOneWidget);
    expect(find.text('가격 5,000원'), findsOneWidget);
    expect(find.text('가격과 조건은 판매처에서 확인 ›'), findsNothing);
    expect(tester.getTopLeft(find.text('광고 · 판매점')).dx, greaterThan(tester.getTopLeft(find.text('3일 · 하루 1GB')).dx));
    expect(find.text('일본 eSIM 3일'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    service.close();
  });
  testWidgets('광고 두 개 다음에 검색 항목을 배치한다', (tester) async {
    final client = MockClient((request) async => http.Response(jsonEncode([
      for (var i = 1; i <= 3; i++) {'merchant_name':'판매점', 'title':'광고 상품 $i', 'description':'하루 1GB', 'duration_days':3, 'purchase_url':'https://example.com/item'}
    ]), 200, headers: {'content-type':'application/json; charset=utf-8'}));
    final service = SimAdsService(client: client, url: 'https://example.supabase.co', anonKey: 'public-key');
    await tester.pumpWidget(MaterialApp(home: SimShoppingScreen(country: countryByCode('JP'), isEsim: true, departure: '2027-01-01', endDate: '2027-01-03', adsService: service)));
    await tester.pumpAndSettle();
    final second = tester.getTopLeft(find.text('광고 상품 2')).dy;
    final search = tester.getTopLeft(find.text('일본 eSIM 3일')).dy;
    final third = tester.getTopLeft(find.text('광고 상품 3')).dy;
    expect(second, lessThan(search));
    expect(search, lessThan(third));
    await tester.pumpWidget(const SizedBox());
    service.close();
  });
  test('여행지와 종류, 일수에 맞는 광고 상품을 요청한다', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/rest/v1/rpc/list_ranked_sim_ads');
      expect(request.method, 'POST');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['p_country'], 'JP');
      expect(body['p_type'], 'esim');
      expect(body['p_days'], 3);
      expect(request.headers['apikey'], 'public-key');
      return http.Response('[{"merchant_name":"판매점","title":"일본 데이터","description":"하루 1GB","duration_days":3,"price_krw":5000,"purchase_url":"https://example.com/item","image_url":null}]', 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final service = SimAdsService(client: client, url: 'https://example.supabase.co', anonKey: 'public-key');
    final ads = await service.fetch(countryCode: 'JP', isEsim: true, days: 3);
    expect(ads.single.merchant, '판매점');
    expect(ads.single.price, 5000);
    service.close();
  });
  test('클릭은 서버에서 중복 검증하도록 전송한다', () async {
    var called = false;
    final client = MockClient((request) async {
      called = true;
      expect(request.url.path, '/rest/v1/rpc/record_checked_click');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['p_ad_id'], 42);
      expect(body['p_installation_id'], 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
      return http.Response('', 204);
    });
    final service = SimAdsService(client: client, url: 'https://example.supabase.co', anonKey: 'public-key');
    await service.recordCheckedClick(42, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    expect(called, isTrue);
    service.close();
  });
  test('잘못된 링크는 거부하고 연결 정보가 없으면 요청하지 않는다', () async {
    final client = MockClient((request) async => http.Response('[{"merchant_name":"판매점","title":"유심","description":"","duration_days":3,"purchase_url":"http://unsafe.example"}]', 200, headers: {'content-type': 'application/json; charset=utf-8'}));
    final service = SimAdsService(client: client, url: 'https://example.supabase.co', anonKey: 'public-key');
    expect(await service.fetch(countryCode: 'JP', isEsim: false), isEmpty);
    service.close();
    final unconfigured = SimAdsService(url: '', anonKey: '');
    expect(await unconfigured.fetch(countryCode: 'JP', isEsim: false), isEmpty);
    unconfigured.close();
  });
  test('연결 실패는 빈 상품 목록과 구분한다', () async {
    final client = MockClient((request) async => http.Response('failed', 503));
    final service = SimAdsService(client: client, url: 'https://example.supabase.co', anonKey: 'public-key');
    await expectLater(service.fetch(countryCode: 'JP', isEsim: false), throwsFormatException);
    service.close();
  });
}
