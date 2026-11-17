import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'record_form.dart';

class RecordDetailScreen extends StatefulWidget {
  const RecordDetailScreen({super.key, required this.kind, required this.id, this.initial, this.onChanged});
  final RecordKind kind;
  final String id;
  final CrmRecord? initial;
  final ValueChanged<CrmRecord>? onChanged;

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  CrmRecord? _record;
  List<Engagement> _entries = [];
  List<CrmEvent> _events = [];
  String? _error;
  bool _loading = true;

  RecordKind get kind => widget.kind;
  String get _base => '/records/${kind.name}/${widget.id}';

  @override
  void initState() {
    super.initState();
    _record = widget.initial;
    _load();
  }

  Future<void> _load() async {
    final api = AppScope.read(context).api;
    setState(() => _error = null);
    try {
      final results = await Future.wait([api.get(_base), api.get('$_base/timeline').catchError((_) => null)]);
      if (!mounted) return;
      final timeline = results[1] is Map ? Map<String, dynamic>.from(results[1] as Map) : const <String, dynamic>{};
      setState(() {
        _record = CrmRecord(Map<String, dynamic>.from(results[0] as Map));
        _entries = ((timeline['entries'] as List?) ?? const []).map((e) => Engagement(Map<String, dynamic>.from(e as Map))).toList();
        _events = ((timeline['events'] as List?) ?? const []).map((e) => CrmEvent(Map<String, dynamic>.from(e as Map))).toList();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _updated(CrmRecord r) {
    setState(() => _record = r);
    widget.onChanged?.call(r);
  }

  Future<void> _changeStatus() async {
    final app = AppScope.read(context);
    final r = _record!;
    final stages = app.workflow
        .stagesFor(kind)
        .where((s) => !(kind == RecordKind.leads && s == 'Converted' && r.status != 'Converted'))
        .toList();
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Move to stage', style: display(22)),
          ),
          for (final s in stages)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: Brand.stage(s), shape: BoxShape.circle)),
              title: Text(s, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: s == r.status ? const Icon(Icons.check_circle_rounded, color: Brand.accent) : null,
              onTap: () => Navigator.pop(c, s),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked == null || picked == r.status || !mounted) return;
    try {
      final data = await app.api.patch(_base, {'status': picked});
      HapticFeedback.mediumImpact();
      _updated(CrmRecord(Map<String, dynamic>.from(data as Map)));
      if (mounted) showMessage(context, 'Moved to $picked');
      _load();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _convert() async {
    final ok = await confirm(
      context,
      title: 'Convert this lead?',
      message: 'This creates a contact, a company (if one is named) and a deal, all linked to this lead.',
      action: 'Convert',
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).api.post('/leads/${widget.id}/convert');
      HapticFeedback.heavyImpact();
      if (mounted) showMessage(context, 'Lead converted — the new deal is in Deals.');
      await _load();
      if (_record != null) widget.onChanged?.call(_record!);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _launch(Uri uri, {String? logType}) async {
    HapticFeedback.selectionClick();
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!ok) {
      showMessage(context, 'No app on this phone can open that.', error: true);
      return;
    }
    if (logType != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Log this ${logType.toLowerCase()} on the timeline?'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(label: 'Log', textColor: Brand.glow, onPressed: () => _addActivity(type: logType)),
      ));
    }
  }

  Future<void> _addActivity({String type = 'Note'}) async {
    final created = await showActivitySheet(context, kind: kind, recordId: widget.id, recordName: _record?.name ?? '', type: type);
    if (created && mounted) {
      HapticFeedback.mediumImpact();
      showMessage(context, type == 'Follow-up' ? 'Follow-up scheduled' : 'Added to the timeline');
      _load();
    }
  }

  Future<void> _completeFollowUp(Engagement e) async {
    try {
      await AppScope.read(context).api.patch('$_base/activities/${e.id}', {'status': 'Completed'});
      HapticFeedback.mediumImpact();
      if (mounted) showMessage(context, 'Follow-up done');
      _load();
    } on ApiException catch (err) {
      if (mounted) showMessage(context, err.message, error: true);
    }
  }

  Future<void> _edit() async {
    final updated = await Navigator.push<CrmRecord>(
      context,
      MaterialPageRoute(builder: (_) => RecordFormScreen(kind: kind, record: _record)),
    );
    if (updated != null) {
      _updated(updated);
      _load();
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete ${_record!.name}?',
      message: 'This removes the ${kind.singular.toLowerCase()} from the CRM. It cannot be undone.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.read(context).api.delete(_base);
      if (mounted) {
        showMessage(context, '${kind.singular} deleted');
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final r = _record;
    return Scaffold(
      appBar: AppBar(
        title: Text(kind.singular),
        actions: [
          if (r != null) IconButton(tooltip: 'Edit', onPressed: _edit, icon: const Icon(Icons.edit_rounded)),
          if (r != null && (app.user?.isAdmin ?? false))
            PopupMenuButton<String>(
              onSelected: (v) => v == 'delete' ? _delete() : null,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Brand.red, fontWeight: FontWeight.w700))),
              ],
            ),
        ],
      ),
      floatingActionButton: r == null
          ? null
          : FloatingActionButton.extended(
              heroTag: 'activity',
              onPressed: () => _addActivity(),
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text('Log activity', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
      body: r == null
          ? (_error != null ? ErrorState(_error!, onRetry: _load) : const SkeletonList(count: 4))
          : RefreshIndicator(
              color: Brand.accent,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                children: [
                  _header(app, r),
                  const SizedBox(height: 12),
                  _actions(r),
                  if (kind == RecordKind.leads && !app.workflow.isTerminal(kind, r.status)) ...[
                    const SizedBox(height: 12),
                    _convertCard(),
                  ],
                  const SizedBox(height: 18),
                  ..._details(app, r),
                  const SizedBox(height: 8),
                  SectionTitle('Timeline${_loading ? '' : ' · ${_entries.length + _events.length}'}'),
                  ..._timeline(app),
                ],
              ),
            ),
    );
  }

