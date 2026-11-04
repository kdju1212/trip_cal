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
    final max = totals.fold(BigInt.one, (s, e) => e.value > s ? e.value : s);
    // Ratios are bounded before conversion to doubles; never chart negative values.
    double ratio(BigInt n, BigInt d) =>
        (n * BigInt.from(1000000) ~/ d).toDouble() / 1000000;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '예산 한눈에 보기',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            if (denominator == BigInt.zero)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('예산이나 경비를 입력하면 차트가 표시돼요.'),
              )
            else ...[
              SizedBox(
                height: 190,
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
            if (totals.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('카테고리별 비교', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              SizedBox(
                height: 150,
                child: Semantics(
                  label: '카테고리별 예상 경비 막대 차트. 아래 숫자는 범례 순서입니다.',
                  child: BarChart(
                    BarChartData(
                      maxY: 1.15,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (v, meta) =>
                                Text('${v.toInt() + 1}'),
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < totals.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: ratio(totals[i].value, max),
                                width: 16,
                                color: chartColors[i % chartColors.length],
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ],
                          ),
                      ],
                      barTouchData: BarTouchData(enabled: false),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                [
                  for (var i = 0; i < totals.length; i++)
                    '${i + 1}. ${totals[i].key}',
                ].join('   '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
