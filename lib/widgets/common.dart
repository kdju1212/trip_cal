import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

void message(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
Future<T?> guarded<T>(BuildContext context, Future<T> Function() action) async {
  try { return await action(); }
  catch (error) { if (context.mounted) message(context, error is FormatException ? error.message.toString() : '저장하지 못했어요. 다시 시도해 주세요.'); return null; }
}
Future<bool> confirm(BuildContext context, String title, String body, {String action = '확인'}) async => await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(title), content: SingleChildScrollView(child: Text(body)), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action))])) ?? false;
Future<void> openExternal(BuildContext context, String raw) async {
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) { message(context, '올바른 HTTPS 링크가 아니에요.'); return; }
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) message(context, '링크를 열 수 없어요.');
  } catch (_) { if (context.mounted) message(context, '링크를 열 수 없어요.'); }
}
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {this.action, super.key});
  final String title;
  final Widget? action;
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 20, bottom: 12), child: Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))), ?action]));
}
class EmptyState extends StatelessWidget {
  const EmptyState(this.title, this.subtitle, {this.icon = Icons.luggage_outlined, super.key});
  final String title, subtitle;
  final IconData icon;
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 16), Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center), const SizedBox(height: 8), Text(subtitle, textAlign: TextAlign.center)]));
}
class NumberInputFormatter extends TextInputFormatter {
  const NumberInputFormatter({this.decimals = 0});
  final int decimals;
  @override TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.replaceAll(',', '');
    if (raw.length > 24 || !RegExp(decimals == 0 ? r'^\d*$' : '^\\d*(?:\\.\\d{0,$decimals})?\$').hasMatch(raw)) return oldValue;
    final parts = raw.split('.');
    final integer = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    final text = '$integer${parts.length > 1 ? '.${parts[1]}' : ''}';
    final right = newValue.text.length - newValue.selection.extentOffset;
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: (text.length - right).clamp(0, text.length)));
  }
}
String rawNumber(TextEditingController c) => c.text.replaceAll(',', '').trim();
String groupedNumber(String s) => s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
