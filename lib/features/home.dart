import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/push.dart';
import '../core/session.dart';
import '../ui/brand_logo.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'record_detail.dart';
import 'records.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenTab});
  final ValueChanged<int> onOpenTab;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Paint the last dashboard instantly, then refresh it.
    final cached = AppScope.read(context).recall('dashboard');
    if (cached is Map) {
      _data = Map<String, dynamic>.from(cached);
      _loading = false;
    }
    reload(quiet: _data != null);
  }

  Future<void> reload({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = _data == null;
        _error = null;
      });
    }
    try {
      final app = AppScope.read(context);
      final data = Map<String, dynamic>.from(await app.api.get('/dashboard') as Map);
      app.remember('dashboard', data);
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted && (!quiet || _data == null)) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _int(String key) => (_data?[key] as num?)?.toInt() ?? 0;

  List<Map<String, dynamic>> _list(dynamic v) =>
      (v is List ? v : const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final employee = _data?['employee'] == true;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: darkBars,
      child: Scaffold(
        body: RefreshIndicator(
          color: Brand.accent,
          onRefresh: () async {
            HapticFeedback.lightImpact();
            await Future.wait([reload(quiet: true), app.refreshUnread()]);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _Hero(data: _data, loading: _loading)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                sliver: SliverList.list(children: [
                  const _AlertsCard(),
                  if (_error != null && _data == null)
                    ErrorState(_error!, onRetry: reload)
                  else if (_data == null)
                    const SizedBox(height: 360, child: SkeletonList(count: 4, padding: EdgeInsets.zero))
                  else if (employee)
                    ..._employee()
                  else
                    ..._manager(app),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _employee() {
    final tasks = _list((_data?['tasks'] as Map?)?['list']);
    return [
      const SectionTitle("Today's tasks"),
      if (tasks.isEmpty)
        const Panel(child: EmptyState(icon: Icons.wb_sunny_rounded, title: 'Nothing due today', message: 'Enjoy the calm.'))
      else
        ...tasks.map((t) => _tile(CrmRecord(t), RecordKind.tasks)),
    ];
  }

  List<Widget> _manager(AppState app) {
    final leadStages = _list(_data?['leadStages']);
    final recent = _list(_data?['recent']);
    final overdue = _list((_data?['overdue'] as Map?)?['list']);
    final performance = _list(_data?['performance']);
    final maxStage = leadStages.fold<int>(1, (m, s) => (s['count'] as num).toInt() > m ? (s['count'] as num).toInt() : m);
    return [
      GridView.count(
        crossAxisCount: 2,
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.45,
        children: [
          _Metric('Total leads', '${_int('leads')}', Icons.person_search_rounded, Brand.accent, () => widget.onOpenTab(1)),
          _Metric('Active deals', '${_int('activeDeals')}', Icons.handshake_rounded, Brand.blue, () => widget.onOpenTab(2)),
          _Metric('Open tasks', '${_int('tasks')}', Icons.task_alt_rounded, Brand.amber, () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const RecordListScreen(kind: RecordKind.tasks)));
          }),
          _Metric('All deals', '${_int('deals')}', Icons.stacked_bar_chart_rounded, Brand.orange, () => widget.onOpenTab(2)),
        ],
      ),
      const SizedBox(height: 18),
      SectionTitle('New enquiries', action: 'See all', onAction: () => widget.onOpenTab(1)),
      if (recent.isEmpty)
        const Panel(child: EmptyState(icon: Icons.inbox_rounded, title: 'No leads yet', message: 'New website enquiries will appear here instantly.'))
      else
        ...recent.map((r) => _tile(CrmRecord(r), RecordKind.leads)),
      if (leadStages.isNotEmpty) ...[
        const SizedBox(height: 18),
        const SectionTitle('Lead pipeline'),
        Panel(
          child: Column(
            children: [
              for (final s in leadStages)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: _StageBar(
                    label: s['status'].toString(),
                    count: (s['count'] as num).toInt(),
                    max: maxStage,
                  ),
                ),
            ],
          ),
        ),
      ],
      if (overdue.isNotEmpty) ...[
        const SizedBox(height: 18),
        SectionTitle('Overdue tasks · ${(_data?['overdue'] as Map?)?['total'] ?? overdue.length}'),
        ...overdue.map((t) => _tile(CrmRecord(t), RecordKind.tasks)),
      ],
      if (performance.isNotEmpty) ...[
        const SizedBox(height: 18),
        const SectionTitle('Team'),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            for (final p in performance)
              ListTile(
                leading: Avatar(p['name'].toString(), size: 38),
                title: Text(p['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: Text('${p['leads']} leads · ${p['won']} won',
                    style: const TextStyle(color: Brand.muted, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
          ]),
        ),
      ],
    ];
  }

  Widget _tile(CrmRecord r, RecordKind kind) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: RecordTile(
          record: r,
          kind: kind,
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => RecordDetailScreen(kind: kind, id: r.id)));
            reload(quiet: true);
          },
        ),
      );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.data, required this.loading});
  final Map<String, dynamic>? data;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final stages = (data?['leadStages'] as List?)?.cast<Map>() ?? const [];
    final fresh = stages.isEmpty ? 0 : (stages.first['count'] as num).toInt();
    final overdue = ((data?['overdue'] as Map?)?['total'] as num?)?.toInt() ?? 0;
    final headline = data == null
        ? 'Loading your workspace…'
        : data!['employee'] == true
            ? 'Here is your day.'
            : fresh > 0
                ? '$fresh ${fresh == 1 ? 'lead is' : 'leads are'} waiting for you.'
                : 'You are all caught up.';
    return Container(
      decoration: const BoxDecoration(
        gradient: Brand.heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const AqMark(size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${greeting()}, ${app.user?.firstName ?? ''}',
                  style: const TextStyle(color: Color(0xFFD8D0C2), fontWeight: FontWeight.w500, fontSize: 15),
                ),
              ),
              const NotificationBell(light: true),
            ]),
            const SizedBox(height: 8),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                headline,
                style: display(30, color: const Color(0xFFF6F1E8)),
              ),
            ),
            if (data != null && data!['employee'] != true) ...[
              const SizedBox(height: 20),
              Row(children: [
                _HeroStat(label: stages.isEmpty ? 'New' : stages.first['status'].toString(), value: '$fresh'),
                _HeroStat(label: 'Overdue tasks', value: '$overdue', warn: overdue > 0),
                _HeroStat(label: 'Conversion', value: '${(data!['conversion'] as num?)?.toInt() ?? 0}%'),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value, this.warn = false});
  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: .1)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: TextStyle(
                    color: warn ? const Color(0xFFFF8A5C) : Brand.glow, fontSize: 22, fontWeight: FontWeight.w600, fontFeatures: tabular)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 11.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon, this.color, this.onTap);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Panel(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: color, size: 19),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -.6, fontFeatures: tabular)),
            Text(label, style: const TextStyle(color: Brand.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
        ]),
      );
}

