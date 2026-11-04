import 'package:flutter/material.dart';
import '../controller.dart';
import '../domain.dart';
import '../widgets/common.dart';

class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen(this.app, this.tripId, {super.key});
  final AppController app;
  final int tripId;
  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  late Future<List<DbRow>> data;
  @override
  void initState() {
    super.initState();
    reload();
    widget.app.addListener(reload);
  }

  void reload() {
    data = widget.app.store.checklist(widget.tripId);
    if (mounted) { setState(() {}); }
  }

  @override
  void dispose() {
    widget.app.removeListener(reload);
    super.dispose();
  }

  Future<void> edit([DbRow? item]) async {
    final name = TextEditingController(text: item?['name'] as String?);
    final category = TextEditingController(
      text: item?['category'] as String? ?? '직접 추가',
    );
    final form = GlobalKey<FormState>();
    final result = await showDialog<DbRow>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item == null ? '준비물 추가' : '준비물 수정'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: '준비물 이름'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '이름을 입력해 주세요.' : null,
                ),
                TextFormField(
                  controller: category,
                  maxLength: 30,
                  decoration: const InputDecoration(labelText: '분류'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '분류를 입력해 주세요.' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate())
                { Navigator.pop(context, <String, Object?>{
                  'name': name.text.trim(),
                  'category': category.text.trim(),
                }); }
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    name.dispose();
    category.dispose();
    if (result == null || !mounted) { return; }
    await guarded(context, () async {
      if (item == null) {
        await widget.app.store.db.insert('checklist', {
          ...result,
          'trip_id': widget.tripId,
        });
      } else {
        await widget.app.store.db.update(
          'checklist',
          result,
          where: 'id = ? AND trip_id = ?',
          whereArgs: [item['id'], widget.tripId],
        );
      }
      await widget.app.changed();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('여행 준비물')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: edit,
      icon: const Icon(Icons.add),
      label: const Text('준비물 추가'),
    ),
    body: FutureBuilder<List<DbRow>>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          { return Center(
            child: TextButton(onPressed: reload, child: const Text('다시 불러오기')),
          ); }
        if (!snapshot.hasData)
          { return const Center(child: CircularProgressIndicator()); }
        final items = snapshot.data!;
        final count = items.where((e) => e['checked'] == 1).length;
        final groups = items.map((e) => e['category']! as String).toSet();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count / ${items.length}개 준비 완료',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: items.isEmpty ? 0 : count / items.length,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${items.isEmpty ? 0 : (count / items.length * 100).round()}% 준비했어요. 하나씩 채워 보세요.',
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('eSIM·유심·로밍은 필요한 방식만 선택하면 됩니다. 모두 구매할 필요는 없어요.'),
            ),
            if (items.isEmpty)
              const EmptyState('준비물을 추가해 보세요', '여행에 필요한 것만 자유롭게 관리하세요.'),
            for (final group in groups) ...[
              SectionTitle(group),
              ...items
                  .where((e) => e['category'] == group)
                  .map(
                    (item) => Card(
                      child: Row(
                        children: [
                          Expanded(
                            child: CheckboxListTile(
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                item['name']! as String,
                                style: TextStyle(
                                  decoration: item['checked'] == 1
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              value: item['checked'] == 1,
                              onChanged: (checked) async {
                                await guarded(context, () async {
                                  await widget.app.store.db.update(
                                    'checklist',
                                    {'checked': checked == true ? 1 : 0},
                                    where: 'id = ? AND trip_id = ?',
                                    whereArgs: [item['id'], widget.tripId],
                                  );
                                  await widget.app.changed();
                                });
                              },
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (value) async {
                              if (value == 'edit') {
                                await edit(item);
                                return;
                              }
                              if (!await confirm(
                                    context,
                                    '준비물을 삭제할까요?',
                                    item['name']! as String,
                                    action: '삭제',
                                  ) ||
                                  !context.mounted)
                                { return; }
                              await guarded(context, () async {
                                await widget.app.store.db.delete(
                                  'checklist',
                                  where: 'id = ? AND trip_id = ?',
                                  whereArgs: [item['id'], widget.tripId],
                                );
                                await widget.app.changed();
                              });
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('수정')),
                              PopupMenuItem(value: 'delete', child: Text('삭제')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        );
      },
    ),
  );
}
