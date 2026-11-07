import 'package:flutter/material.dart';
import '../controller.dart';
import '../domain.dart';
import '../widgets/common.dart';
import 'trip_form.dart';
import 'trip_detail.dart';
import 'settings.dart';

class Home extends StatefulWidget {
  const Home(this.app, {super.key});
  final AppController app;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late Future<(List<DbRow>, int, bool)> data;
  @override
  void initState() {
    super.initState();
    reload();
    widget.app.addListener(reload);
  }

  void reload() {
    data = load();
    if (mounted) {
      setState(() {});
    }
  }

  Future<(List<DbRow>, int, bool)> load() async {
    final trips = await widget.app.store.trips();
    final selected = await widget.app.store.setting('notificationTrip', 0);
    final showRemaining = await widget.app.store.setting('notificationRemaining', true);
    final result = <DbRow>[];
    for (final trip in trips) {
      final expenses = await widget.app.store.expenses(trip['id']! as int);
      final items = showRemaining ? await widget.app.store.checklist(trip['id']! as int) : <DbRow>[];
      result.add({
        ...trip,
        'remaining':
            BigInt.parse(trip['budget']! as String) - totalWon(expenses),
        'checklistRemaining': items.where((item) => item['checked'] != 1).length,
      });
    }
    return (result, selected, showRemaining);
  }

  @override
  void dispose() {
    widget.app.removeListener(reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        '여행 준비 도우미',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          tooltip: '설정',
          onPressed: () async { await Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => SettingsScreen(widget.app)),
          ); if (mounted) reload(); },
          icon: const Icon(Icons.tune),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => TripForm(widget.app)),
      ),
      icon: const Icon(Icons.add),
      label: const Text('새 여행'),
    ),
    body: FutureBuilder<(List<DbRow>, int, bool)>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: reload,
              child: const Text('여행을 불러오지 못했어요. 다시 시도'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (trips, selectedId, showRemaining) = snapshot.data!;
        final featured = selectedDdayTrip(trips, selectedId, DateTime.now());
        return RefreshIndicator(
          onRefresh: () async {
            reload();
            await data;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2362DC), Color(0xFF568CF8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.flight_takeoff_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      featured == null ? '다가오는 여행이 없어요' : '${countryByCode(featured['country']! as String).flag} ${featured['name']}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      featured == null ? '출발일을 입력하면 D-day가 표시돼요.' : dDay(DateTime.parse(featured['departure']! as String), DateTime.now()),
                      style: TextStyle(color: Colors.white, fontSize: featured == null ? 15 : 32, fontWeight: featured == null ? FontWeight.normal : FontWeight.bold),
                    ),
                    if (featured != null) ...[
                      const SizedBox(height: 6),
                      Text('${featured['departure']} 출발${showRemaining ? ' · 체크리스트 ${featured['checklistRemaining']}개 남음' : ''}', style: const TextStyle(color: Colors.white)),
                      TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TripDetail(widget.app, featured['id']! as int))),
                        style: TextButton.styleFrom(foregroundColor: Colors.white), child: const Text('여행 보기 ›')),
                    ],
                  ],
                ),
              ),
              SectionTitle(
                '나의 여행',
                action: Chip(label: Text('${trips.length}개')),
              ),
              if (trips.isEmpty)
                const EmptyState(
                  '첫 여행을 준비해 볼까요?',
                  '아래 새 여행 버튼으로 시작하세요.\n출발일은 나중에 정해도 괜찮아요.',
                ),
              ...trips.map((t) {
                final c = countryByCode(t['country']! as String);
                final remaining = t['remaining']! as BigInt;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              TripDetail(widget.app, t['id']! as int),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  c.flag,
                                  style: const TextStyle(fontSize: 36),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    t['name']! as String,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Chip(label: Text(c.name)),
                                Chip(
                                  label: Text(
                                    dDay(
                                      t['departure'] == null
                                          ? null
                                          : DateTime.parse(
                                              t['departure']! as String,
                                            ),
                                      DateTime.now(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              remaining.isNegative
                                  ? '예산 초과 ${formatWon(remaining.abs())}'
                                  : '남은 예산 ${formatWon(remaining)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: remaining.isNegative
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    ),
  );
}
