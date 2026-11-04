import 'package:flutter/material.dart';
import '../controller.dart';
import '../domain.dart';
import '../widgets/common.dart';

class TripForm extends StatefulWidget {
  const TripForm(this.app, {this.trip, super.key});
  final AppController app;
  final DataRow? trip;
  @override State<TripForm> createState() => _TripFormState();
}
class _TripFormState extends State<TripForm> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.trip?['name'] as String?);
  late final budget = TextEditingController(text: groupedNumber(widget.trip?['budget'] as String? ?? ''));
  late Country country = countryByCode(widget.trip?['country'] as String? ?? 'KR');
  late DateTime? departure = widget.trip?['departure'] == null ? null : DateTime.parse(widget.trip!['departure']! as String);
  bool saving = false;
  @override void dispose() { name.dispose(); budget.dispose(); super.dispose(); }
  Future<void> selectCountry() async {
    final selected = await showModalBottomSheet<Country>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const CountryPicker());
    if (selected != null && mounted) setState(() => country = selected);
  }
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    final result = await guarded(context, () async {
      final row = <String, Object?>{'name': name.text.trim(), 'country': country.code, 'budget': rawNumber(budget), 'departure': departure == null ? null : dateText(departure!)};
      if (widget.trip == null) { await widget.app.store.createTrip(row); }
      else { await widget.app.store.updateTrip(widget.trip!['id']! as int, row); }
      await widget.app.changed();
      return true;
    });
    if (!mounted) return;
    if (result == true) { Navigator.pop(context); }
    else { setState(() => saving = false); }
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.trip == null ? '새로운 여행' : '여행 수정')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: Form(key: form, child: ListView(padding: const EdgeInsets.all(24), children: [
      Text('어디로 떠나시나요?', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8), const Text('일정이 정해지지 않아도, 예산부터 준비해 보세요.'), const SizedBox(height: 28),
      TextFormField(controller: name, maxLength: 80, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: '여행 이름', hintText: '나를 위한 일본 여행', prefixIcon: Icon(Icons.edit_outlined)), validator: (s) => s == null || s.trim().isEmpty ? '여행 이름을 입력해 주세요.' : null),
      const SizedBox(height: 12),
      Card(child: ListTile(onTap: selectCountry, leading: Text(country.flag, style: const TextStyle(fontSize: 30)), title: Text(country.name), subtitle: Text('현지 통화 ${country.currency} · ${country.symbol}'), trailing: const Icon(Icons.expand_more))),
      const SizedBox(height: 20),
      TextFormField(controller: budget, keyboardType: TextInputType.number, inputFormatters: const [NumberInputFormatter()], decoration: const InputDecoration(labelText: '총 여행 예산', suffixText: '원', prefixIcon: Icon(Icons.account_balance_wallet_outlined)), validator: (s) => BigInt.tryParse(rawNumber(budget)) == null ? '0 이상의 예산을 입력해 주세요.' : null),
      const SizedBox(height: 20),
      Card(child: ListTile(leading: const Icon(Icons.calendar_today_outlined), title: Text(departure == null ? '출발일 선택' : dateText(departure!)), subtitle: const Text('선택 사항'), trailing: departure == null ? null : IconButton(tooltip: '출발일 지우기', onPressed: () => setState(() => departure = null), icon: const Icon(Icons.close)), onTap: () async {
        final date = await showDatePicker(context: context, initialDate: departure ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
        if (mounted && date != null) setState(() => departure = date);
      })),
      if (widget.trip != null) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('국가를 바꿔도 기존 경비와 준비물은 유지됩니다. 필요한 준비물은 직접 추가해 주세요.')),
      const SizedBox(height: 28), FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.check), label: Padding(padding: const EdgeInsets.all(14), child: Text(saving ? '저장 중…' : '여행 저장'))),
    ])))),
  );
}
class CountryPicker extends StatefulWidget {
  const CountryPicker({super.key});
  @override State<CountryPicker> createState() => _CountryPickerState();
}
class _CountryPickerState extends State<CountryPicker> {
  String query = '';
  @override Widget build(BuildContext context) {
    final filtered = countries.where((c) => '${c.name} ${c.code} ${c.currency}'.toLowerCase().contains(query.toLowerCase())).toList();
    return SafeArea(child: SizedBox(height: MediaQuery.sizeOf(context).height * .8, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
      Text('여행 국가', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 16),
      TextField(autofocus: true, decoration: const InputDecoration(hintText: '국가명 또는 통화 검색', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => query = v)), const SizedBox(height: 12),
      Expanded(child: filtered.isEmpty ? const Center(child: Text('검색 결과가 없어요.')) : ListView.builder(itemCount: filtered.length, itemBuilder: (context, i) { final c = filtered[i]; return ListTile(leading: Text(c.flag, style: const TextStyle(fontSize: 28)), title: Text(c.name), subtitle: Text('${c.code} · ${c.currency}'), onTap: () => Navigator.pop(context, c)); })),
    ]))));
  }
}
