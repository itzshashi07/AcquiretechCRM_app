import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Team members and what each role may do. Admins manage; managers can look.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List<CrmUser>? _members;
  int _total = 0;
  String? _error;
  String _search = '';
  String? _role;
  String _status = 'active';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = Map<String, dynamic>.from(await AppScope.read(context).api.get('/team', query: {
        'page': '1',
        'limit': '100',
        if (_search.isNotEmpty) 'search': _search,
        'role': ?_role,
        if (_status != 'all') 'status': _status,
      }) as Map);
      if (!mounted) return;
      setState(() {
        _members = (data['list'] as List).map((e) => CrmUser.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        _total = (data['total'] as num?)?.toInt() ?? _members!.length;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _open([CrmUser? member]) async {
    final app = AppScope.read(context);
    if (member != null && !app.canManageTeam) {
      await showModalBottomSheet<void>(context: context, builder: (_) => _MemberSheet(member));
      return;
    }
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => MemberFormScreen(member: member)));
    if (saved == true) {
      _load();
      app.loadPeople();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final members = _members;
    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      floatingActionButton: app.canManageTeam
          ? FloatingActionButton.extended(
              heroTag: 'add-member',
              onPressed: () => _open(),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add member', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: RefreshIndicator(
        color: Brand.accent,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
          children: [
            TextField(
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () {
                  _search = v.trim();
                  _load();
                });
              },
              decoration: const InputDecoration(hintText: 'Search by name, email or team', prefixIcon: Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final s in const ['active', 'inactive', 'all'])
                  _chip(s == 'all' ? 'Everyone' : '${s[0].toUpperCase()}${s.substring(1)}', _status == s, () {
                    setState(() => _status = s);
                    _load();
                  }),
                const SizedBox(width: 6),
                for (final r in roles)
                  _chip(r, _role == r, () {
                    setState(() => _role = _role == r ? null : r);
                    _load();
                  }),
              ]),
            ),
            const SizedBox(height: 14),
            const _RolesCard(),
            const SizedBox(height: 18),
            if (members == null && _error != null)
              ErrorState(_error!, onRetry: _load)
            else if (members == null)
              const SizedBox(height: 300, child: SkeletonList(count: 4, padding: EdgeInsets.zero))
            else if (members.isEmpty)
              const EmptyState(icon: Icons.groups_rounded, title: 'Nobody here', message: 'Try a different filter.')
            else ...[
              SectionTitle('$_total ${_total == 1 ? 'member' : 'members'}'),
              for (final m in members)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _MemberTile(m, isYou: m.id == app.user?.id, onTap: () => _open(m)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          showCheckmark: false,
          labelStyle: TextStyle(color: selected ? Colors.white : Brand.text, fontWeight: FontWeight.w600),
          onSelected: (_) {
            HapticFeedback.selectionClick();
            onTap();
          },
        ),
      );
}

Color roleColor(String role) => switch (role) {
      'Admin' => Brand.accent,
      'Manager' => Brand.blue,
      'Salesperson' => Brand.success,
      _ => Brand.cognac,
    };

class _MemberTile extends StatelessWidget {
  const _MemberTile(this.m, {required this.isYou, required this.onTap});
  final CrmUser m;
  final bool isYou;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Panel(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Opacity(opacity: m.active ? 1 : .45, child: Avatar(m.name)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isYou ? '${m.name} (you)' : m.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              const SizedBox(height: 3),
              Text(
                [if (m.email.isNotEmpty) m.email, if (m.team.isNotEmpty) m.team].join(' · ').ifEmpty('No team'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Brand.muted, fontSize: 13),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Pill(m.role, color: roleColor(m.role)),
            if (!m.active) ...[const SizedBox(height: 5), const Pill('Inactive', color: Brand.grey)],
          ]),
        ]),
      );
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _RolesCard extends StatefulWidget {
  const _RolesCard();

  @override
  State<_RolesCard> createState() => _RolesCardState();
}

class _RolesCardState extends State<_RolesCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Panel(
        onTap: () => setState(() => _open = !_open),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.admin_panel_settings_outlined, color: Brand.cognac),
            const SizedBox(width: 10),
            const Expanded(child: Text('Roles & permissions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            AnimatedRotation(
              turns: _open ? .5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.expand_more_rounded, color: Brand.muted),
            ),
          ]),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final r in roles)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(width: 104, child: Pill(r, color: roleColor(r))),
                            Expanded(child: Text(roleSummaries[r]!, style: const TextStyle(color: Brand.inkSoft, height: 1.4, fontSize: 13.5))),
                          ]),
                        ),
                      const Text(
                        'To remove someone, set them Inactive. Their records stay; sign-in and alerts stop immediately.',
                        style: TextStyle(color: Brand.muted, fontSize: 12.5, height: 1.4),
                      ),
                    ]),
                  ),
          ),
        ]),
      );
}

