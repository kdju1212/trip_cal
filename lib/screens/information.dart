import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../controller.dart';
import '../domain.dart';
import '../widgets/common.dart';

class TipsScreen extends StatefulWidget {
  const TipsScreen(this.country, {super.key});
  final Country country;
  @override State<TipsScreen> createState() => _TipsScreenState();
}
class _TipsScreenState extends State<TipsScreen> {
  late final Future<Map<String, dynamic>> data = load();
  Future<Map<String, dynamic>> load() async {
    final code = ['JP','US','TH','VN'].contains(widget.country.code) ? widget.country.code : 'common';
    return jsonDecode(await rootBundle.loadString('assets/tips/$code.json')) as Map<String, dynamic>;
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text('${widget.country.flag} 여행 꿀팁')), body: FutureBuilder<Map<String, dynamic>>(future: data, builder: (context, snapshot) {
    if (snapshot.hasError) return const Center(child: Text('여행 정보를 불러오지 못했어요.'));
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    final info = snapshot.data!;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(info['title'] as String, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 12),
      const Text('비자·입국 조건과 안전 정보는 바뀔 수 있어요. 출발 전에 공식 기관의 최신 공지를 확인하세요. 아래 내용은 준비를 돕는 참고 안내입니다.'),
      const SizedBox(height: 8), Text('공식 출처 확인: ${info['checkedAt']}', style: Theme.of(context).textTheme.bodySmall),
      for (final raw in info['sections'] as List) Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(raw['title'] as String, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), const SizedBox(height: 10), Text(raw['body'] as String), if (raw['url'] != null) TextButton.icon(onPressed: () => openExternal(context, raw['url'] as String), icon: const Icon(Icons.open_in_new, size: 16), label: const Text('공식 안내 확인'))]))),
    ]);
  }));
}

const purchaseItems = [
  ('esim', 'eSIM', '사용 기기의 eSIM 지원 여부와 데이터 사용량, 개통 시점을 확인하세요.'),
  ('sim', '유심', '휴대폰 잠금 여부와 유심 규격을 확인하세요. 기존 유심 보관도 준비하세요.'),
  ('roaming', '해외 로밍', '이용 중인 통신사에서 목적지 요금과 이용 기간을 확인하세요.'),
  ('insurance', '여행자보험', '보장 범위, 면책과 가입 가능 기간을 비교하세요.'),
  ('pass', '교통패스', '이동 경로와 개별 승차권 합계를 비교해 필요할 때만 구매하세요.'),
  ('adapter', '멀티어댑터', '사용 기기의 입력 전압과 숙소 콘센트를 확인하세요.'),
  ('gear', '여행용품', '짐의 무게와 항공사 수하물 규정을 먼저 확인하세요.'),
];
class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen(this.app, this.trip, {super.key});
  final AppController app;
  final DbRow trip;
  @override State<PurchaseScreen> createState() => _PurchaseScreenState();
}
class _PurchaseScreenState extends State<PurchaseScreen> {
  late Future<List<DbRow>> data = load();
  Future<List<DbRow>> load() => widget.app.store.db.query('purchases', where: 'trip_id = ?', whereArgs: [widget.trip['id']]);
  // Verified merchant homepages, no affiliate IDs or claims of partnership.
  late final links = <String, String>{
    'esim': 'https://www.airalo.com/',
    'roaming': 'https://roaming.kt.com/',
    'insurance': 'https://www.samsungfire.com/',
    if (widget.trip['country'] == 'JP') 'pass': 'https://japanrailpass.net/en/',
  };
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('필수 구매 안내')), body: FutureBuilder<List<DbRow>>(future: data, builder: (context, snapshot) {
    if (snapshot.hasError) return const Center(child: Text('구매 선택을 불러오지 못했어요.'));
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
    final domestic = widget.trip['country'] == 'KR';
    final needed = {for (final e in snapshot.data!) e['item']: e['needed'] == 1};
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('${countryByCode(widget.trip['country']! as String).flag} 필요한 것만 준비해요', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 12),
      const Text('체크는 구매가 필요한 항목을 표시합니다. eSIM·유심·로밍은 필요한 방식만 선택하세요. 앱 내 결제와 제휴 관계는 없습니다. 링크는 판매처의 공식 안내로 연결되며 특정 상품을 보장하지 않습니다.'), const SizedBox(height: 16),
      for (final (id, title, description) in purchaseItems.where((item) => !domestic || ['pass','gear'].contains(item.$1))) Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [CheckboxListTile(title: Text(title), subtitle: Text(description), value: needed[id] ?? false, onChanged: (v) async {
        await guarded(context, () async { await widget.app.store.db.insert('purchases', {'trip_id': widget.trip['id'], 'item': id, 'needed': v == true ? 1 : 0}, conflictAlgorithm: ConflictAlgorithm.replace); if (mounted) setState(() => data = load()); });
      }), Padding(padding: const EdgeInsets.only(left: 16, bottom: 8), child: links[id] == null ? const Text('구매 링크 준비 중', style: TextStyle(fontSize: 12)) : TextButton.icon(onPressed: () => openExternal(context, links[id]!), icon: const Icon(Icons.open_in_new), label: const Text('공식 사이트 확인')))])),
    ]);
  }));
}
