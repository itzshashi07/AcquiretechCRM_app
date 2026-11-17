import 'package:flutter/material.dart';

enum RecordKind {
  leads('Leads', 'Lead', Icons.person_search_rounded),
  contacts('Contacts', 'Contact', Icons.contacts_rounded),
  companies('Companies', 'Company', Icons.apartment_rounded),
  deals('Deals', 'Deal', Icons.handshake_rounded),
  tasks('Tasks', 'Task', Icons.task_alt_rounded);

  const RecordKind(this.label, this.singular, this.icon);
  final String label;
  final String singular;
  final IconData icon;

  static RecordKind? parse(String? value) {
    for (final kind in RecordKind.values) {
      if (kind.name == value) return kind;
    }
    return null;
  }

  bool get hasStages => this == leads || this == deals || this == tasks;
  bool get isPerson => this == leads || this == contacts;
}

String _s(dynamic v) => v == null ? '' : v.toString();
DateTime? _date(dynamic v) => v == null || v == '' ? null : DateTime.tryParse(v.toString())?.toLocal();

const roles = ['Admin', 'Manager', 'Salesperson', 'Employee'];

/// What each role can do, stated from the server's enforcement (auth.ts / crm.ts).
const roleSummaries = {
  'Admin': 'Every record. Adds team members, changes roles and teams, deactivates access, '
      'edits workflow stages and automations, reviews website submissions and can delete records.',
  'Manager': 'Records owned by people in their own team. Leads they create are shared '
      'round-robin within the team. Sees the team list (without emails). Cannot manage users or settings, or delete.',
  'Salesperson': 'Only their own leads, contacts, companies, deals and tasks. New records they create are theirs.',
  'Employee': 'Only their own tasks. No access to leads, contacts, companies, deals or the team.',
};

class CrmUser {
  CrmUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.team = '',
    this.active = true,
    this.profile = const {},
  });

  factory CrmUser.fromJson(Map<String, dynamic> j) => CrmUser(
        id: _s(j['id']),
        name: _s(j['name']),
        email: _s(j['email']),
        role: _s(j['role']),
        team: _s(j['team']),
        active: j['active'] != false && j['active'] != 0,
        profile: {
          for (final k in ['phone', 'department', 'employeeId', 'joiningDate', 'managerId', 'notes'])
            if (j[k] != null) k: _s(j[k]),
        },
      );

  final String id;
  final String name;
  final String email;
  final String role;
  final String team;
  final bool active;
  final Map<String, String> profile;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;
  bool get isAdmin => role == 'Admin';
  bool get isEmployee => role == 'Employee';
  String get phone => profile['phone'] ?? '';
  String get department => profile['department'] ?? '';

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'email': email, 'role': role, 'team': team, 'active': active, ...profile};
}

class CrmRecord {
  CrmRecord(this.json);

  factory CrmRecord.fromJson(Map<String, dynamic> j) => CrmRecord(j);

  final Map<String, dynamic> json;

