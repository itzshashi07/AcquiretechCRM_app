import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/push.dart';
import '../core/session.dart';
import '../ui/theme.dart';
import 'followups.dart';
import 'home.dart';
import 'more.dart';
import 'notifications.dart';
import 'record_detail.dart';
import 'records.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _index = 0;
  Timer? _poll;
  final _homeKey = GlobalKey<HomeScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PushCenter.instance.opened.addListener(_consumeOpened);
    PushCenter.instance.received.addListener(_onPush);
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeOpened());
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => AppScope.read(context).refreshUnread());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushCenter.instance.opened.removeListener(_consumeOpened);
    PushCenter.instance.received.removeListener(_onPush);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final app = AppScope.read(context);
      app.refreshUnread();
      app.dataChanged();
      _homeKey.currentState?.reload(quiet: true);
    }
  }

  void _onPush() {
    AppScope.read(context)
      ..refreshUnread()
      ..dataChanged();
    _homeKey.currentState?.reload(quiet: true);
  }

  /// Opens the record a tapped notification points at, e.g. `/leads?record=abc`.
  void _consumeOpened() {
    final url = PushCenter.instance.opened.value;
    if (url == null || !mounted) return;
    PushCenter.instance.opened.value = null;
    final uri = Uri.tryParse('https://app$url');
    final kind = RecordKind.parse(uri?.pathSegments.isEmpty ?? true ? null : uri!.pathSegments.first);
    final id = uri?.queryParameters['record'];
    final nav = Navigator.of(context);
    nav.popUntil((r) => r.isFirst);
    if (kind != null && id != null && id.isNotEmpty) {
      nav.push(MaterialPageRoute(builder: (_) => RecordDetailScreen(kind: kind, id: id)));
    } else if (uri?.path == '/notifications') {
      nav.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    } else {
      setState(() => _index = 0);
    }
    AppScope.read(context).refreshUnread();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    // Employees only ever work with their own tasks; everyone else gets the full CRM.
    final tabs = <(Widget, NavigationDestination)>[
      (
        HomeScreen(key: _homeKey, onOpenTab: (i) => setState(() => _index = i)),
        const NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard_rounded), label: 'Home'),
      ),
      if (app.isEmployee)
        (
          const RecordListScreen(kind: RecordKind.tasks),
          const NavigationDestination(
              icon: Icon(Icons.task_alt_outlined), selectedIcon: Icon(Icons.task_alt_rounded), label: 'Tasks'),
        )
      else ...[
        (
          const RecordListScreen(kind: RecordKind.leads),
          const NavigationDestination(
              icon: Icon(Icons.person_search_outlined), selectedIcon: Icon(Icons.person_search_rounded), label: 'Leads'),
        ),
        (
          const RecordListScreen(kind: RecordKind.deals, showPipeline: true),
          const NavigationDestination(
              icon: Icon(Icons.handshake_outlined), selectedIcon: Icon(Icons.handshake_rounded), label: 'Deals'),
        ),
      ],
      (
        const FollowupsScreen(),
        const NavigationDestination(
            icon: Icon(Icons.event_available_outlined), selectedIcon: Icon(Icons.event_available_rounded), label: 'Follow-ups'),
      ),
      (
        const MoreScreen(),
        const NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'More'),
      ),
    ];
    final index = _index.clamp(0, tabs.length - 1);
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _index = 0);
      },
      child: Scaffold(
        body: IndexedStack(index: index, children: [for (final t in tabs) t.$1]),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Brand.border))),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) {
              HapticFeedback.selectionClick();
              setState(() => _index = i);
            },
            destinations: [for (final t in tabs) t.$2],
          ),
        ),
      ),
    );
  }
}
