import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'record_detail.dart';
import 'record_form.dart';

class RecordListScreen extends StatefulWidget {
  const RecordListScreen({super.key, required this.kind, this.showPipeline = false});
  final RecordKind kind;
  final bool showPipeline;

  @override
  State<RecordListScreen> createState() => _RecordListScreenState();
}

class _RecordListScreenState extends State<RecordListScreen> {
  final _items = <CrmRecord>[];
  final _scroll = ScrollController();
  final _searchController = TextEditingController();
  Timer? _debounce;
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _search = '';
  String? _status;
  int _generation = 0;
  Key _pipelineKey = UniqueKey();

  RecordKind get kind => widget.kind;
  late final ValueNotifier<int> _refresh = AppScope.read(context).refresh;

  @override
  void initState() {
    super.initState();
    _refresh.addListener(_load);
    // Show the last list instantly; the network refresh replaces it.
    final cached = AppScope.read(context).recall('list:${kind.name}');
    if (cached is Map && cached['list'] is List) {
      _items.addAll((cached['list'] as List).map((e) => CrmRecord(Map<String, dynamic>.from(e as Map))));
      _total = (cached['total'] as num?)?.toInt() ?? _items.length;
      _loading = false;
    }
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    _refresh.removeListener(_load);
    _scroll.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Map<String, String> _query(int page) => {
        'page': '$page',
        'limit': '20',
        'sort': 'createdAt',
        'direction': 'desc',
        if (_search.isNotEmpty) 'search': _search,
        'status': ?_status,
      };

  Future<PageResult<CrmRecord>> _fetch(int page) async {
    final app = AppScope.read(context);
    final data = Map<String, dynamic>.from(await app.api.get('/records/${kind.name}', query: _query(page)) as Map);
    if (page == 1 && _search.isEmpty && _status == null) app.remember('list:${kind.name}', data);
    final list = (data['list'] as List).map((e) => CrmRecord(Map<String, dynamic>.from(e as Map))).toList();
    return PageResult(list, (data['total'] as num?)?.toInt() ?? list.length);
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _pipelineKey = UniqueKey();
    });
    try {
      final result = await _fetch(1);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.list);
        _total = result.total;
        _page = 1;
      });
    } on ApiException catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e.message);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _items.length >= _total) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final result = await _fetch(_page + 1);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(result.list);
        _total = result.total;
        _page++;
      });
    } catch (_) {
      // The next scroll will try again.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), () {
      if (value.trim() == _search) return;
      _search = value.trim();
      _load();
    });
  }

  Future<void> _open(CrmRecord r) async {
    final deleted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RecordDetailScreen(
          kind: kind,
          id: r.id,
          initial: r,
          // Keep the list and its scroll position; just refresh the edited row.
          onChanged: (updated) {
            final i = _items.indexWhere((x) => x.id == updated.id);
            if (i >= 0 && mounted) setState(() => _items[i] = updated);
          },
        ),
      ),
    );
    if (deleted == true) _load();
  }

  Future<void> _create() async {
    HapticFeedback.lightImpact();
    final created = await Navigator.push<CrmRecord>(context, MaterialPageRoute(builder: (_) => RecordFormScreen(kind: kind)));
    if (created != null && mounted) {
      AppScope.read(context).dataChanged();
      Navigator.push(context, MaterialPageRoute(builder: (_) => RecordDetailScreen(kind: kind, id: created.id, initial: created)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final stages = app.workflow.stagesFor(kind);
    return Scaffold(
      appBar: AppBar(
        title: Text(kind.label),
        actions: const [NotificationBell(), SizedBox(width: 6)],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(stages.isEmpty ? 64 : 112),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: SizedBox(
                height: 48,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search ${kind.label.toLowerCase()}',
                    prefixIcon: const Icon(Icons.search_rounded),
                    contentPadding: EdgeInsets.zero,
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _searchController.clear();
                              _onSearch('');
                              setState(() {});
                            },
                          ),
                  ),
                ),
              ),
            ),
            if (stages.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  children: [
                    _FilterChip(label: 'All', selected: _status == null, onTap: () {
                      setState(() => _status = null);
                      _load();
                    }),
                    for (final s in stages)
                      _FilterChip(label: s, selected: _status == s, color: Brand.stage(s), onTap: () {
                        setState(() => _status = _status == s ? null : s);
                        _load();
                      }),
                  ],
                ),
              ),
          ]),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-${kind.name}',
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: Text('New ${kind.singular.toLowerCase()}', style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: Brand.accent,
        onRefresh: () async {
          HapticFeedback.lightImpact();
          await _load();
        },
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) return const SkeletonList();
    final header = <Widget>[
      if (widget.showPipeline) _PipelineSummary(key: _pipelineKey),
      if (_items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
          child: Text(
            '$_total ${_total == 1 ? kind.singular.toLowerCase() : kind.label.toLowerCase()}${_status != null ? ' · $_status' : ''}',
            style: const TextStyle(color: Brand.muted, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
    ];
    if (_error != null && _items.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [...header, ErrorState(_error!, onRetry: _load)]);
    }
    if (_items.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: [
        ...header,
        EmptyState(
          icon: kind.icon,
          title: _search.isNotEmpty || _status != null ? 'No matches' : 'No ${kind.label.toLowerCase()} yet',
          message: _search.isNotEmpty || _status != null
              ? 'Try a different search or filter.'
              : kind == RecordKind.leads
                  ? 'Website enquiries land here automatically.'
                  : 'Tap “New ${kind.singular.toLowerCase()}” to add the first one.',
        ),
      ]);
    }
    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: header.length + _items.length + 1,
      itemBuilder: (context, i) {
        if (i < header.length) return header[i];
        final index = i - header.length;
        if (index == _items.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : _items.length >= _total
                      ? const Text('You are all caught up', style: TextStyle(color: Brand.grey, fontWeight: FontWeight.w600))
                      : const SizedBox.shrink(),
            ),
          );
        }
        final r = _items[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: RecordTile(record: r, kind: kind, onTap: () => _open(r)),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.color});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          avatar: color == null || selected
              ? null
              : Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          labelStyle: TextStyle(color: selected ? Colors.white : Brand.text, fontWeight: FontWeight.w700, fontSize: 13),
          onSelected: (_) {
            HapticFeedback.selectionClick();
            onTap();
          },
        ),
      );
}

