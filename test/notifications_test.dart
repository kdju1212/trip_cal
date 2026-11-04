import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trip_cal/services/notifications.dart';
import 'package:trip_cal/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('알림은 기본 OFF, 설정·준비물·삭제 상태를 네이티브로 전달', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(DdayNotifications.channel, (call) async {
      calls.add(call);
      if (call.method == 'requestPermission') return true;
      return null;
    });
    final store = await Storage.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    try {
      final id = await store.createTrip({
        'name': '일본',
        'country': 'JP',
        'budget': '0',
        'departure': '2099-01-01',
      });
      final n = DdayNotifications(store);
      await n.sync();
      expect(calls.last.arguments['enabled'], false);
      expect(await n.requestPermission(), true);
      await store.setSetting('notificationEnabled', true);
      await store.setSetting('notificationTrip', id);
      await n.sync();
      expect(calls.last.arguments['enabled'], true);
      expect(calls.last.arguments['selected'], id);
      await store.deleteTrip(id);
      await n.sync();
      expect(calls.last.arguments['enabled'], false);
      expect(calls.last.arguments['trips'], '[]');
    } finally {
      await store.db.close();
      messenger.setMockMethodCallHandler(DdayNotifications.channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
