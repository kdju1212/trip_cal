import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../domain.dart';

const chartColors = [
  Color(0xFF377CF6),
  Color(0xFF65B9B3),
  Color(0xFFF2B66D),
  Color(0xFF9B8BDA),
  Color(0xFFEF8896),
  Color(0xFF58A9DB),
  Color(0xFFB5C579),
  Color(0xFFD39DCD),
  Color(0xFF8895A7),
];

class BudgetChart extends StatelessWidget {
  const BudgetChart(this.expenses, this.budget, {super.key});
  final List<DbRow> expenses;
  final BigInt budget;
  @override
  Widget build(BuildContext context) {
    final totals = categoryTotals(
      expenses,
    ).entries.where((e) => e.value > BigInt.zero).toList();
    final total = totalWon(expenses);
    final remaining = budget - total;
    final entries = [
      ...totals,
      if (remaining > BigInt.zero) MapEntry('남은 예산', remaining),
    ];
    final denominator = entries.fold(BigInt.zero, (s, e) => s + e.value);
    // Ratios are bounded before conversion to doubles; never chart negative values.
    double ratio(BigInt n, BigInt d) =>
        (n * BigInt.from(1000000) ~/ d).toDouble() / 1000000;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (denominator == BigInt.zero)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('예산이나 경비를 입력하면 차트가 표시돼요.'),
              )
            else ...[
              SizedBox(
                height: 150,
                child: Semantics(
                  label: '카테고리별 경비 및 남은 예산 도넛 차트',
                  child: PieChart(
                    PieChartData(
                      centerSpaceRadius: 56,
                      sectionsSpace: 3,
                      sections: [
                        for (var i = 0; i < entries.length; i++)
                          PieChartSectionData(
                            value: ratio(
                              entries[i].value,
                              denominator,
                            ).clamp(.000001, 1).toDouble(),
                            title: '',
                            radius: 28,
                            color: entries[i].key == '남은 예산'
                                ? Theme.of(context).colorScheme.outlineVariant
                                : chartColors[i % chartColors.length],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < entries.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: entries[i].key == '남은 예산'
                              ? Theme.of(context).colorScheme.outlineVariant
                              : chartColors[i % chartColors.length],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(entries[i].key)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          formatWon(entries[i].value),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