class RecordTile extends StatelessWidget {
  const RecordTile({super.key, required this.record, required this.kind, required this.onTap});
  final CrmRecord record;
  final RecordKind kind;
  final VoidCallback onTap;

  String _subtitle(AppState app) {
    switch (kind) {
      case RecordKind.deals:
        return [
          if (record.company.isNotEmpty) record.company,
          if (record.closeDate.isNotEmpty) 'Closes ${dateOnly(record.closeDate)}',
        ].join(' · ');
      case RecordKind.tasks:
        return [
          if (record.dueDate.isNotEmpty) 'Due ${dateOnly(record.dueDate)}',
          if (record.priority.isNotEmpty) record.priority,
        ].join(' · ');
      default:
        return [
          if (record.company.isNotEmpty) record.company,
          if (record.company.isEmpty && record.email.isNotEmpty) record.email,
          if (record.company.isEmpty && record.email.isEmpty && record.phone.isNotEmpty) record.phone,
        ].join(' · ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final subtitle = _subtitle(app);
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(children: [
        Avatar(record.name, icon: kind == RecordKind.companies ? Icons.apartment_rounded : kind == RecordKind.tasks ? Icons.task_alt_rounded : null),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(record.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, letterSpacing: -.2)),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Brand.muted, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 7),
            Row(children: [
              if (record.fromWebsite) ...[
                const Pill('Website', icon: Icons.language_rounded, color: Brand.orange),
                const SizedBox(width: 6),
              ],
              if (kind == RecordKind.deals && record.amount != null) ...[
                Pill(money(record.amount, app.currency), color: Brand.accent),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(timeAgo(record.createdAt), maxLines: 1,
                    style: const TextStyle(color: Brand.grey, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
          ]),
        ),
        if (kind.hasStages) ...[const SizedBox(width: 8), StatusChip(record.status)],
      ]),
    );
  }
}

class _PipelineSummary extends StatefulWidget {
  const _PipelineSummary({super.key});

  @override
  State<_PipelineSummary> createState() => _PipelineSummaryState();
}

class _PipelineSummaryState extends State<_PipelineSummary> {
  late final Future<dynamic> _report = AppScope.read(context).api.get('/reports');

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return FutureBuilder<dynamic>(
      future: _report,
      builder: (context, snap) {
        final data = snap.data is Map ? Map<String, dynamic>.from(snap.data as Map) : null;
        if (snap.hasError) return const SizedBox.shrink();
        Widget stat(String label, String key, Color color) => Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Brand.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    data == null ? '—' : money((data[key] as num?) ?? 0, app.currency, compact: true),
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: color, letterSpacing: -.4),
                  ),
                  const SizedBox(height: 2),
                  Text(label, style: const TextStyle(color: Brand.muted, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            );
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            stat('Open pipeline', 'pipelineValue', Brand.ink),
            stat('Weighted', 'weightedValue', Brand.blue),
            stat('Won', 'wonValue', Brand.accent),
          ]),
        );
      },
    );
  }
}