  Widget _header(AppState app, CrmRecord r) {
    final subtitle = [if (r.company.isNotEmpty && kind != RecordKind.companies) r.company, if (r.email.isNotEmpty) r.email].join(' · ');
    final canChange = kind.hasStages && !(kind == RecordKind.leads && r.status == 'Converted');
    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Avatar(r.name, size: 60, icon: kind == RecordKind.companies ? Icons.apartment_rounded : null),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText(r.name, style: display(24)),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Brand.muted, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (kind.hasStages) StatusChip(r.status, large: true, onTap: canChange ? _changeStatus : null),
          if (r.fromWebsite) const Pill('Website enquiry', icon: Icons.language_rounded, color: Brand.orange),
          if (kind == RecordKind.deals && r.amount != null) Pill(money(r.amount, app.currency), color: Brand.accent),
        ]),
        const SizedBox(height: 14),
        const Divider(),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.person_outline_rounded, size: 17, color: Brand.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Owner: ${app.personName(r.ownerId)}${r.createdAt != null ? '  ·  Added ${timeAgo(r.createdAt)}' : ''}',
              style: const TextStyle(color: Brand.muted, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _actions(CrmRecord r) {
    final digits = r.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final whatsapp = digits.length == 10 ? '91$digits' : digits;
    return Row(children: [
      _QuickAction(Icons.call_rounded, 'Call', r.phone.isEmpty ? null : () => _launch(Uri(scheme: 'tel', path: r.phone), logType: 'Call')),
      _QuickAction(Icons.chat_rounded, 'WhatsApp',
          digits.length < 8 ? null : () => _launch(Uri.parse('https://wa.me/$whatsapp'), logType: 'WhatsApp')),
      _QuickAction(Icons.mail_rounded, 'Email', r.email.isEmpty ? null : () => _launch(Uri(scheme: 'mailto', path: r.email), logType: 'Email')),
      _QuickAction(Icons.event_rounded, 'Follow-up', () => _addActivity(type: 'Follow-up')),
    ]);
  }

  Widget _convertCard() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Brand.ink, Color(0xFF3A2A20)]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: Brand.glow),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Qualified? Turn this lead into a contact and a deal.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, height: 1.35)),
          ),
          TextButton(
            onPressed: _convert,
            style: TextButton.styleFrom(foregroundColor: Brand.glow),
            child: const Text('Convert'),
          ),
        ]),
      );

  List<Widget> _details(AppState app, CrmRecord r) {
    final rows = <Widget>[
      if (r.phone.isNotEmpty) _InfoRow(Icons.call_outlined, 'Phone', r.phone),
      if (r.email.isNotEmpty) _InfoRow(Icons.mail_outline_rounded, 'Email', r.email),
      if (r.company.isNotEmpty && kind != RecordKind.companies) _InfoRow(Icons.apartment_rounded, 'Company', r.company),
      if (r.source.isNotEmpty) _InfoRow(Icons.call_split_rounded, 'Source', r.source),
      if (r.campaign.isNotEmpty) _InfoRow(Icons.campaign_outlined, kind == RecordKind.leads ? 'Service' : 'Campaign', r.campaign),
      if (r.amount != null) _InfoRow(Icons.payments_outlined, 'Amount', money(r.amount, app.currency)),
      if (r.probability != null) _InfoRow(Icons.percent_rounded, 'Probability', '${r.probability!.round()}%'),
      if (r.closeDate.isNotEmpty) _InfoRow(Icons.flag_outlined, 'Close date', dateOnly(r.closeDate)),
      if (r.dueDate.isNotEmpty) _InfoRow(Icons.event_outlined, 'Due date', dateOnly(r.dueDate)),
      if (r.priority.isNotEmpty) _InfoRow(Icons.priority_high_rounded, 'Priority', r.priority),
      if (r.tags.isNotEmpty) _InfoRow(Icons.sell_outlined, 'Tags', r.tags.join(', ')),
    ];
    final custom = Map<String, String>.from(r.customFields)..remove('submissionId');
    final ordered = [
      ...briefLabels.keys.where(custom.containsKey),
      ...custom.keys.where((k) => !briefLabels.containsKey(k) && k != 'budgetCurrency'),
    ];
    String value(String k) =>
        k == 'budget' && (custom['budgetCurrency'] ?? '').isNotEmpty ? '${custom['budgetCurrency']} ${custom[k]}' : custom[k]!;
    return [
      if (rows.isNotEmpty) ...[
        const SectionTitle('Details'),
        Panel(padding: const EdgeInsets.symmetric(vertical: 6), child: Column(children: rows)),
        const SizedBox(height: 18),
      ],
      if (ordered.isNotEmpty) ...[
        SectionTitle(r.fromWebsite ? 'Website brief' : 'More details'),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [for (final k in ordered) _InfoRow(null, briefLabel(k), value(k))]),
        ),
        const SizedBox(height: 18),
      ],
      if (r.notes.trim().isNotEmpty) ...[
        SectionTitle(r.fromWebsite ? 'Enquiry message' : 'Notes'),
        Panel(child: _ExpandableText(r.notes.trim())),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<Widget> _timeline(AppState app) {
    if (_loading && _entries.isEmpty && _events.isEmpty) {
      return const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))];
    }
    final items = <(DateTime, Widget)>[
      for (final e in _entries) (e.createdAt ?? DateTime(2000), _EntryTile(e, app: app, onDone: () => _completeFollowUp(e))),
      for (final e in _events) (e.createdAt ?? DateTime(2000), _EventTile(e, app: app)),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    if (items.isEmpty) {
      return const [
        Panel(
          child: EmptyState(
            icon: Icons.timeline_rounded,
            title: 'No activity yet',
            message: 'Calls, notes and follow-ups you log will appear here.',
          ),
        ),
      ];
    }
    return [for (final i in items) i.$2];
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: enabled ? Colors.white : Brand.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Brand.border)),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Column(children: [
                Icon(icon, color: enabled ? Brand.accent : Brand.grey.withValues(alpha: .5), size: 23),
                const SizedBox(height: 5),
                Text(label,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: enabled ? Brand.text : Brand.grey.withValues(alpha: .7))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value);
  final IconData? icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => InkWell(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: value));
          HapticFeedback.selectionClick();
          showMessage(context, '$label copied');
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (icon != null) ...[Icon(icon, size: 19, color: Brand.muted), const SizedBox(width: 12)],
            SizedBox(
              width: 110,
              child: Text(label, style: const TextStyle(color: Brand.muted, fontWeight: FontWeight.w600, fontSize: 13.5)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.35))),
          ]),
        ),
      );
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText(this.text);
  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final long = widget.text.length > 420 || '\n'.allMatches(widget.text).length > 8;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        alignment: Alignment.topCenter,
        child: SelectableText(
          widget.text,
          maxLines: long && !_open ? 8 : null,
          style: const TextStyle(height: 1.5, fontSize: 14.5),
        ),
      ),
      if (long)
        TextButton(
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          onPressed: () => setState(() => _open = !_open),
          child: Text(_open ? 'Show less' : 'Read full message'),
        ),
    ]);
  }
}

