import 'package:flutter/material.dart';
import '../domain.dart';
import '../widgets/common.dart';
import '../services/sim_ads.dart';

/// Search links show current third-party results; they are not offers in this app.
class SimShoppingScreen extends StatefulWidget {
  const SimShoppingScreen({super.key, required this.country, required this.isEsim, this.departure, this.endDate, this.adsService});
  final Country? country;
  final bool isEsim;
  final SimAdsService? adsService;
  final String? departure;
  final String? endDate;

  @override
  State<SimShoppingScreen> createState() => _SimShoppingScreenState();
}

class _SimShoppingScreenState extends State<SimShoppingScreen> {
  late final SimAdsService ads = widget.adsService ?? SimAdsService();
  late Future<List<SimAd>> listings = loadAds();
  Future<List<SimAd>> loadAds() => ads.fetch(countryCode: widget.country?.code ?? '', isEsim: widget.isEsim, days: tripCalendarDays(widget.departure, widget.endDate));

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
          if (ads.configured && country != null && country.code != 'KR')
            FutureBuilder<List<SimAd>>(
              future: listings,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                }
                if (snapshot.hasError) {
                  return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
                    const Expanded(child: Text('광고 상품을 불러오지 못했어요.')),
                    TextButton(onPressed: () => setState(() => listings = loadAds()), child: const Text('다시 시도')),
                  ]));
                }
                final products = snapshot.data ?? [];
                if (products.isEmpty) return const SizedBox.shrink();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('업체 광고', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  for (final ad in products) Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => openExternal(context, ad.purchaseUrl),
                      child: Padding(padding: const EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ClipRRect(borderRadius: BorderRadius.circular(12), child: ad.imageUrl == null
                          ? Container(width: 80, height: 80, color: Theme.of(context).colorScheme.primaryContainer, child: const Icon(Icons.sim_card_outlined))
                          : Image.network(ad.imageUrl!, width: 80, height: 80, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(width: 80, height: 80, color: Theme.of(context).colorScheme.primaryContainer, child: const Icon(Icons.sim_card_outlined)))),
                        const SizedBox(width: 16),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('광고 · ${ad.merchant}', style: Theme.of(context).textTheme.labelMedium),
                          const SizedBox(height: 4),
                          Text(ad.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          Text('${ad.duration}일${ad.description.isEmpty ? '' : ' · ${ad.description}'}'),
                          if (ad.price != null) Text('등록 가격 ${formatWon(BigInt.from(ad.price!))}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('가격과 조건은 판매처에서 확인 ›', style: Theme.of(context).textTheme.bodySmall),
                        ])),
                      ])),
                    ),
                  ),
                  const SizedBox(height: 16),
                ]);
              },
            ),
          for (final (term, description, icon) in options)
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  final uri = Uri.https('search.shopping.naver.com', '/search/all', {'query': '$place $type $term'});
                  openExternal(context, uri.toString());
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, size: 36, color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$place $type $term', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(description, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Text('상품과 가격 보기 ›', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                    ])),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