class _MemberSheet extends StatelessWidget {
  const _MemberSheet(this.m);
  final CrmUser m;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Avatar(m.name, size: 52),
              const SizedBox(width: 14),
              Expanded(child: Text(m.name, style: display(22))),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 8, children: [
              Pill(m.role, color: roleColor(m.role)),
              if (m.team.isNotEmpty) Pill(m.team, color: Brand.cognac),
              if (!m.active) const Pill('Inactive', color: Brand.grey),
            ]),
            const SizedBox(height: 14),
            Text(roleSummaries[m.role] ?? '', style: const TextStyle(color: Brand.inkSoft, height: 1.45)),
            const SizedBox(height: 10),
            const Text('Only an administrator can change roles or access.', style: TextStyle(color: Brand.muted, fontSize: 12.5)),
          ]),
        ),
      );
}

/// Admin form to add a member or change role, team, access and password.
class MemberFormScreen extends StatefulWidget {
  const MemberFormScreen({super.key, this.member});
  final CrmUser? member;

  @override
  State<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends State<MemberFormScreen> {
  late final CrmUser? m = widget.member;
  late final _name = TextEditingController(text: m?.name);
  late final _email = TextEditingController(text: m?.email);
  late final _team = TextEditingController(text: m?.team);
  late final _phone = TextEditingController(text: m?.phone);
  late final _department = TextEditingController(text: m?.department);
  late final _employeeId = TextEditingController(text: m?.profile['employeeId']);
  final _password = TextEditingController();
  final _crmId = TextEditingController();
  late String _role = m?.role ?? 'Salesperson';
  late bool _active = m?.active ?? true;
  bool _resetPassword = false;
  bool _busy = false;
  String? _error;

  // EspoCRM people the new member can be linked to (production needs one).
  List<Map<String, dynamic>>? _crmUsers;
  String? _crmUserId;

  bool get editing => m != null;
  bool get isSelf => m?.id == AppScope.read(context).user?.id;

  @override
  void initState() {
    super.initState();
    if (!editing) {
      _password.text = _generate();
      _loadCrmUsers();
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _team, _phone, _department, _employeeId, _password, _crmId]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCrmUsers() async {
    try {
      final data = Map<String, dynamic>.from(await AppScope.read(context).api.get('/crm-users') as Map);
      if (!mounted || data['available'] != true) return;
      setState(() {
        _crmUsers = (data['list'] as List).map((e) => Map<String, dynamic>.from(e as Map)).where((u) => u['linked'] != true).toList();
      });
      _matchEmail();
    } catch (_) {
      // Older servers, or EspoCRM without user listing: the manual field stays.
    }
  }

  void _matchEmail() {
    final email = _email.text.trim().toLowerCase();
    if (_crmUsers == null || email.isEmpty || _crmUserId != null) return;
    for (final u in _crmUsers!) {
      if ((u['email'] ?? '').toString().toLowerCase() == email) {
        setState(() => _crmUserId = u['id'].toString());
        return;
      }
    }
  }

  static String _generate() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789@#%+';
    final r = Random.secure();
    return List.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Map<String, dynamic> _body() => {
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'role': _role,
        'team': _team.text.trim(),
        'active': _active,
        'phone': _phone.text.trim(),
        'department': _department.text.trim(),
        'employeeId': _employeeId.text.trim(),
        if (editing) ...{
          'joiningDate': m!.profile['joiningDate'] ?? '',
          'managerId': m!.profile['managerId'] ?? '',
          'notes': m!.profile['notes'] ?? '',
        },
        if (!editing || _resetPassword) 'password': _password.text,
        if (!editing && (_crmUserId ?? _crmId.text.trim()).isNotEmpty) 'crmUserId': _crmUserId ?? _crmId.text.trim(),
      };

  Future<void> _save() async {
    final body = _body();
    if ((body['name'] as String).isEmpty || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(body['email'] as String)) {
      setState(() => _error = 'Add a name and a valid email address.');
      return;
    }
    if (body.containsKey('password') && (body['password'] as String).length < 12) {
      setState(() => _error = 'Passwords need at least 12 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = AppScope.read(context).api;
    try {
      if (editing) {
        await api.put('/users/${m!.id}', body);
      } else {
        await api.post('/users', body);
      }
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      if (body.containsKey('password')) await _shareCredentials(body['email'] as String, body['password'] as String);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareCredentials(String email, String password) => showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(editing ? 'Password reset' : 'Member added'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Share these sign-in details privately. They will not be shown again.', style: TextStyle(height: 1.4)),
            const SizedBox(height: 14),
            SelectableText('$email\n$password', style: const TextStyle(fontWeight: FontWeight.w700, height: 1.5)),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: 'Acquiretech CRM\n$email\n$password'));
                showMessage(context, 'Copied');
              },
              child: const Text('Copy'),
            ),
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done')),
          ],
        ),
      );

