import 'package:flutter/material.dart';
import '../controller.dart';
import '../domain.dart';
import '../services/rates.dart';
import '../widgets/common.dart';

class _Entry {
  String category = categories.first;
  String currency = 'KRW';
  final amount = TextEditingController();
  final custom = TextEditingController();
  RateQuote? quote;
  bool loading = false;
  int generation = 0;
  String get label => category == '__custom' ? custom.text.trim() : category;
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
  final entries = <_Entry>[_Entry()];
  bool saving = false;
  late final country = countryByCode(widget.trip['country']! as String);
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
    if (row.amount.text.isNotEmpty &&
        !await confirm(
          context,
          '통화를 바꿀까요?',
          '입력한 금액이 다른 통화로 잘못 해석되지 않도록 금액을 초기화합니다.',
          action: '초기화하고 변경',
        )) {
      return;
    }
    if (!mounted || !entries.contains(row)) {
      return;
    }
    setState(() {
      row.generation++;
      row.currency = next;
      row.amount.clear();
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
        message(context, '저장된 환율을 불러왔어요. 기준 날짜를 확인하세요.');
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
        title: Text('1 ${row.currency} = ? 원'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const [NumberInputFormatter(decimals: 12)],
          decoration: const InputDecoration(labelText: '직접 입력 환율'),
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
      final rows = entries
          .map(
            (row) => <String, Object?>{
              'name': row.label,
              'category': row.label,
              'amount': rawNumber(row.amount),
              'currency': row.currency,
              'rate': row.currency == 'KRW' ? '1' : row.quote!.rate,
              'rate_date': row.currency == 'KRW' ? null : row.quote!.date,
              'rate_source': row.currency == 'KRW' ? 'KRW' : row.quote!.source,
            },
          )
          .toList();
      await widget.app.store.saveExpenses(widget.trip['id']! as int, rows);
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
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('항목을 여러 개 추가해 한 번에 저장할 수 있어요.'),
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
  );

  Widget entryCard(_Entry row) {
    final choices = {'KRW', if (country.currency != 'KRW') country.currency};
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
                      ...categories.map(
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
                if (entries.length > 1)
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
              Text(
                row.quote == null
                    ? '환율 조회 또는 직접 입력이 필요해요.'
                    : '1 ${row.currency} = ${row.quote!.rate}원 · ${row.quote!.date} · ${row.quote!.source}${row.quote!.cached ? ' (저장된 환율)' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
