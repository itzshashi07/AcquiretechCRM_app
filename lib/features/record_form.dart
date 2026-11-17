import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/theme.dart';

const _sources = ['Website', 'Referral', 'Organic Search', 'Social Media', 'Event', 'Outbound', 'Other'];
const _priorities = ['Low', 'Normal', 'High', 'Urgent'];

class RecordFormScreen extends StatefulWidget {
  const RecordFormScreen({super.key, required this.kind, this.record});
  final RecordKind kind;
  final CrmRecord? record;

  @override
  State<RecordFormScreen> createState() => _RecordFormScreenState();
}

class _RecordFormScreenState extends State<RecordFormScreen> {
  late final CrmRecord? r = widget.record;
  late final _name = TextEditingController(text: r?.name);
  late final _email = TextEditingController(text: r?.email);
  late final _phone = TextEditingController(text: r?.phone);
  late final _company = TextEditingController(text: r?.company);
  late final _campaign = TextEditingController(text: r?.campaign);
  late final _notes = TextEditingController(text: r?.notes);
  late final _amount = TextEditingController(text: r?.amount == null ? '' : NumberFormat('0.##').format(r!.amount));
  late final _probability = TextEditingController(text: r?.probability == null ? '' : r!.probability!.round().toString());
  late String? _source = (r?.source.isEmpty ?? true) ? null : r!.source;
  late String? _status = (r?.status.isEmpty ?? true) ? null : r!.status;
  late String? _priority = (r?.priority.isEmpty ?? true) ? null : r!.priority;
  late String _closeDate = r?.closeDate ?? '';
  late String _dueDate = r?.dueDate ?? '';
  bool _busy = false;
  String? _error;

