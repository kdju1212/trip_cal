import 'package:flutter/material.dart';
import '../controller.dart';
import '../domain.dart';
import '../services/rates.dart';
import '../widgets/common.dart';

class _Entry {
  _Entry([this.original]) {
    if (original != null) {
      category = original!['category']! as String;
      if (category == '__custom') { custom.text = category; }
      currency = original!['currency']! as String;
      amount.text = groupedNumber(original!['amount']! as String);
      if (currency != 'KRW') {
        quote = RateQuote(currency, original!['rate']! as String,
          original!['rate_date'] as String? ?? '',
          original!['rate_source'] as String? ?? '저장된 환율');
      }
    }
  }
  final DbRow? original;
  String category = categories.first;
  String currency = 'KRW';
  final amount = TextEditingController();
  final custom = TextEditingController();
  RateQuote? quote;
  bool loading = false;
  int generation = 0;
  String get label => category == '__custom' ? custom.text.trim() : category;
  bool get matchesOriginal {
    final old = original;
    if (old == null) { return false; }
    final foreign = old['currency'] != 'KRW';
    return label == old['category'] && rawNumber(amount) == old['amount'] &&
        currency == old['currency'] &&
        (!foreign || (quote != null && quote!.rate == old['rate'] &&
          quote!.date == (old['rate_date'] ?? '') &&
          quote!.source == (old['rate_source'] ?? '저장된 환율')));
  }
  DbRow asRow() {
    final old = original;
    final untouched = matchesOriginal;
    if (untouched && old != null) {
      return {
        for (final key in ['id', 'name', 'category', 'amount', 'currency', 'rate', 'rate_date', 'rate_source']) key: old[key],
      };
    }
    return {
      if (old != null) 'id': old['id'],
      'name': old != null && label == old['category'] ? old['name'] : label,
      'category': label,
      'amount': rawNumber(amount),
      'currency': currency,
      'rate': currency == 'KRW' ? '1' : quote!.rate,
      'rate_date': currency == 'KRW' ? null : quote!.date,
      'rate_source': currency == 'KRW' ? 'KRW' : quote!.source,
    };
  }
  void dispose() {
    amount.dispose();
    custom.dispose();
  }
}

class ExpenseBatchForm extends StatefulWidget {
  const ExpenseBatchForm(this.app, this.trip, {super.key});
  final AppController app;
  final DbRow trip;
  @override
  State<ExpenseBatchForm> createState() => _ExpenseBatchFormState();
}

class _ExpenseBatchFormState extends State<ExpenseBatchForm> {
  final form = GlobalKey<FormState>();
  final entries = <_Entry>[];
  List<DbRow> original = [];
  bool saving = false, loadingEntries = true, loadFailed = false;
  late final country = countryByCode(widget.trip['country']! as String);
  @override
  void initState() {
    super.initState();
    loadEntries();
  }

  Future<void> loadEntries() async {
    setState(() { loadingEntries = true; loadFailed = false; });
    try {
      final saved = await widget.app.store.expenses(widget.trip['id']! as int);
      if (!mounted) { return; }
      setState(() {
        original = saved;
        entries.addAll(saved.map((row) => _Entry(row)));
        if (entries.isEmpty) { entries.add(_Entry()); }
        loadingEntries = false;
      });
    } catch (_) {
      if (mounted) { setState(() { loadingEntries = false; loadFailed = true; }); }
    }
  }

