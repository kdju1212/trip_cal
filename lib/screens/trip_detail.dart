import 'package:flutter/material.dart';
import '../controller.dart';
import '../domain.dart';
import '../widgets/common.dart';
import '../services/rates.dart';
import '../widgets/budget_chart.dart';
import '../widgets/ad_banner.dart';
import 'expense_form.dart';
import 'trip_form.dart';
import 'checklist.dart';
import 'information.dart';

class TripDetail extends StatefulWidget {
  const TripDetail(this.app, this.tripId, {super.key});
  final AppController app;
  final int tripId;
  @override State<TripDetail> createState() => _TripDetailState();
}
class _TripDetailState extends State<TripDetail> {
  late Future<(DbRow?, List<DbRow>)> data;
  bool recalculating = false;
  @override void initState() { super.initState(); reload(); widget.app.addListener(reload); }
  void reload() { data = load(); if (mounted) setState(() {}); }
  Future<(DbRow?, List<DbRow>)> load() async {
    final trips = await widget.app.store.db.query('trips', where: 'id = ?', whereArgs: [widget.tripId]);
    return (trips.isEmpty ? null : trips.single, await widget.app.store.expenses(widget.tripId));
  }
  @override void dispose() { widget.app.removeListener(reload); super.dispose(); }
  Future<void> menu(String action, DbRow trip) async {
    if (action == 'edit') { await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TripForm(widget.app, trip: trip))); return; }
    if (action == 'delete') {
      if (!await confirm(context, '여행을 삭제할까요?', '경비, 준비물과 구매 안내 선택이 함께 삭제됩니다. 복구할 수 없어요.', action: '삭제')) return;
      if (!mounted) return;
      final result = await guarded(context, () async { await widget.app.store.deleteTrip(widget.tripId); await widget.app.changed(); return true; });
      if (mounted && result == true) Navigator.pop(context);
    }
    if (action == 'copy' && mounted) {
      await guarded(context, () async { await widget.app.store.duplicateTrip(widget.tripId); await widget.app.changed(); });
      if (mounted) message(context, '여행 목록에 복사본을 만들었어요.');
    }
  }
  Future<void> recalculate(List<DbRow> expenses) async {
    setState(() => recalculating = true);
    try {
      final foreign = expenses.where((e) => e['currency'] != 'KRW').toList();
      if (foreign.isEmpty) { message(context, '외화로 입력한 경비가 없어요.'); return; }
      final quotes = <String, RateQuote>{};
      for (final code in foreign.map((e) => e['currency']! as String).toSet()) { quotes[code] = await widget.app.rates.latest(code); }
      final preview = <DbRow>[];
      for (final e in foreign) {
        final q = quotes[e['currency']]!;
        preview.add({...e, 'rate': q.rate, 'rate_date': q.date, 'rate_source': q.source, 'won': convertToWon(e['amount']! as String, q.rate, fractionDigits: currencyInfo(e['currency']! as String).fractionDigits).toString()});
      }
      final old = totalWon(foreign), next = totalWon(preview);
      final info = quotes.values.map((q) => '${q.currency}: ${q.rate}원 · ${q.date} · ${q.source}${q.cached ? ' (저장된 환율)' : ''}').join('\n');
      if (!mounted) return;
      if (!await confirm(context, '환율 재계산 미리보기', '외화 경비 합계\n${formatWon(old)} → ${formatWon(next)}\n변경 차액 ${formatWon(next - old)}\n\n$info\n\n원래 외화 입력 금액을 기준으로 다시 계산합니다.', action: '재계산 적용')) return;
      if (!mounted) return;
      await guarded(context, () async { await widget.app.store.recalculate(widget.tripId, preview); await widget.app.changed(); });
    } on FormatException catch (e) { if (mounted) message(context, e.message.toString()); }
    catch (_) { if (mounted) message(context, '재계산하지 못했어요. 기존 경비는 유지됩니다.'); }
    finally { if (mounted) setState(() => recalculating = false); }
  }
  @override Widget build(BuildContext context) => FutureBuilder<(DbRow?, List<DbRow>)>(future: data, builder: (context, snapshot) {
    if (snapshot.hasError) return Scaffold(appBar: AppBar(), body: Center(child: TextButton(onPressed: reload, child: const Text('다시 불러오기'))));
    if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final (trip, expenses) = snapshot.data!;
    if (trip == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('삭제되었거나 찾을 수 없는 여행이에요.')));
    final country = countryByCode(trip['country']! as String);
    final budget = BigInt.parse(trip['budget']! as String), total = totalWon(expenses);
    final remaining = budget - total;
    final ratio = budgetRatio(total, budget);
    return Scaffold(
      appBar: AppBar(title: Text(trip['name']! as String), actions: [PopupMenuButton<String>(onSelected: (a) => menu(a, trip), itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('여행 수정')), PopupMenuItem(value: 'copy', child: Text('여행 복제')), PopupMenuItem(value: 'delete', child: Text('여행 삭제'))])]),
      bottomNavigationBar: const AdBanner(),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ExpenseForm(widget.app, trip))), icon: const Icon(Icons.add), label: const Text('경비 추가')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 110), children: [
        Wrap(spacing: 8, children: [Chip(label: Text('${country.flag} ${country.name}')), Chip(label: Text(dDay(trip['departure'] == null ? null : DateTime.parse(trip['departure']! as String), DateTime.now())))]), const SizedBox(height: 16),
        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: remaining.isNegative ? Theme.of(context).colorScheme.errorContainer : Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(24)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(remaining.isNegative ? '예산을 초과했어요' : '남은 여행 예산'), const SizedBox(height: 10), Text(formatWon(remaining.isNegative ? remaining.abs() : remaining), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 20), Text('총 예산 ${formatWon(budget)}'), Text('예상 경비 ${formatWon(total)}'), const SizedBox(height: 16), LinearProgressIndicator(value: ratio.clamp(0, 1).toDouble(), minHeight: 8, borderRadius: BorderRadius.circular(8)), const SizedBox(height: 8), Text(budget == BigInt.zero ? '총 예산이 0원입니다. 예산을 설정해 주세요.' : '예산 사용률 ${(ratio * 100).toStringAsFixed(1)}%')])),
        const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(avatar: const Icon(Icons.checklist), label: const Text('준비물'), onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ChecklistScreen(widget.app, widget.tripId)))),
          ActionChip(avatar: const Icon(Icons.lightbulb_outline), label: const Text('여행 꿀팁'), onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TipsScreen(country)))),
          ActionChip(avatar: const Icon(Icons.shopping_bag_outlined), label: const Text('구매 안내'), onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PurchaseScreen(widget.app, trip)))),
        ]), const SizedBox(height: 16), BudgetChart(expenses, budget),
        SectionTitle('예상 경비', action: IconButton(tooltip: '최신 환율로 다시 계산', onPressed: recalculating ? null : () => recalculate(expenses), icon: recalculating ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.currency_exchange))),
        if (expenses.isEmpty) const EmptyState('아직 경비가 없어요', '항공권부터 하나씩 예상 비용을 더해 보세요.', icon: Icons.receipt_long_outlined),
        ...expenses.map((e) => Card(child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), title: Text(e['name']! as String, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${e['category']} · ${groupedNumber(e['amount']! as String)} ${e['currency']}'), Text(formatWon(BigInt.parse(e['won']! as String)), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)), if (e['currency'] != 'KRW') Text('1 ${e['currency']} = ${e['rate']}원\n${e['rate_date']} · ${e['rate_source']}', style: Theme.of(context).textTheme.bodySmall)]), onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ExpenseForm(widget.app, trip, expense: e))), trailing: IconButton(tooltip: '경비 삭제', icon: const Icon(Icons.delete_outline), onPressed: () async {
          if (!await confirm(context, '경비를 삭제할까요?', e['name']! as String, action: '삭제') || !context.mounted) return;
          await guarded(context, () async { await widget.app.store.db.delete('expenses', where: 'id = ? AND trip_id = ?', whereArgs: [e['id'], widget.tripId]); await widget.app.changed(); });
        })))),
      ]),
    );
  });
}