  RecordKind get kind => widget.kind;
  bool get editing => r != null;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _company, _campaign, _notes, _amount, _probability]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _nameLabel => switch (kind) {
        RecordKind.companies => 'Company name',
        RecordKind.deals => 'Deal name',
        RecordKind.tasks => 'Task',
        _ => 'Full name',
      };

  Map<String, dynamic> _values() => {
        'name': _name.text.trim(),
        if (kind != RecordKind.tasks) 'email': _email.text.trim(),
        if (kind != RecordKind.tasks) 'phone': _phone.text.trim(),
        if (kind == RecordKind.leads || kind == RecordKind.contacts || kind == RecordKind.deals) 'company': _company.text.trim(),
        if (kind == RecordKind.leads || kind == RecordKind.deals) 'source': _source,
        if (kind == RecordKind.leads) 'campaign': _campaign.text.trim(),
        if (kind.hasStages) 'status': _status,
        if (kind == RecordKind.deals) 'amount': double.tryParse(_amount.text.replaceAll(',', '').trim()),
        if (kind == RecordKind.deals) 'probability': double.tryParse(_probability.text.trim()),
        if (kind == RecordKind.deals) 'closeDate': _closeDate,
        if (kind == RecordKind.tasks) 'dueDate': _dueDate,
        if (kind == RecordKind.tasks) 'priority': _priority,
        'notes': _notes.text.trim(),
      };

  Future<void> _save() async {
    final values = _values();
    if ((values['name'] as String).isEmpty) {
      setState(() => _error = 'Add a ${_nameLabel.toLowerCase()}.');
      return;
    }
    final email = values['email'] as String? ?? '';
    if (email.isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _error = 'That email address does not look right.');
      return;
    }
    final p = values['probability'] as double?;
    if (p != null && (p < 0 || p > 100)) {
      setState(() => _error = 'Probability must be between 0 and 100.');
      return;
    }
    final Map<String, dynamic> body;
    if (editing) {
      // Send only what changed so concurrent edits elsewhere are not overwritten.
      body = {};
      values.forEach((k, v) {
        final before = r!.json[k];
        final same = (before == null && (v == null || v == '')) || before == v || (before is num && v is num && before == v);
        if (!same && !(v == null && before == null)) body[k] = v ?? '';
      });
      body.removeWhere((k, v) => v == '' && (k == 'amount' || k == 'probability' || k == 'source' || k == 'status' || k == 'priority'));
      if (body.isEmpty) {
        Navigator.pop(context);
        return;
      }
    } else {
      body = {
        for (final e in values.entries)
          if (e.value != null && e.value != '') e.key: e.value,
      };
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = AppScope.read(context).api;
      final data = editing ? await api.patch('/records/${kind.name}/${r!.id}', body) : await api.post('/records/${kind.name}', body);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, CrmRecord(Map<String, dynamic>.from(data as Map)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate(String current, ValueChanged<String> set) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(current) ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => set(DateFormat('yyyy-MM-dd').format(picked)));
  }

  Widget _field(TextEditingController c, String label, IconData icon,
          {TextInputType? type, int lines = 1, TextCapitalization caps = TextCapitalization.none}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: type,
          minLines: lines,
          maxLines: lines == 1 ? 1 : 8,
          textCapitalization: caps,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), alignLabelWithHint: lines > 1),
        ),
      );

  Widget _dropdown(String label, IconData icon, String? value, List<String> options, ValueChanged<String?> onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: options.contains(value) ? value : null,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
          borderRadius: BorderRadius.circular(16),
          items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
          onChanged: onChanged,
        ),
      );

  Widget _date(String label, String value, ValueChanged<String> set) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _pickDate(value, set),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.event_rounded),
              suffixIcon: value.isEmpty
                  ? null
                  : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => set(''))),
            ),
            child: Text(value.isEmpty ? 'Choose a date' : dateOnly(value),
                style: TextStyle(color: value.isEmpty ? Brand.grey : Brand.text, fontWeight: FontWeight.w600)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final stages = app.workflow
        .stagesFor(kind)
        .where((s) => !(kind == RecordKind.leads && s == 'Converted' && _status != 'Converted'))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit ${kind.singular.toLowerCase()}' : 'New ${kind.singular.toLowerCase()}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _field(_name, _nameLabel, kind == RecordKind.companies ? Icons.apartment_rounded : Icons.badge_outlined,
              caps: TextCapitalization.words),
          if (kind != RecordKind.tasks) ...[
            _field(_phone, 'Phone', Icons.call_outlined, type: TextInputType.phone),
            _field(_email, 'Email', Icons.alternate_email_rounded, type: TextInputType.emailAddress),
          ],
          if (kind == RecordKind.leads || kind == RecordKind.contacts || kind == RecordKind.deals)
            _field(_company, 'Company', Icons.apartment_rounded, caps: TextCapitalization.words),
          if (kind == RecordKind.deals) ...[
            Row(children: [
              Expanded(child: _field(_amount, 'Amount (${app.currency})', Icons.payments_outlined, type: const TextInputType.numberWithOptions(decimal: true))),
              const SizedBox(width: 10),
              SizedBox(width: 130, child: _field(_probability, 'Win %', Icons.percent_rounded, type: TextInputType.number)),
            ]),
            _date('Expected close', _closeDate, (v) => _closeDate = v),
          ],
          if (kind == RecordKind.tasks) ...[
            _date('Due date', _dueDate, (v) => _dueDate = v),
            _dropdown('Priority', Icons.flag_outlined, _priority, _priorities, (v) => setState(() => _priority = v)),
          ],
          if (kind.hasStages) _dropdown('Stage', Icons.linear_scale_rounded, _status, stages, (v) => setState(() => _status = v)),
          if (kind == RecordKind.leads || kind == RecordKind.deals)
            _dropdown('Source', Icons.call_split_rounded, _source, _sources, (v) => setState(() => _source = v)),
          if (kind == RecordKind.leads) _field(_campaign, 'Service / campaign', Icons.campaign_outlined),
          _field(_notes, 'Notes', Icons.notes_rounded, lines: 4, caps: TextCapitalization.sentences),
          if (!editing && kind == RecordKind.leads)
            const Padding(
              padding: EdgeInsets.only(bottom: 12, left: 4),
              child: Text('The lead is assigned automatically using your team rules.',
                  style: TextStyle(color: Brand.muted, fontSize: 12.5)),
            ),
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Brand.red.withValues(alpha: .08), borderRadius: BorderRadius.circular(14)),
              child: Text(_error!, style: const TextStyle(color: Brand.red, fontWeight: FontWeight.w600)),
            ),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text(editing ? 'Save changes' : 'Create ${kind.singular.toLowerCase()}'),
          ),
        ],
      ),
    );
  }
}