  String get id => _s(json['id']);
  String get name => _s(json['name']);
  String get email => _s(json['email']);
  String get phone => _s(json['phone']);
  String get company => _s(json['company']);
  String get source => _s(json['source']);
  String get campaign => _s(json['campaign']);
  String get status => _s(json['status']);
  String get ownerId => _s(json['ownerId']);
  String get notes => _s(json['notes']);
  String get priority => _s(json['priority']);
  String get closeDate => _s(json['closeDate']);
  String get dueDate => _s(json['dueDate']);
  double? get amount => (json['amount'] as num?)?.toDouble();
  double? get probability => (json['probability'] as num?)?.toDouble();
  List<String> get tags => (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [];
  Map<String, String> get customFields =>
      (json['customFields'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {};
  DateTime? get createdAt => _date(json['createdAt']);
  DateTime? get updatedAt => _date(json['updatedAt']);
  bool get fromWebsite => source.toLowerCase() == 'website';
}

class PageResult<T> {
  PageResult(this.list, this.total);
  final List<T> list;
  final int total;
}

class Workflow {
  Workflow(this.leads, this.deals, this.tasks);

  factory Workflow.defaults() => Workflow(
        ['New Lead', 'Contacted', 'Qualified', 'Proposal', 'Negotiation', 'Converted', 'Junk', 'Lost'],
        ['New', 'Qualified', 'Proposal Sent', 'Negotiation', 'Won', 'Lost'],
        ['Pending', 'In Progress', 'Completed', 'Cancelled'],
      );

  factory Workflow.fromJson(Map<String, dynamic> j) {
    List<String> list(String key, List<String> fallback) =>
        (j[key] as List?)?.map((e) => e.toString()).toList() ?? fallback;
    final d = Workflow.defaults();
    return Workflow(list('leads', d.leads), list('deals', d.deals), list('tasks', d.tasks));
  }

  final List<String> leads;
  final List<String> deals;
  final List<String> tasks;

  List<String> stagesFor(RecordKind kind) => switch (kind) {
        RecordKind.leads => leads,
        RecordKind.deals => deals,
        RecordKind.tasks => tasks,
        _ => const [],
      };

  static const terminal = {
    RecordKind.leads: ['Converted', 'Junk', 'Lost'],
    RecordKind.deals: ['Won', 'Lost'],
    RecordKind.tasks: ['Completed', 'Cancelled'],
  };

  bool isTerminal(RecordKind kind, String status) => terminal[kind]?.contains(status) ?? false;
}

/// A timeline entry: note, call, follow-up and so on (snake_case from the API).
class Engagement {
  Engagement(this.json);

  final Map<String, dynamic> json;

  String get id => _s(json['id']);
  RecordKind? get kind => RecordKind.parse(_s(json['kind']));
  String get recordId => _s(json['record_id']);
  String get type => _s(json['type']);
  String get title => _s(json['title']);
  String get body => _s(json['body']);
  String get url => _s(json['url']);
  String get status => _s(json['status']);
  String get actorId => _s(json['actor_id']);
  String get recordName => _s(json['recordName']);
  DateTime? get dueAt => _date(json['due_at']);
  DateTime? get createdAt => _date(json['created_at']);
  bool get isFollowUp => type == 'Follow-up';
  bool get isScheduled => status == 'Scheduled';
  bool get isOverdue => isScheduled && (dueAt?.isBefore(DateTime.now()) ?? false);
}

class CrmEvent {
  CrmEvent(this.json);

  final Map<String, dynamic> json;

  String get actorId => _s(json['actor_id']);
  String get action => _s(json['action']);
  DateTime? get createdAt => _date(json['created_at']);
}

class Notice {
  Notice(this.json);

  final Map<String, dynamic> json;

  String get id => _s(json['id']);
  String get message => _s(json['message']);
  String get recordId => _s(json['record_id']);
  RecordKind? get kind => RecordKind.parse(_s(json['kind']));
  bool get read => json['read'] == 1 || json['read'] == true;
  DateTime? get createdAt => _date(json['created_at']);

  String get title {
    final m = message;
    final noun = kind?.singular.toLowerCase() ?? 'record';
    if (m.endsWith(' captured')) return 'New website enquiry';
    if (m.contains('follow-up overdue')) return 'Follow-up overdue';
    if (m.contains('follow-up due')) return 'Follow-up due soon';
    if (m.contains('reassigned')) return 'A $noun was assigned to you';
    if (m.endsWith(' created')) return 'New $noun for you';
    if (m.contains('stage changed')) return 'Stage changed';
    if (m.endsWith(' converted')) return 'Lead converted';
    if (m.endsWith(' updated')) return '${kind?.singular ?? 'Record'} updated';
    return m.isEmpty ? 'Update' : '${m[0].toUpperCase()}${m.substring(1)}';
  }

  String get detail {
    final m = message;
    final colon = m.indexOf(': ');
    if (colon >= 0) return m.substring(colon + 2);
    if (m.endsWith(' captured')) return 'A visitor filled a form on the website. Tap to respond.';
    return 'Tap to open the ${kind?.singular.toLowerCase() ?? 'record'}.';
  }
}
