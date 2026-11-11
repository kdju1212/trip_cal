import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain.dart';
import '../widgets/common.dart';

class TipsScreen extends StatefulWidget {
  const TipsScreen(this.country, {super.key});
  final Country country;
  @override
  State<TipsScreen> createState() => _TipsScreenState();
}

class _TipsScreenState extends State<TipsScreen> {
  late final Future<Map<String, dynamic>> data = load();
  Future<Map<String, dynamic>> load() async {
    final code = ['JP', 'US', 'TH', 'VN'].contains(widget.country.code)
        ? widget.country.code
        : 'common';
    return jsonDecode(await rootBundle.loadString('assets/tips/$code.json'))
        as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${widget.country.flag} 여행 꿀팁')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('여행 정보를 불러오지 못했어요.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final info = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              info['title'] as String,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              '비자·입국 조건과 안전 정보는 바뀔 수 있어요. 출발 전에 공식 기관의 최신 공지를 확인하세요. 아래 내용은 준비를 돕는 참고 안내입니다.',
            ),
            const SizedBox(height: 8),
            Text(
              '공식 출처 확인: ${info['checkedAt']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (final raw in info['sections'] as List)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        raw['title'] as String,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Text(raw['body'] as String),
                      if (raw['url'] != null)
                        TextButton.icon(
                          onPressed: () =>
                              openExternal(context, raw['url'] as String),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('공식 안내 확인'),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
