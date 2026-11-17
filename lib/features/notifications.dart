import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'record_detail.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Notice>? _items;
  final Map<String, CrmRecord> _records = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = AppScope.read(context);
    try {
      final list = (await app.api.get('/notifications') as List).map((e) => Notice(Map<String, dynamic>.from(e as Map))).toList();
      if (!mounted) return;
      setState(() {
        _items = list;
        _error = null;
      });
      // Seen now; the list keeps showing which ones were new on this visit.
      if (list.any((n) => !n.read)) app.markAllRead();
      // Names make the list scannable; fetch the first few records in parallel.
      final wanted = <String, Notice>{};
      for (final n in list) {
        if (n.kind != null && !_records.containsKey(n.recordId) && wanted.length < 20) wanted[n.recordId] = n;
      }
      await Future.wait(wanted.values.map((n) async {
        try {
          _records[n.recordId] = CrmRecord(Map<String, dynamic>.from(await app.api.get('/records/${n.kind!.name}/${n.recordId}') as Map));
        } catch (_) {}
      }));
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final fresh = items?.where((n) => !n.read).toList() ?? const [];
    final earlier = items?.where((n) => n.read).toList() ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        color: Brand.accent,
        onRefresh: _load,
        child: items == null
            ? (_error != null ? ListView(children: [ErrorState(_error!, onRetry: _load)]) : const SkeletonList())
            : items.isEmpty
                ? ListView(children: const [
                    EmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: 'You are all caught up',
                      message: 'New website enquiries, assignments and reminders will show up here.',
                    ),
                  ])
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    children: [
                      if (fresh.isNotEmpty) ...[const SectionTitle('New'), ...fresh.map((n) => _NoticeTile(n, _records[n.recordId]))],
                      if (earlier.isNotEmpty) ...[const SectionTitle('Earlier'), ...earlier.map((n) => _NoticeTile(n, _records[n.recordId]))],
                    ],
                  ),
      ),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile(this.n, this.record);
  final Notice n;
  final CrmRecord? record;

  String get _detail {
    final r = record;
    if (r == null) return n.detail;
    if (n.message.endsWith(' captured')) return [r.name, if (r.campaign.isNotEmpty) r.campaign].join(' · ');
    if (n.message.contains(': ')) return '${n.detail} — ${r.name}';
    return r.name;
  }

  (IconData, Color) get _look {
    final m = n.message;
    if (m.endsWith(' captured')) return (Icons.language_rounded, Brand.orange);
    if (m.contains('overdue')) return (Icons.alarm_rounded, Brand.red);
    if (m.contains('follow-up')) return (Icons.event_rounded, Brand.amber);
    if (m.contains('reassigned') || m.endsWith(' created')) return (Icons.person_add_alt_1_rounded, Brand.blue);
    if (m.contains('stage')) return (Icons.swap_horiz_rounded, Brand.accent);
    return (Icons.notifications_rounded, Brand.accent);
  }

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _look;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        onTap: n.kind == null
            ? null
            : () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordDetailScreen(kind: n.kind!, id: n.recordId))),
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                if (!n.read)
                  Container(width: 9, height: 9, decoration: const BoxDecoration(color: Brand.orange, shape: BoxShape.circle)),
              ]),
              const SizedBox(height: 3),
              Text(_detail, style: const TextStyle(color: Brand.muted, height: 1.35)),
              const SizedBox(height: 5),
              Text(timeAgo(n.createdAt), style: const TextStyle(color: Brand.grey, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    );
  }
}
