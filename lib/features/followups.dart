import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'record_detail.dart';

class FollowupsScreen extends StatelessWidget {
  const FollowupsScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Follow-ups'),
            actions: const [NotificationBell(), SizedBox(width: 6)],
            bottom: const TabBar(
              labelColor: Brand.ink,
              unselectedLabelColor: Brand.muted,
              indicatorColor: Brand.accent,
              indicatorWeight: 3,
              dividerColor: Brand.border,
              labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              tabs: [Tab(text: 'Today'), Tab(text: 'Overdue'), Tab(text: 'Upcoming'), Tab(text: 'Done')],
            ),
          ),
          body: const TabBarView(children: [
            _FollowupList('today'),
            _FollowupList('overdue'),
            _FollowupList('upcoming'),
            _FollowupList('completed'),
          ]),
        ),
      );
}

class _FollowupList extends StatefulWidget {
  const _FollowupList(this.filter);
  final String filter;

  @override
  State<_FollowupList> createState() => _FollowupListState();
}

class _FollowupListState extends State<_FollowupList> with AutomaticKeepAliveClientMixin {
  List<Engagement>? _items;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  late final ValueNotifier<int> _refresh = AppScope.read(context).refresh;

  @override
  void initState() {
    super.initState();
    _refresh.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _refresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = Map<String, dynamic>.from(
          await AppScope.read(context).api.get('/followups', query: {'filter': widget.filter, 'page': '1'}) as Map);
      final list = (data['list'] as List).map((e) => Engagement(Map<String, dynamic>.from(e as Map))).toList();
      if (widget.filter == 'completed') list.sort((a, b) => (b.dueAt ?? DateTime(0)).compareTo(a.dueAt ?? DateTime(0)));
      if (mounted) {
        setState(() {
          _items = list;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _complete(Engagement e) async {
    final kind = e.kind;
    if (kind == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _items = _items?.where((x) => x.id != e.id).toList());
    try {
      await AppScope.read(context).api.patch('/records/${kind.name}/${e.recordId}/activities/${e.id}', {'status': 'Completed'});
      if (mounted) showMessage(context, 'Nice — “${e.title}” is done');
    } on ApiException catch (err) {
      if (mounted) showMessage(context, err.message, error: true);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = _items;
    return RefreshIndicator(
      color: Brand.accent,
      onRefresh: _load,
      child: items == null
          ? (_error != null
              ? ListView(children: [ErrorState(_error!, onRetry: _load)])
              : const SkeletonList(count: 5))
          : items.isEmpty
              ? ListView(children: [
                  EmptyState(
                    icon: widget.filter == 'overdue' ? Icons.verified_rounded : Icons.event_available_rounded,
                    title: switch (widget.filter) {
                      'today' => 'Nothing due today',
                      'overdue' => 'Nothing overdue',
                      'upcoming' => 'No upcoming follow-ups',
                      _ => 'No completed follow-ups yet',
                    },
                    message: widget.filter == 'overdue'
                        ? 'You are on top of every conversation.'
                        : 'Schedule one from any lead with “Follow-up”.',
                  ),
                ])
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _FollowupTile(
                    e: items[i],
                    onDone: () => _complete(items[i]),
                    onOpen: () async {
                      final kind = items[i].kind;
                      if (kind == null) return;
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => RecordDetailScreen(kind: kind, id: items[i].recordId)),
                      );
                      _load();
                    },
                  ),
                ),
    );
  }
}

class _FollowupTile extends StatelessWidget {
  const _FollowupTile({required this.e, required this.onDone, required this.onOpen});
  final Engagement e;
  final VoidCallback onDone;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final overdue = e.isOverdue;
    final color = !e.isScheduled ? Brand.accent : overdue ? Brand.red : Brand.amber;
    return Panel(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(8, 12, 14, 12),
      child: Row(children: [
        IconButton(
          tooltip: e.isScheduled ? 'Mark done' : 'Done',
          onPressed: e.isScheduled ? onDone : null,
          icon: Icon(
            e.isScheduled ? Icons.radio_button_unchecked_rounded : Icons.check_circle_rounded,
            color: e.isScheduled ? color : Brand.accent,
            size: 28,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  decoration: e.isScheduled ? null : TextDecoration.lineThrough,
                  color: e.isScheduled ? Brand.text : Brand.muted,
                )),
            const SizedBox(height: 3),
            Row(children: [
              Icon(e.kind?.icon ?? Icons.person_rounded, size: 15, color: Brand.muted),
              const SizedBox(width: 5),
              Expanded(
                child: Text(e.recordName.isEmpty ? (e.kind?.singular ?? '') : e.recordName,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Brand.muted, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ]),
            const SizedBox(height: 7),
            Pill(overdue ? 'Overdue · ${dueLabel(e.dueAt)}' : dueLabel(e.dueAt), icon: Icons.schedule_rounded, color: color),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: Brand.grey),
      ]),
    );
  }
}
