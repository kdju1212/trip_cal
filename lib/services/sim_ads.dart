import 'dart:convert';
import 'package:http/http.dart' as http;

class SimAd {
  const SimAd({required this.merchant, required this.title, required this.description, required this.duration, required this.purchaseUrl, this.price, this.imageUrl});
  final String merchant, title, description, purchaseUrl;
  final int duration;
  final int? price;
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
    return SimAd(merchant: merchant, title: title, description: description, duration: duration, purchaseUrl: purchaseUrl, price: price as int?, imageUrl: image is String && _secureUrl(image) ? image : null);
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
    final uri = root.replace(path: '${root.path.replaceFirst(RegExp(r'/$'), '')}/rest/v1/sim_ads', queryParameters: {
      'select': 'id,merchant_name,title,description,sim_type,country_code,duration_days,price_krw,image_url,purchase_url,priority,updated_at',
      'country_code': 'eq.$countryCode',
      'sim_type': 'eq.${isEsim ? 'esim' : 'sim'}',
      if (days != null) 'duration_days': 'eq.$days',
      'order': 'priority.desc,id.desc',
      'limit': '50',
    });
    final response = await client.get(uri, headers: {
      'apikey': anonKey,
      if (!anonKey.startsWith('sb_publishable_')) 'Authorization': 'Bearer $anonKey',
    }).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) { throw const FormatException('광고 상품을 불러오지 못했어요.'); }
    final json = jsonDecode(response.body);
    if (json is! List) { throw const FormatException('광고 상품 응답을 확인해 주세요.'); }
    return json.map(SimAd.fromJson).whereType<SimAd>().toList();
  }
  void close() => client.close();
}