IconData _entryIcon(String type) => switch (type) {
      'Call' => Icons.call_rounded,
      'Email' => Icons.mail_rounded,
      'Meeting' => Icons.groups_rounded,
      'WhatsApp' => Icons.chat_rounded,
      'Follow-up' => Icons.event_rounded,
      'Document' => Icons.description_rounded,
      _ => Icons.sticky_note_2_rounded,
    };

class _EntryTile extends StatelessWidget {
  const _EntryTile(this.e, {required this.app, required this.onDone});
  final Engagement e;
  final AppState app;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final color = e.isFollowUp ? (e.isOverdue ? Brand.red : Brand.amber) : Brand.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
            child: Icon(_entryIcon(e.type), size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5))),
                Text(timeAgo(e.createdAt), style: const TextStyle(color: Brand.grey, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
              if (e.body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(e.body, maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Brand.muted, height: 1.4)),
              ],
              if (e.isFollowUp) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Pill(
                    e.isScheduled ? (e.isOverdue ? 'Overdue · ${dueLabel(e.dueAt)}' : dueLabel(e.dueAt)) : e.status,
                    icon: e.isScheduled ? Icons.schedule_rounded : Icons.check_rounded,
                    color: e.isScheduled ? color : Brand.accent,
                  ),
                  const Spacer(),
                  if (e.isScheduled)
                    TextButton.icon(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: onDone,
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                      label: const Text('Done'),
                    ),
                ]),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${e.type} · ${app.personName(e.actorId)}',
                      style: const TextStyle(color: Brand.grey, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile(this.e, {required this.app});
  final CrmEvent e;
  final AppState app;

  String get _text {
    final a = e.action;
    if (a == 'captured') return 'Received from the website form';
    if (a == 'created') return 'Created by ${app.personName(e.actorId)}';
    if (a == 'converted') return 'Converted to a deal';
    if (a.startsWith('stage changed: ')) return 'Stage: ${a.substring(15)}';
    if (a == 'reminder') return 'Reminder sent';
    if (a.startsWith('follow-up')) return '${a[0].toUpperCase()}${a.substring(1)}';
    return '${a[0].toUpperCase()}${a.substring(1)} by ${app.personName(e.actorId)}';
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 6, 12),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Brand.grey, shape: BoxShape.circle)),
          const SizedBox(width: 14),
          Expanded(child: Text(_text, style: const TextStyle(color: Brand.muted, fontWeight: FontWeight.w600, fontSize: 13))),
          Text(timeAgo(e.createdAt), style: const TextStyle(color: Brand.grey, fontSize: 12)),
        ]),
      );
}

