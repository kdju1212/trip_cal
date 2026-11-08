import 'dart:convert';
import 'package:http/http.dart' as http;

class SimAd {
  const SimAd({required this.merchant, required this.title, required this.description, required this.duration, required this.purchaseUrl, this.price, this.imageUrl, this.id});
  final String merchant, title, description, purchaseUrl;
  final int duration;
  final int? price;
  final int? id;
  final String? imageUrl;

  static bool _secureUrl(String? value) {
    final uri = value == null ? null : Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty;
  }

  static SimAd? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) { return null; }
    final merchant = raw['merchant_name'];
    final title = raw['title'];
    final description = raw['description'];
    final duration = raw['duration_days'];
    final purchaseUrl = raw['purchase_url'];
    final price = raw['price_krw'];
    final image = raw['image_url'];
    if (merchant is! String || merchant.trim().isEmpty || title is! String || title.trim().isEmpty || description is! String || duration is! int || duration < 1 || purchaseUrl is! String || !_secureUrl(purchaseUrl) || (price != null && (price is! int || price < 0))) { return null; }
    return SimAd(merchant: merchant, title: title, description: description, duration: duration, purchaseUrl: purchaseUrl, price: price as int?, imageUrl: image is String && _secureUrl(image) ? image : null, id: raw['id'] is int ? raw['id'] as int : null);
  }
}

class SimAdsService {
  SimAdsService({http.Client? client, String? url, String? anonKey})
      : client = client ?? http.Client(),
        url = url ?? const String.fromEnvironment('SUPABASE_URL'),
        anonKey = anonKey ?? const String.fromEnvironment('SUPABASE_ANON_KEY');
  final http.Client client;
  final String url, anonKey;
  bool get configured => SimAd._secureUrl(url) && anonKey.isNotEmpty;

  Future<List<SimAd>> fetch({required String countryCode, required bool isEsim, int? days}) async {
    if (!configured || !RegExp(r'^[A-Z]{2}$').hasMatch(countryCode) || countryCode == 'KR') { return []; }
    final root = Uri.parse(url);
    final uri = root.replace(path: '${root.path.replaceFirst(RegExp(r'/$'), '')}/rest/v1/rpc/list_ranked_sim_ads');
    final response = await client.post(uri, headers: {
      'apikey': anonKey,
      if (!anonKey.startsWith('sb_publishable_')) 'Authorization': 'Bearer $anonKey',
      'Content-Type': 'application/json',
    }, body: jsonEncode({'p_country': countryCode, 'p_type': isEsim ? 'esim' : 'sim', 'p_days': days})).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) { throw const FormatException('광고 상품을 불러오지 못했어요.'); }
    final json = jsonDecode(response.body);
    if (json is! List) { throw const FormatException('광고 상품 응답을 확인해 주세요.'); }
    return json.map(SimAd.fromJson).whereType<SimAd>().toList();
  }
  /// Best-effort anonymous activity measurement; this is not verified billing data.
  Future<void> recordEvents(List<int> ids, String event) async {
    if (!configured || ids.isEmpty || !['loaded', 'click'].contains(event)) { return; }
    final root = Uri.parse(url);
    final uri = root.replace(path: '${root.path.replaceFirst(RegExp(r'/$'), '')}/rest/v1/rpc/record_ad_events');
    try {
      await client.post(uri, headers: {
        'apikey': anonKey,
        if (!anonKey.startsWith('sb_publishable_')) 'Authorization': 'Bearer $anonKey',
        'Content-Type': 'application/json',
      }, body: jsonEncode({'p_ids': ids.take(50).toList(), 'p_event': event})).timeout(const Duration(seconds: 5));
    } catch (_) { /* Statistics must not interrupt shopping. */ }
  }
  Future<void> recordCheckedClick(int adId, String installationId) async {
    if (!configured) { return; }
    final root = Uri.parse(url);
    final uri = root.replace(path: '${root.path.replaceFirst(RegExp(r'/$'), '')}/rest/v1/rpc/record_checked_click');
    try {
      await client.post(uri, headers: {
        'apikey': anonKey,
        if (!anonKey.startsWith('sb_publishable_')) 'Authorization': 'Bearer $anonKey',
        'Content-Type': 'application/json',
      }, body: jsonEncode({'p_ad_id': adId, 'p_installation_id': installationId})).timeout(const Duration(seconds: 5));
    } catch (_) { /* Click logging must not interrupt shopping. */ }
  }
  void close() => client.close();
}
