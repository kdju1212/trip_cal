import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ads.dart';

class AdBanner extends StatefulWidget {
  const AdBanner({super.key});
  @override State<AdBanner> createState() => _AdBannerState();
}
class _AdBannerState extends State<AdBanner> {
  BannerAd? ad;
  bool loaded = false;
  @override void initState() { super.initState(); AdsService.allowed.addListener(update); WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) update(); }); }
  void update() {
    if (!mounted) return;
    if (!AdsService.allowed.value) { ad?.dispose(); ad = null; setState(() => loaded = false); return; }
    if (ad != null) return;
    final banner = BannerAd(size: AdSize.banner, adUnitId: AdsService.bannerId, request: const AdRequest(), listener: BannerAdListener(onAdLoaded: (value) { if (mounted && identical(value, ad)) setState(() => loaded = true); else { value.dispose(); } }, onAdFailedToLoad: (value, error) { value.dispose(); if (mounted && identical(value, ad)) { ad = null; setState(() => loaded = false); } }));
    ad = banner;
    banner.load();
  }
  @override void dispose() { AdsService.allowed.removeListener(update); ad?.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => !loaded || ad == null || MediaQuery.sizeOf(context).width < 320 ? const SizedBox.shrink() : SafeArea(top: false, child: SizedBox(height: 58, child: Center(child: SizedBox(width: 320, height: 50, child: AdWidget(ad: ad!)))));
}