/// Bottom sheet to log a note, call, message or schedule a follow-up.
Future<bool> showActivitySheet(
  BuildContext context, {
  required RecordKind kind,
  required String recordId,
  required String recordName,
  String type = 'Note',
}) async {
  final created = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ActivitySheet(kind: kind, recordId: recordId, recordName: recordName, type: type),
  );
  return created ?? false;
}

class _ActivitySheet extends StatefulWidget {
  const _ActivitySheet({required this.kind, required this.recordId, required this.recordName, required this.type});
  final RecordKind kind;
  final String recordId;
  final String recordName;
  final String type;

  @override
  State<_ActivitySheet> createState() => _ActivitySheetState();
}

class _ActivitySheetState extends State<_ActivitySheet> {
  static const types = ['Note', 'Call', 'WhatsApp', 'Email', 'Meeting', 'Follow-up'];
  late String _type = widget.type;
  final _title = TextEditingController();
  final _body = TextEditingController();
  late DateTime _due = () {
    final t = DateTime.now().add(const Duration(days: 1));
    return DateTime(t.year, t.month, t.day, 10);
  }();
  int _reminder = 15;
  bool _busy = false;
  String? _error;
  bool _titleEdited = false;

  @override
  void initState() {
    super.initState();
    _title.text = _defaultTitle(_type);
  }