  @override
  void dispose() {
    for (final row in entries) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> changeCurrency(_Entry row, String next) async {
    if (row.currency == next) {
      return;
    }
    if (!mounted || !entries.contains(row)) {
      return;
    }
    setState(() {
      row.generation++;
      row.currency = next;
      row.quote = null;
      row.loading = false;
    });
    if (next != 'KRW') {
      await fetch(row);
    }
  }

  Future<void> fetch(_Entry row) async {
    final code = row.currency;
    final request = ++row.generation;
    setState(() => row.loading = true);
    try {
      final quote = await widget.app.rates.latest(code);
      if (!mounted || !entries.contains(row) || row.generation != request) {
        return;
      }
      setState(() {
        row.quote = quote;
        row.loading = false;
      });
      if (quote.cached) {
        message(context, '최신 환율을 가져오지 못해 저장된 환율을 사용합니다.');
      }
    } catch (_) {
      if (!mounted || !entries.contains(row) || row.generation != request) {
        return;
      }
      setState(() => row.loading = false);
      message(context, '환율을 가져오지 못했어요. 직접 입력해 주세요.');
    }
  }

  Future<void> manualRate(_Entry row) async {
    final controller = TextEditingController(text: row.quote?.rate ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('환율 직접 입력'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const [NumberInputFormatter(decimals: 12)],
          decoration: const InputDecoration(labelText: '외화 1단위당 원화'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, rawNumber(controller)),
            child: const Text('적용'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || result == null || !entries.contains(row)) {
      return;
    }
    final quote = await guarded(
      context,
      () => widget.app.rates.manual(
        row.currency,
        result,
        dateText(DateTime.now()),
      ),
    );
    if (mounted && entries.contains(row) && quote != null) {
      setState(() => row.quote = quote);
    }
  }

  BigInt? converted(_Entry row) {
    try {
      if (row.matchesOriginal) { return BigInt.parse(row.original!['won']! as String); }
      if (row.currency != 'KRW' && row.quote == null) {
        return null;
      }
      return convertToWon(
        rawNumber(row.amount),
        row.currency == 'KRW' ? '1' : row.quote!.rate,
        fractionDigits: currencyInfo(row.currency).fractionDigits,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    if (entries.any((row) => converted(row) == null)) {
      message(context, '각 항목의 금액과 환율을 확인해 주세요.');
      return;
    }
    setState(() => saving = true);
    final result = await guarded(context, () async {
      final rows = entries.map((row) => row.asRow()).toList();
      await widget.app.store.saveExpenseChanges(widget.trip['id']! as int, original, rows);
      await widget.app.changed();
      return true;
    });
    if (!mounted) {
      return;
    }
    if (result == true) {
      Navigator.pop(context);
    } else {
      setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('예상 경비 추가')),
    body: loadingEntries
      ? const Center(child: CircularProgressIndicator())
      : loadFailed
      ? Center(child: TextButton(onPressed: loadEntries, child: const Text('경비를 불러오지 못했어요. 다시 시도')))
      : SafeArea(
      top: false,
      child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
            children: [
              Text('저장된 경비가 위에 표시됩니다. 항목을 추가하거나 수정한 뒤 저장해 주세요.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              for (final row in entries) entryCard(row),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: saving
                    ? null
                    : () => setState(() => entries.add(_Entry())),
                icon: const Icon(Icons.add),
                label: const Text('항목 추가'),
              ),
              const SizedBox(height: 24),
              remainingBudget(),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: saving ? null : save,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(saving ? '저장 중…' : '${entries.length}개 경비 저장'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    ),
  );

  Widget remainingBudget() {
    var total = BigInt.zero;
    var incomplete = false;
    for (final row in entries) {
      final amount = converted(row);
      if (amount == null) {
        incomplete = true;
      } else {
        total += amount;
      }
    }
    final remaining = BigInt.parse(widget.trip['budget']! as String) - total;
    return Semantics(
      liveRegion: true,
      child: Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('남은 예산', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(formatWon(remaining), style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: remaining.isNegative ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
          )),
          if (remaining.isNegative) Text('예산 초과 ${formatWon(remaining.abs())}'),
          if (incomplete) Text('금액이나 환율을 입력하지 않은 항목은 제외했어요.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      )),
    );
  }

  Widget entryCard(_Entry row) {
    final choices = {'KRW', if (country.currency != 'KRW') country.currency, row.currency};
    final won = converted(row);
    final compactDecoration = const InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
    );
    return Card(
      key: ObjectKey(row),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: DropdownButtonFormField<String>(
                    initialValue: row.category,
                    isExpanded: true,
                    decoration: compactDecoration.copyWith(labelText: '항목'),
                    items: [
                      ...{...categories, if (row.category != '__custom') row.category}.map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      const DropdownMenuItem(
                        value: '__custom',
                        child: Text('직접 입력', overflow: TextOverflow.ellipsis),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) => setState(() => row.category = value!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 6,
                  child: TextFormField(
                    controller: row.amount,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: currencyInfo(row.currency).fractionDigits > 0,
                    ),
                    inputFormatters: [
                      NumberInputFormatter(
                        decimals: currencyInfo(row.currency).fractionDigits,
                      ),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: compactDecoration.copyWith(
                      labelText: '금액',
                      prefixText: '${currencyInfo(row.currency).symbol} ',
                    ),
                    validator: (_) {
                      try {
                        convertToWon(
                          rawNumber(row.amount),
                          '1',
                          fractionDigits: currencyInfo(
                            row.currency,
                          ).fractionDigits,
                        );
                        return null;
                      } catch (_) {
                        return '금액 확인';
                      }
                    },
                  ),
                ),
                if (entries.length > 1 || row.original != null)
                  IconButton(
                    tooltip: '항목 삭제',
                    visualDensity: VisualDensity.compact,
                    onPressed: saving
                        ? null
                        : () {
                            setState(() {
                              entries.remove(row);
                              row.generation++;
                            });
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => row.dispose(),
                            );
                          },
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
            if (row.category == '__custom')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextFormField(
                  controller: row.custom,
                  maxLength: 30,
                  decoration: compactDecoration.copyWith(
                    labelText: '직접 입력할 항목',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '항목을 입력하세요.' : null,
                ),
              ),
            if (choices.length > 1)
              Row(
                children: [
                  Text('통화', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: row.currency,
                    underline: const SizedBox.shrink(),
                    items: choices
                        .map(
                          (code) => DropdownMenuItem(
                            value: code,
                            child: Text('$code ${currencyInfo(code).symbol}'),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) {
                            if (value != null) {
                              changeCurrency(row, value);
                            }
                          },
                  ),
                ],
              ),
            if (row.currency != 'KRW') ...[
              if (row.quote == null)
                Text('환율 조회 또는 직접 입력이 필요해요.', style: Theme.of(context).textTheme.bodySmall),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: saving || row.loading ? null : () => fetch(row),
                    icon: const Icon(Icons.refresh),
                    label: Text(row.loading ? '조회 중…' : '환율 새로고침'),
                  ),
                  TextButton(
                    onPressed: saving || row.loading
                        ? null
                        : () => manualRate(row),
                    child: const Text('직접 입력'),
                  ),
                ],
              ),
              Text(
                '원화 환산 ${won == null ? '—' : formatWon(won)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
