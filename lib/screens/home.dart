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
  late Future<List<DbRow>> data;
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

  Future<List<DbRow>> load() async {
    final trips = await widget.app.store.trips();
    final result = <DbRow>[];
    for (final trip in trips) {
      final expenses = await widget.app.store.expenses(trip['id']! as int);
      result.add({
        ...trip,
        'remaining':
            BigInt.parse(trip['budget']! as String) - totalWon(expenses),
      });
    }
    return result;
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
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => SettingsScreen(widget.app)),
          ),
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
    body: FutureBuilder<List<DbRow>>(
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
        final trips = snapshot.data!;
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
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.flight_takeoff_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                    SizedBox(height: 20),
                    Text(
                      '설렘은 더하고,\n걱정은 덜어내세요.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        height: 1.35,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '예산부터 준비물까지, 떠나기 전 한곳에서.',
                      style: TextStyle(color: Colors.white, height: 1.5),
                    ),
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
