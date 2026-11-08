import 'package:flutter/material.dart';
import '../controller.dart';
import '../domain.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen(this.app, {super.key});
  final AppController app;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool enabled = false, remaining = true, busy = false, loaded = false;
  int selected = 0;
  List<DbRow> trips = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final s = widget.app.store;
      final e = await s.setting('notificationEnabled', false);
      final r = await s.setting('notificationRemaining', true);
      final t = await s.setting('notificationTrip', 0);
      final list = (await s.trips())
          .where((v) => notificationEligible(v, DateTime.now()))
          .toList();
      if (mounted) {
        setState(() {
          enabled = e;
          remaining = r;
          selected = list.any((e) => e['id'] == t) ? t : 0;
          trips = list;
          loaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        message(context, '설정을 불러오지 못했어요.');
      }
    }
  }

  Future<void> saveNotification(bool value) async {
    if (value && trips.isEmpty) {
      message(context, '오늘 이후의 출발일이 있는 여행을 먼저 추가해 주세요.');
      return;
    }
    setState(() => busy = true);
    await guarded(context, () async {
      if (value && !await widget.app.notifications.requestPermission()) {
        if (mounted) {
          message(context, '알림 권한이 필요해요. 기기 설정에서 허용해 주세요.');
        }
        return;
      }
      await widget.app.store.setSetting('notificationEnabled', value);
      await widget.app.store.setSetting('notificationTrip', selected);
      await widget.app.store.setSetting('notificationRemaining', remaining);
      await widget.app.notifications.sync();
      if (mounted) {
        setState(() => enabled = value);
      }
    });
    if (mounted) {
      setState(() => busy = false);
    }
  }

  Future<void> notificationOptions() async {
    await guarded(context, () async {
      await widget.app.store.setSetting('notificationTrip', selected);
      await widget.app.store.setSetting('notificationRemaining', remaining);
      await widget.app.notifications.sync();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('설정')),
    body: !loaded
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SectionTitle('화면'),
              DropdownButtonFormField<ThemeMode>(
                initialValue: widget.app.themeMode,
                decoration: const InputDecoration(labelText: '화면 모드'),
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('기기 설정 따르기'),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text('라이트 모드'),
                  ),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('다크 모드')),
                ],
                onChanged: (mode) {
                  if (mode != null) {
                    guarded(context, () => widget.app.setTheme(mode));
                  }
                },
              ),
              const SectionTitle('출발일 D-day 알림'),
              Card(
                child: SwitchListTile(
                  title: const Text('D-day 고정 알림'),
                  subtitle: Text(
                    widget.app.notifications.supported
                        ? '알림창에서 여행 준비를 확인해요.'
                        : 'Android에서 사용할 수 있어요.',
                  ),
                  value: enabled,
                  onChanged: busy || !widget.app.notifications.supported
                      ? null
                      : saveNotification,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey('selected-$selected'),
                initialValue: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '표시할 여행'),
                items: [
                  const DropdownMenuItem(
                    value: 0,
                    child: Text('가장 가까운 여행 자동 선택'),
                  ),
                  ...trips.map(
                    (t) => DropdownMenuItem(
                      value: t['id']! as int,
                      child: Text(
                        t['name']! as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (value) {
                        setState(() => selected = value!);
                        notificationOptions();
                      },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('남은 체크리스트 항목 수 표시'),
                value: remaining,
                onChanged: busy
                    ? null
                    : (v) {
                        setState(() => remaining = v);
                        notificationOptions();
                      },
              ),
              const Text(
                '기본값은 OFF입니다. 날짜가 지나면 알림을 종료합니다. Android 버전과 절전 설정에 따라 갱신이 지연되거나 알림을 지울 수 있습니다.',
              ),
              if (widget.app.serviceMessage != null)
                Text(widget.app.serviceMessage!),
              const SectionTitle('개인정보와 앱 정보'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('개인정보처리방침'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const PrivacyScreen(),
                        ),
                      ),
                    ),
                    ListTile(
                      title: const Text('앱 정보'),
                      subtitle: const Text('여행 준비 도우미 1.0.0 · 예상 경비 계획'),
                      onTap: () => showAboutDialog(
                        context: context,
                        applicationName: '여행 준비 도우미',
                        applicationVersion: '1.0.0',
                        children: [
                          const Text(
                            '로그인 없이 여행 예산과 체크리스트를 관리합니다. 데이터는 이 기기의 SQLite DB에 저장됩니다.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
  );
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('개인정보처리방침')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('개발용 개인정보 안내', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        const Text(
          '여행·예산·경비·체크리스트는 기기 내부 DB에 저장하며 개발자의 서버로 전송하지 않습니다. 회원가입과 로그인이 없습니다. 앱을 삭제하면 로컬 데이터가 삭제되며 자동 클라우드 백업은 사용하지 않습니다.\n\n환율을 조회하면 통화 코드와 네트워크 요청 정보(IP 주소 등)가 Frankfurter에 전달됩니다. 여행 이름과 경비 내역은 전송하지 않습니다.\n\n업체 광고를 표시할 때 여행 국가, 통신 방식과 여행 일수가 광고 목록 서버에 전달됩니다. 광고 목록을 불러오거나 광고를 누르면 광고 식별자, 활동 유형과 시각이 서버에 기록됩니다. 상품 이미지를 불러오면 해당 이미지 서버에 네트워크 정보(IP 주소 등)가 전달될 수 있습니다. 외부 링크는 기기의 브라우저에서 열리며 해당 사이트의 개인정보처리방침이 적용됩니다.\n\n정식 출시 전 운영자명, 연락처, 처리 목적·보유기간·이용자 권리와 공개 정책 URL을 확정하고 Google Play 신고 내용과 일치시켜야 합니다.',
        ),
        TextButton(
          onPressed: () => openExternal(context, 'https://frankfurter.dev/'),
          child: const Text('Frankfurter 공식 안내'),
        ),
      ],
    ),
  );
}