  String _defaultTitle(String type) {
    final first = widget.recordName.split(' ').first;
    return switch (type) {
      'Call' => 'Called $first',
      'WhatsApp' => 'WhatsApp with $first',
      'Email' => 'Emailed $first',
      'Meeting' => 'Meeting with $first',
      'Follow-up' => 'Follow up with $first',
      _ => 'Note',
    };
  }

  Future<void> _pickDue() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_due));
    if (!mounted) return;
    setState(() => _due = DateTime(date.year, date.month, date.day, time?.hour ?? _due.hour, time?.minute ?? _due.minute));
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Add a short title.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final followUp = _type == 'Follow-up';
    try {
      await AppScope.read(context).api.post('/records/${widget.kind.name}/${widget.recordId}/activities', {
        'type': _type,
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        if (followUp) 'dueAt': _due.toUtc().toIso8601String(),
        if (followUp) 'reminderMinutes': _reminder,
        'status': followUp ? 'Scheduled' : 'Completed',
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final followUp = _type == 'Follow-up';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(followUp ? 'Schedule a follow-up' : 'Log activity', style: display(22)),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in types)
                ChoiceChip(
                  label: Text(t),
                  avatar: Icon(_entryIcon(t), size: 16, color: t == _type ? Colors.white : Brand.accent),
                  selected: t == _type,
                  showCheckmark: false,
                  labelStyle: TextStyle(color: t == _type ? Colors.white : Brand.text, fontWeight: FontWeight.w700),
                  onSelected: (_) => setState(() {
                    _type = t;
                    if (!_titleEdited) _title.text = _defaultTitle(t);
                  }),
                ),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              onChanged: (_) => _titleEdited = true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: followUp ? 'What to discuss (optional)' : 'Details (optional)', alignLabelWithHint: true),
            ),
            if (followUp) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDue,
                    icon: const Icon(Icons.event_rounded, size: 19),
                    label: Text(dueLabel(_due)),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButtonHideUnderline(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(border: Border.all(color: Brand.border), borderRadius: BorderRadius.circular(16)),
                    child: DropdownButton<int>(
                      value: _reminder,
                      borderRadius: BorderRadius.circular(16),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('No reminder')),
                        DropdownMenuItem(value: 15, child: Text('15 min before')),
                        DropdownMenuItem(value: 60, child: Text('1 hour before')),
                        DropdownMenuItem(value: 1440, child: Text('1 day before')),
                      ],
                      onChanged: (v) => setState(() => _reminder = v ?? 15),
                    ),
                  ),
                ),
              ]),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Brand.red, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Text(followUp ? 'Schedule follow-up' : 'Save to timeline'),
            ),
          ]),
        ),
      ),
    );
  }
}
