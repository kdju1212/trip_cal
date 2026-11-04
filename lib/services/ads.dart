import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdsService {
  static final allowed = ValueNotifier<bool>(false);
  static Future<void>? _initializing;
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static bool get production => const bool.fromEnvironment('PRODUCTION_ADS');
  static String get bannerId => production
      ? const String.fromEnvironment('ADMOB_BANNER_ID')
      : defaultTargetPlatform == TargetPlatform.iOS
      ? 'ca-app-pub-3940256099942544/2934735716'
      : 'ca-app-pub-3940256099942544/6300978111';
  static Future<void> initialize() => _initializing ??= _initialize();
  static Future<void> _initialize() async {
    if (!supported || bannerId.isEmpty) { return; }
    try {
      final ready = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((error) {});
            if (!ready.isCompleted) { ready.complete(); }
          } catch (_) {
            if (!ready.isCompleted) { ready.complete(); }
          }
        },
        (error) {
          if (!ready.isCompleted) { ready.complete(); }
        },
      );
      await ready.future.timeout(const Duration(seconds: 20));
      if (await ConsentInformation.instance.canRequestAds()) {
        await MobileAds.instance.initialize();
        allowed.value = true;
      }
    } catch (_) {
      allowed.value = false;
    }
  }

  static Future<bool> privacyOptions() async {
    if (!supported) { return false; }
    // Stop and dispose existing banners while consent is being changed.
    allowed.value = false;
    try {
      final status = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      if (status != PrivacyOptionsRequirementStatus.required) {
        allowed.value = await ConsentInformation.instance.canRequestAds();
        return false;
      }
      await ConsentForm.showPrivacyOptionsForm((error) {});
      allowed.value = await ConsentInformation.instance.canRequestAds();
      return true;
    } catch (_) {
      return false;
    }
  }
}
