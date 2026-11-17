import 'package:intl/intl.dart';

String initials(String name) {
  // Ignore tokens such as "(TEST)" or "&" so initials are always letters.
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .map((p) => p.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), ''))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}

String timeAgo(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  // A phone clock a little behind the server makes brand-new items look "future".
  if (diff.isNegative) return diff.inMinutes > -5 ? 'just now' : dueLabel(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('d MMM').format(time);
}

/// "Today, 4:30 pm", "Tomorrow, 10:00 am", "Mon 24 Nov, 9:15 am".
String dueLabel(DateTime? time) {
  if (time == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final clock = DateFormat('h:mm a').format(time).toLowerCase();
  final delta = day.difference(today).inDays;
  if (delta == 0) return 'Today, $clock';
  if (delta == 1) return 'Tomorrow, $clock';
  if (delta == -1) return 'Yesterday, $clock';
  return '${DateFormat(time.year == now.year ? 'EEE d MMM' : 'd MMM y').format(time)}, $clock';
}

String fullDate(DateTime? time) => time == null ? '' : DateFormat('d MMM y, h:mm a').format(time);

String dateOnly(String iso) {
  final parsed = DateTime.tryParse(iso);
  return parsed == null ? iso : DateFormat('d MMM y').format(parsed);
}

String money(num? value, String currency, {bool compact = false}) {
  if (value == null) return '—';
  final symbol = NumberFormat.simpleCurrency(name: currency).currencySymbol;
  return compact
      ? NumberFormat.compactSimpleCurrency(name: currency).format(value)
      : NumberFormat.currency(symbol: symbol, decimalDigits: value % 1 == 0 ? 0 : 2).format(value);
}

String greeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Working late';
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Website brief keys from the enquiry form, in reading order.
const briefLabels = {
  'type': 'Project type',
  'audience': 'Audience',
  'stage': 'Project stage',
  'budget': 'Budget',
  'timeline': 'Timeline',
  'contactMethod': 'Preferred contact',
  'location': 'Location',
  'existingUrl': 'Existing site',
  'features': 'Features',
  'entryPoint': 'Form',
};

String briefLabel(String key) {
  if (briefLabels.containsKey(key)) return briefLabels[key]!;
  final clean = key.replaceFirst('detail_', '').replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  return clean.isEmpty ? key : '${clean[0].toUpperCase()}${clean.substring(1)}';
}