  Future<void> _toggleAccess() async {
    final deactivate = _active;
    final ok = await confirm(
      context,
      title: deactivate ? 'Remove ${m!.name}\'s access?' : 'Restore ${m!.name}\'s access?',
      message: deactivate
          ? 'They are signed out everywhere and stop receiving alerts. Their records stay in the CRM.'
          : 'They can sign in again with their existing password.',
      action: deactivate ? 'Remove access' : 'Restore',
    );
    if (!ok) return;
    setState(() => _active = !deactivate);
    await _save();
  }

  Widget _field(TextEditingController c, String label, IconData icon, {TextInputType? type, ValueChanged<String>? onChanged}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: type,
          onChanged: onChanged,
          textCapitalization: type == null ? TextCapitalization.words : TextCapitalization.none,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(editing ? m!.name : 'Add member')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _field(_name, 'Full name', Icons.badge_outlined),
          _field(_email, 'Work email', Icons.alternate_email_rounded,
              type: TextInputType.emailAddress, onChanged: (_) => _matchEmail()),
          const SectionTitle('Role'),
          for (final r in roles)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RoleOption(
                role: r,
                selected: _role == r,
                enabled: !(isSelf && r != 'Admin'),
                onTap: () => setState(() => _role = r),
              ),
            ),
          const SizedBox(height: 6),
          _field(_team, 'Team (managers see their team)', Icons.groups_outlined),
          _field(_phone, 'Phone', Icons.call_outlined, type: TextInputType.phone),
          _field(_department, 'Department', Icons.apartment_outlined),
          _field(_employeeId, 'Employee ID', Icons.tag_rounded),
          if (!editing) ...[
            const SectionTitle('CRM account link'),
            if (_crmUsers != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  initialValue: _crmUserId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'EspoCRM user', prefixIcon: Icon(Icons.link_rounded)),
                  items: [
                    for (final u in _crmUsers!)
                      DropdownMenuItem(
                        value: u['id'].toString(),
                        child: Text('${u['name']}${(u['email'] ?? '').toString().isEmpty ? '' : ' — ${u['email']}'}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _crmUserId = v),
                ),
              )
            else
              _field(_crmId, 'EspoCRM user ID (needed on the live workspace)', Icons.link_rounded, type: TextInputType.text),
            const SectionTitle('First password'),
          ] else ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _resetPassword,
              onChanged: (v) => setState(() {
                _resetPassword = v;
                if (v) _password.text = _generate();
              }),
              title: const Text('Reset password', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Signs them out everywhere'),
            ),
          ],
          if (!editing || _resetPassword)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: 'Password (12+ characters)',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Generate a new one',
                    icon: const Icon(Icons.autorenew_rounded),
                    onPressed: () => setState(() => _password.text = _generate()),
                  ),
                ),
              ),
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
                : Text(editing ? 'Save changes' : 'Add member'),
          ),
          if (editing && !isSelf) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _toggleAccess,
              style: OutlinedButton.styleFrom(
                foregroundColor: _active ? Brand.red : Brand.success,
                side: BorderSide(color: (_active ? Brand.red : Brand.success).withValues(alpha: .35)),
                minimumSize: const Size.fromHeight(52),
              ),
              icon: Icon(_active ? Icons.person_off_outlined : Icons.person_add_alt_1_outlined),
              label: Text(_active ? 'Remove access' : 'Restore access'),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({required this.role, required this.selected, required this.enabled, required this.onTap});
  final String role;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = roleColor(role);
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: Material(
        color: selected ? color.withValues(alpha: .08) : Brand.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? color : Brand.border, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onTap();
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? color : Brand.grey, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(role, style: TextStyle(fontWeight: FontWeight.w700, color: selected ? Brand.onTint(color) : Brand.text)),
                  const SizedBox(height: 3),
                  Text(roleSummaries[role]!, style: const TextStyle(color: Brand.muted, fontSize: 12.5, height: 1.35)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
