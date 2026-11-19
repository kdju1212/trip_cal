import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../domain.dart';
import '../widgets/common.dart';
import '../services/sim_ads.dart';
import '../storage.dart';

/// Search links show current third-party results; they are not offers in this app.
class SimShoppingScreen extends StatefulWidget {
  const SimShoppingScreen({super.key, required this.country, required this.isEsim, this.departure, this.endDate, this.adsService, this.storage});
  final Country? country;
  final bool isEsim;
  final SimAdsService? adsService;
  final Storage? storage;
  final String? departure;
  final String? endDate;

  @override
  State<SimShoppingScreen> createState() => _SimShoppingScreenState();
}

class _SimShoppingScreenState extends State<SimShoppingScreen> {
  late final SimAdsService ads = widget.adsService ?? SimAdsService();
  late Future<List<SimAd>> listings = loadAds();
  late final Future<String?> installationId = loadInstallationId();
  Future<String?> loadInstallationId() async {
    final storage = widget.storage;
    if (storage == null) { return null; }
    try {
      final existing = await storage.setting<String>('ad_installation_id', '');
      if (RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(existing)) { return existing; }
      final random = Random.secure();
      final bytes = List<int>.generate(16, (_) => random.nextInt(256));
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      final id = '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
      await storage.setSetting('ad_installation_id', id);
      return id;
    } catch (_) { return null; }
  }
  Future<void> recordClick(int adId) async {
    final id = await installationId;
    if (id == null) { await ads.recordEvents([adId], 'click'); return; }
    await ads.recordCheckedClick(adId, id);
  }
  Future<List<SimAd>> loadAds() async {
    final products = await ads.fetch(countryCode: widget.country?.code ?? '', isEsim: widget.isEsim, days: tripCalendarDays(widget.departure, widget.endDate));
    unawaited(ads.recordEvents(products.map((ad) => ad.id).whereType<int>().toList(), 'loaded'));
    return products;
  }

  @override
  void dispose() {
    if (widget.adsService == null) ads.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEsim = widget.isEsim;
    final country = widget.country;
    final departure = widget.departure;
    final endDate = widget.endDate;
    final type = isEsim ? 'eSIM' : '유심';
    final place = country == null || country.code == 'KR' ? '해외여행' : country.name;
    final days = tripCalendarDays(departure, endDate);
    final options = <(String, String, IconData)>[
      if (days != null) ('$days일', '여행 기간에 맞는 상품 찾아보기', Icons.event_available_outlined),
      if (days == null) for (final n in [3, 5, 7]) ('$n일', '$n일 이용 상품 찾아보기', Icons.date_range_outlined),
      if (days == null) ('데이터 무제한', '데이터 제공량과 속도 조건 확인', Icons.all_inclusive),
    ];
    return Scaffold(
      appBar: AppBar(title: Text('$type 사러가기')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('$place $type', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(days == null ? '여행 기간을 설정하면 필요한 일수를 알려드려요.' : '여행 기간 $departure ~ $endDate · 총 $days일',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (days != null) Text('시작일과 종료일을 모두 포함한 일수예요. 상품마다 개통 시점과 사용 일수 계산이 다르니 구매 전에 확인해 주세요.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (days != null) const SizedBox(height: 8),
          const Text('원하는 조건을 누르면 네이버 쇼핑에서 현재 판매 중인 상품과 가격을 확인할 수 있어요.'),
          const SizedBox(height: 6),
          Text(isEsim ? '구매 전 기기의 eSIM 지원 여부를 확인하세요.' : '구매 전 유심 수령 방법과 기기 호환 여부를 확인하세요.'),
          const SizedBox(height: 18),
          FutureBuilder<List<SimAd>>(
            future: listings,
            builder: (context, snapshot) {
              final products = snapshot.data ?? <SimAd>[];
              final cards = <Widget>[];
              if (snapshot.connectionState != ConnectionState.done && ads.configured && country != null && country.code != 'KR') {
                cards.add(const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())));
              }
              if (snapshot.hasError) {
                cards.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
                  const Expanded(child: Text('광고 상품을 불러오지 못했어요.')),
                  TextButton(onPressed: () => setState(() => listings = loadAds()), child: const Text('다시 시도')),
                ])));
              }
              Widget adCard(SimAd ad) => Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () { if (ad.id != null) { unawaited(recordClick(ad.id!)); } openExternal(context, ad.purchaseUrl); },
                  child: Padding(padding: const EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(borderRadius: BorderRadius.circular(12), child: ad.imageUrl == null
                      ? Container(width: 80, height: 80, color: Theme.of(context).colorScheme.primaryContainer, child: const Icon(Icons.sim_card_outlined))
                      : Image.network(ad.imageUrl!, width: 80, height: 80, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(width: 80, height: 80, color: Theme.of(context).colorScheme.primaryContainer, child: const Icon(Icons.sim_card_outlined)))),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(ad.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      Row(children: [
                        Expanded(child: Text('${ad.duration}일${ad.description.isEmpty ? '' : ' · ${ad.description}'}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Flexible(child: Text('광고 · ${ad.merchant}', style: Theme.of(context).textTheme.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                      if (ad.price != null) Text('가격 ${formatWon(BigInt.from(ad.price!))}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ])),
                  ])),
                ),
              );
              Widget organicCard((String, String, IconData) option) {
                final (term, description, icon) = option;
                return Card(clipBehavior: Clip.antiAlias, child: InkWell(
                  onTap: () { final uri = Uri.https('search.shopping.naver.com', '/search/all', {'query': '$place $type $term'}); openExternal(context, uri.toString()); },
                  child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                    Container(width: 80, height: 80, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 36, color: Theme.of(context).colorScheme.onPrimaryContainer)),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$place $type $term', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6), Text(description, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 8),
                      Text('상품과 가격 보기 ›', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                    ])),
                  ])),
                ));
              }
              // Two sponsored listings, then up to two search links, then the rest.
              cards.addAll(products.take(2).map(adCard));
              cards.addAll(options.take(2).map(organicCard));
              cards.addAll(products.skip(2).map(adCard));
              cards.addAll(options.skip(2).map(organicCard));
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cards);
            },
          ),
        ],
      ),
    );
  }
}