class _StageBar extends StatelessWidget {
  const _StageBar({required this.label, required this.count, required this.max});
  final String label;
  final int count;
  final int max;

  @override
  Widget build(BuildContext context) {
    final color = Brand.stage(label);
    return Row(children: [
      SizedBox(
        width: 104,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: max == 0 ? 0 : count / max),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 9,
              backgroundColor: Brand.surface,
              color: color,
            ),
          ),
        ),
      ),
      SizedBox(
        width: 36,
        child: Text('$count', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    ]);
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PushStatus>(
        valueListenable: PushCenter.instance.status,
        builder: (context, status, _) {
          if (status == PushStatus.on || status == PushStatus.unknown) return const SizedBox.shrink();
          final app = AppScope.read(context);
          final (title, body, action) = switch (status) {
            PushStatus.denied => (
                'Notifications are blocked',
                'Allow notifications for Acquiretech CRM so new website enquiries reach you instantly.',
                'Open settings'
              ),
            PushStatus.serverPending => (
                'Alerts are ready on this phone',
                'The workspace server update that delivers phone alerts is still pending.',
                'Check again'
              ),
            PushStatus.error => ('Could not turn on alerts', 'Check your connection and try again.', 'Try again'),
            _ => ('Get instant enquiry alerts', 'Know the second someone fills a form on your website.', 'Turn on'),
          };
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Brand.accentSoft,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Brand.glow),
              ),
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Brand.accent, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.notifications_active_rounded, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(body, style: const TextStyle(color: Brand.muted, fontSize: 12.5, height: 1.35)),
                    const SizedBox(height: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 18)),
                      onPressed: () async {
                        HapticFeedback.mediumImpact();
                        if (status == PushStatus.denied) {
                          await PushCenter.instance.openSystemSettings();
                        } else {
                          await PushCenter.instance.enable(app.api);
                        }
                      },
                      child: Text(action),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        },
      );
}
