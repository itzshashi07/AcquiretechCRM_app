import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';
import 'push.dart';

/// Signed-in user, workspace settings, role permissions, the unread badge
/// and a small on-device cache that makes every screen paint instantly.
class AppState extends ChangeNotifier {
  AppState() {
    api.onSessionLost = () {
      if (user == null) return;
      user = null;
      notifyListeners();
    };
  }

  final api = CrmApi(const FlutterSecureStorage());
  SharedPreferences? _prefs;

  CrmUser? user;
  bool booting = true;
  Workflow workflow = Workflow.defaults();
  String currency = 'USD';
  Map<String, String> people = {};
  int unread = 0;

  /// Bumped when new data may exist (a push arrived, the app came back, a record was created).
  /// Lists listen to it and refresh quietly.
  final ValueNotifier<int> refresh = ValueNotifier(0);
  void dataChanged() => refresh.value++;

  // ── Role permissions. The server enforces them; the app mirrors them so
  //    nobody sees a button they are not allowed to use.
  String get role => user?.role ?? '';
  bool get isAdmin => role == 'Admin';
  bool get isManager => role == 'Manager';
  bool get isEmployee => role == 'Employee';
  bool get canSeeTeam => isAdmin || isManager;
  bool get canManageTeam => isAdmin;
  bool get canDelete => isAdmin;
  bool canAccess(RecordKind kind) => !isEmployee || kind == RecordKind.tasks;

  // ── Instant start: show the last signed-in user immediately, verify in the background.
  Future<void> boot() async {
    _prefs = await SharedPreferences.getInstance();
    _restoreWorkspace();
    final hasSession = await api.restore();
    final cached = _prefs?.getString('user');
    if (hasSession && cached != null) {
      try {
        user = CrmUser.fromJson(Map<String, dynamic>.from(jsonDecode(cached) as Map));
      } catch (_) {}
    }
    booting = false;
    notifyListeners();
    if (hasSession) unawaited(_verify());
  }

  Future<void> _verify() async {
    try {
      final me = CrmUser.fromJson(Map<String, dynamic>.from(await api.get('/auth/me') as Map));
      final changed = me.role != user?.role || me.name != user?.name || user == null;
      user = me;
      await _prefs?.setString('user', jsonEncode(me.toJson()));
      if (changed) notifyListeners();
      await _afterSignIn(askPermission: false);
    } on ApiException catch (e) {
      // Offline: keep working from the cache. Signed out elsewhere: back to sign-in.
      if (e.status == 401 && user != null) {
        user = null;
        notifyListeners();
      }
    }
  }

  Future<void> login(String email, String password, {required bool remember}) async {
    final signedIn = await api.login(email, password, remember: remember);
    if (user != null && user!.id != signedIn.id) await _clearCache();
    user = signedIn;
    await _prefs?.setString('user', jsonEncode(signedIn.toJson()));
    notifyListeners();
    unawaited(_afterSignIn(askPermission: true));
  }

  Future<void> _afterSignIn({required bool askPermission}) async {
    await Future.wait([loadSettings(), loadPeople(), refreshUnread()]);
    await PushCenter.instance.enable(api, ask: askPermission);
  }

  void _restoreWorkspace() {
    final raw = _prefs?.getString('workspace');
    if (raw == null) return;
    try {
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      workflow = Workflow.fromJson(Map<String, dynamic>.from(data['workflow'] as Map));
      currency = (data['currency'] as String?) ?? currency;
      people = Map<String, String>.from(data['people'] as Map? ?? const {});
    } catch (_) {}
  }

  void _saveWorkspace() => _prefs?.setString(
        'workspace',
        jsonEncode({
          'workflow': {'leads': workflow.leads, 'deals': workflow.deals, 'tasks': workflow.tasks},
          'currency': currency,
          'people': people,
        }),
      );

  Future<void> loadSettings() async {
    try {
      final data = Map<String, dynamic>.from(await api.get('/settings') as Map);
      workflow = Workflow.fromJson(Map<String, dynamic>.from(data['workflow'] as Map));
      currency = (data['currency'] as String?) ?? currency;
      _saveWorkspace();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadPeople() async {
    try {
      final list = await api.get('/users') as List;
      people = {for (final u in list.cast<Map>()) u['id'].toString(): u['name'].toString()};
      _saveWorkspace();
      notifyListeners();
    } catch (_) {}
  }

  String personName(String id) {
    if (id.isEmpty) return 'Unassigned';
    if (id == user?.id) return 'You';
    return people[id] ?? 'Team member';
  }

  // ── Last-known responses, so screens paint before the network answers.
  dynamic recall(String key) {
    final raw = _prefs?.getString('cache:${user?.id}:$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  void remember(String key, Object? data) {
    if (user == null || data == null) return;
    final raw = jsonEncode(data);
    if (raw.length < 400000) _prefs?.setString('cache:${user!.id}:$key', raw);
  }

  Future<void> _clearCache() async {
    final prefs = _prefs;
    if (prefs == null) return;
    for (final key in prefs.getKeys().where((k) => k.startsWith('cache:') || k == 'user' || k == 'workspace')) {
      await prefs.remove(key);
    }
  }

  Future<void> refreshUnread() async {
    if (user == null) return;
    int? count;
    try {
      final data = await api.get('/notifications/unread');
      count = ((data as Map)['unread'] as num?)?.toInt();
    } on ApiException catch (e) {
      // Older servers have no unread endpoint: count from the recent list.
      if (e.status == 404) {
        try {
          final list = await api.get('/notifications') as List;
          count = list.cast<Map>().where((n) => n['read'] == 0 || n['read'] == false).length;
        } catch (_) {}
      }
    } catch (_) {}
    if (count != null && count != unread) {
      unread = count;
      notifyListeners();
    }
  }

  Future<void> markAllRead() async {
    try {
      await api.post('/notifications/read');
      unread = 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> logout() async {
    await PushCenter.instance.signOut();
    await api.logout();
    await _clearCache();
    user = null;
    unread = 0;
    people = {};
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Access without rebuilding when the state changes.
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
