import 'package:flutter/material.dart';
import 'storage.dart';
import 'services/rates.dart';
import 'services/notifications.dart';

class AppController extends ChangeNotifier {
  AppController(this.store) : rates = RateService(store), notifications = DdayNotifications(store);
  final Storage store;
  final RateService rates;
  final DdayNotifications notifications;
  ThemeMode themeMode = ThemeMode.system;
  String? serviceMessage;
  Future<void> load() async {
    final value = await store.setting('theme', 'system');
    themeMode = ThemeMode.values.firstWhere((e) => e.name == value, orElse: () => ThemeMode.system);
    await notifications.initialize();
    await _syncNotifications();
  }
  Future<void> setTheme(ThemeMode mode) async {
    await store.setSetting('theme', mode.name);
    themeMode = mode;
    notifyListeners();
  }
  Future<void> changed() async {
    notifyListeners();
    await _syncNotifications();
  }
  Future<void> _syncNotifications() async {
    try { await notifications.sync(); }
    catch (_) { serviceMessage = 'D-day 알림을 갱신하지 못했어요. 설정에서 다시 켜 주세요.'; }
  }
}
