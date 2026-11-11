import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../domain.dart';
import '../storage.dart';

class DdayNotifications {
  DdayNotifications(this.storage);
  final Storage storage;
  static const channel = MethodChannel('com.tripcal.app/dday');
  ValueChanged<int>? onOpen;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<void> initialize() async {
    if (!supported) {
      return;
    }
    channel.setMethodCallHandler((call) async {
      if (call.method == 'openTrip' && call.arguments is int) {
        onOpen?.call(call.arguments as int);
      }
    });
  }

  Future<int?> initialTrip() async =>
      supported ? await channel.invokeMethod<int>('initialTrip') : null;
  Future<bool> requestPermission() async =>
      supported &&
      (await channel.invokeMethod<bool>('requestPermission') ?? false);
  Future<void> _pending = Future<void>.value();
  Future<void> sync() {
    final next = _pending.catchError((Object _) {}).then((_) => _sync());
    _pending = next;
    return next;
  }

  Future<void> _sync() async {
    if (!supported) {
      return;
    }
    final enabled = await storage.setting('notificationEnabled', false);
    final trips = await storage.trips();
    final snapshots = <Map<String, Object?>>[];
    for (final trip in trips) {
      final items = await storage.checklist(trip['id']! as int);
      final c = countryByCode(trip['country']! as String);
      snapshots.add({
        'id': trip['id'],
        'name': trip['name'],
        'flag': c.flag,
        'departure': trip['departure'],
        'remaining': items.where((e) => e['checked'] != 1).length,
      });
    }
    await channel.invokeMethod<void>('configure', {
      'enabled': enabled,
      'selected': await storage.setting('notificationTrip', 0),
      'showRemaining': await storage.setting('notificationRemaining', true),
      'showName': await storage.setting('notificationShowName', true),
      'showDday': await storage.setting('notificationShowDday', true),
      'customText': await storage.setting('notificationCustomText', ''),
      'emoji': await storage.setting('notificationEmoji', '✈️'),
      'trips': jsonEncode(snapshots),
    });
  }
}
