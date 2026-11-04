import 'package:flutter/material.dart';
import '../controller.dart';
import '../domain.dart';
import '../services/rates.dart';
import '../widgets/common.dart';

class ExpenseForm extends StatefulWidget {
  const ExpenseForm(this.app, this.trip, {this.expense, super.key});
  final AppController app;
  final DbRow trip;
  final DbRow? expense;
  @override State<ExpenseForm> createState() => _ExpenseFormState();
}
class _ExpenseFormState extends State<ExpenseForm> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.expense?['name'] as String?);
  late final amount = TextEditingController(text: groupedNumber(widget.expense?['amount'] as String? ?? ''));
  late final customCategory = TextEditingController(text: widget.expense?['category'] as String? ?? '');
  late String category = widget.expense?['category'] as String? ?? categories.first;
  late String currency = widget.expense?['currency'] as String? ?? 'KRW';
  late final country = countryByCode(widget.trip['country']! as String);
  RateQuote? quote;
  bool loading = false, saving = false;
  int generation = 0;
  @override void initState() {
    super.initState();
    final e = widget.expense;
    if (e != null && currency != 'KRW') {
      quote = RateQuote(currency, e['rate']! as String, e['rate_date'] as String? ?? '', e['rate_source'] as String? ?? '저장된 환율');
    }
  }
  @override void dispose() { name.dispose(); amount.dispose(); customCategory.dispose(); super.dispose(); }
  Future<void> fetchRate() async {
    final code = currency;
    final request = ++generation;
    setState(() => loading = true);
    try {
      final result = await widget.app.rates.latest(code);
      if (mounted && currency == code && generation == request) {
        setState(() { quote = result; loading = false; });
        if (result.cached) message(context, '조회에 실패해 저장된 환율을 불러왔어요. 기준 날짜를 확인하세요.');
      }
    } on FormatException catch (e) {
      if (mounted && generation == request) { setState(() => loading = false); message(context, e.message.toString()); }
    }
  }
  Future<void> changeCurrency(String next) async {
    if (next == currency) return;
    if (amount.text.isNotEmpty && !await confirm(context, '통화를 바꿀까요?', '숫자가 다른 통화로 해석되지 않도록 입력 금액을 초기화합니다.', action: '초기화하고 변경')) return;
    if (!mounted) return;
    generation++;
    setState(() { currency = next; amount.clear(); quote = null; loading = false; });
    if (next != 'KRW') await fetchRate();
  }
  Future<void> manualRate() async {
    final c = TextEditingController(text: quote?.rate ?? '');
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: Text('1 $currency = ? 원'), content: TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: const [NumberInputFormatter(decimals: 12)], decoration: const InputDecoration(labelText: '직접 입력 환율', helperText: '0보다 큰 값을 입력하세요.')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')), FilledButton(onPressed: () => Navigator.pop(context, rawNumber(c)), child: const Text('적용'))]));
    c.dispose();
    if (value == null || !mounted) return;
    final q = await guarded(context, () => widget.app.rates.manual(currency, value, dateText(DateTime.now())));
    if (mounted && q != null) setState(() => quote = q);
  }
  BigInt? get converted {
    try {
      if (currency != 'KRW' && quote == null) return null;
      return convertToWon(rawNumber(amount), currency == 'KRW' ? '1' : quote!.rate, fractionDigits: currencyInfo(currency).fractionDigits);
    } catch (_) { return null; }
  }
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (converted == null) { message(context, '금액과 환율을 확인해 주세요.'); return; }
    setState(() => saving = true);
    final result = await guarded(context, () async {
      await widget.app.store.saveExpense(widget.trip['id']! as int, {
        'name': name.text.trim(), 'category': category == '__custom' ? customCategory.text.trim() : category,
        'amount': rawNumber(amount), 'currency': currency, 'rate': currency == 'KRW' ? '1' : quote!.rate,
        'rate_date': currency == 'KRW' ? null : quote!.date, 'rate_source': currency == 'KRW' ? 'KRW' : quote!.source,
      }, id: widget.expense?['id'] as int?);
      await widget.app.changed();
      return true;
    });
    if (!mounted) return;
    if (result == true) { Navigator.pop(context); }
    else { setState(() => saving = false); }
  }
  @override Widget build(BuildContext context) {
    final choices = {'KRW', if (country.currency != 'KRW') country.currency, currency};
    final cats = {...categories, if (category != '__custom') category};
    return Scaffold(appBar: AppBar(title: Text(widget.expense == null ? '예상 경비 추가' : '예상 경비 수정')),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: Form(key: form, child: ListView(padding: const EdgeInsets.all(24), children: [
        const Text('예약 전에도, 계획은 가볍게'), const SizedBox(height: 20),
        TextFormField(controller: name, maxLength: 80, decoration: const InputDecoration(labelText: '경비 이름', hintText: '왕복 항공권, 3박 호텔…'), validator: (v) => v == null || v.trim().isEmpty ? '경비 이름을 입력해 주세요.' : null),
        const SizedBox(height: 12), DropdownButtonFormField<String>(initialValue: category, isExpanded: true, decoration: const InputDecoration(labelText: '카테고리'), items: [...cats.map((c) => DropdownMenuItem(value: c, child: Text(c))), const DropdownMenuItem(value: '__custom', child: Text('+ 카테고리 직접 입력'))], onChanged: (v) => setState(() => category = v!)),
        if (category == '__custom') Padding(padding: const EdgeInsets.only(top: 16), child: TextFormField(controller: customCategory, maxLength: 30, decoration: const InputDecoration(labelText: '새 카테고리 이름'), validator: (v) => v == null || v.trim().isEmpty ? '카테고리를 입력하세요.' : null)),
        const SizedBox(height: 24), Text('입력 통화', style: Theme.of(context).textTheme.titleSmall), const SizedBox(height: 10),
        if (choices.length > 1) SegmentedButton<String>(showSelectedIcon: false, direction: choices.length > 2 || MediaQuery.sizeOf(context).width < 360 || MediaQuery.textScalerOf(context).scale(1) > 1.25 ? Axis.vertical : Axis.horizontal, segments: choices.map((c) => ButtonSegment(value: c, label: Text('$c ${currencyInfo(c).symbol}'))).toList(), selected: {currency}, onSelectionChanged: saving ? null : (s) => changeCurrency(s.first)) else const Chip(label: Text('KRW ₩ 원화')),
        const SizedBox(height: 20), TextFormField(controller: amount, keyboardType: TextInputType.numberWithOptions(decimal: currencyInfo(currency).fractionDigits > 0), inputFormatters: [NumberInputFormatter(decimals: currencyInfo(currency).fractionDigits)], onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: '금액', suffixText: currency, prefixText: '${currencyInfo(currency).symbol} '), validator: (s) { try { convertToWon(rawNumber(amount), '1', fractionDigits: currencyInfo(currency).fractionDigits); return null; } catch (_) { return '올바른 금액을 입력해 주세요.'; } }),
        if (currency != 'KRW') ...[
          const SizedBox(height: 20), Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('최신 참고 환율', style: Theme.of(context).textTheme.titleSmall), const SizedBox(height: 8),
            Text(quote == null ? '환율 조회 또는 직접 입력이 필요해요.' : '1 $currency = ${quote!.rate} 원'),
            if (quote != null) Text('${quote!.date} · ${quote!.source}${quote!.cached ? ' · 저장된 환율' : ''}'),
            Wrap(spacing: 8, children: [TextButton.icon(onPressed: loading ? null : fetchRate, icon: const Icon(Icons.refresh), label: Text(loading ? '조회 중…' : '환율 새로고침')), TextButton(onPressed: loading ? null : manualRate, child: const Text('직접 입력'))]),
          ]))),
        ],
        const SizedBox(height: 24), Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('원화 환산 예상 경비'), const SizedBox(height: 8), Text(converted == null ? '—' : formatWon(converted!), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))])),
        const SizedBox(height: 12), const Text('저장 시 적용한 환율을 보존합니다. 실제 결제 금액에는 수수료와 환율 차이가 있을 수 있어요.'),
        const SizedBox(height: 28), FilledButton(onPressed: saving ? null : save, child: Padding(padding: const EdgeInsets.all(14), child: Text(saving ? '저장 중…' : '경비 저장'))),
      ])))),
    );
  }
}
