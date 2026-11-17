import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../core/push.dart';
import '../core/session.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'notifications.dart';
import 'records.dart';
import 'team.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final user = app.user;
    void open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    return Scaffold(
      appBar: AppBar(title: const Text('More'), actions: const [NotificationBell(), SizedBox(width: 6)]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (user != null)
            Panel(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Avatar(user.name, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(user.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(user.email, style: const TextStyle(color: Brand.muted, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Pill(user.team.isEmpty ? user.role : '${user.role} · ${user.team}', icon: Icons.shield_outlined, color: roleColor(user.role)),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 18),
          const SectionTitle('Workspace'),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              if (app.canSeeTeam)
                _NavTile(Icons.groups_rounded, app.canManageTeam ? 'Team & roles' : 'My team', () => open(const TeamScreen())),
              for (final kind in [if (!app.isEmployee) ...[RecordKind.contacts, RecordKind.companies], if (!app.isEmployee) RecordKind.tasks])
                _NavTile(kind.icon, kind.label, () => open(RecordListScreen(kind: kind))),
              _NavTile(Icons.notifications_rounded, 'Notifications', () => open(const NotificationsScreen()),
                  badge: app.unread),
            ]),
          ),
          const SizedBox(height: 18),
          const SectionTitle('Alerts on this phone'),
          const _AlertsPanel(),
          const SizedBox(height: 18),
          const SectionTitle('App'),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              _NavTile(Icons.open_in_browser_rounded, 'Open web workspace',
                  () => launchUrl(AppConfig.originUri, mode: LaunchMode.externalApplication)),
              _NavTile(Icons.info_outline_rounded, 'Version ${AppConfig.version}', null, trailing: Text(AppConfig.host,
                  style: const TextStyle(color: Brand.grey, fontSize: 12, fontWeight: FontWeight.w600))),
            ]),
          ),
          const SizedBox(height: 22),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Brand.red,
              side: BorderSide(color: Brand.red.withValues(alpha: .35)),
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () async {
              final ok = await confirm(
                context,
                title: 'Sign out?',
                message: 'This phone stops receiving enquiry alerts until you sign in again.',
                action: 'Sign out',
              );
              if (ok) {
                HapticFeedback.mediumImpact();
                await app.logout();
              }
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile(this.icon, this.label, this.onTap, {this.badge = 0, this.trailing});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final int badge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: Brand.accentSoft, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: Brand.accent, size: 20),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: trailing ??
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (badge > 0) Badge(label: Text('$badge'), backgroundColor: Brand.orange),
              if (onTap != null) const Icon(Icons.chevron_right_rounded, color: Brand.grey),
            ]),
      );
}

class _AlertsPanel extends StatefulWidget {
  const _AlertsPanel();

  @override
  State<_AlertsPanel> createState() => _AlertsPanelState();
}

class _AlertsPanelState extends State<_AlertsPanel> {
  bool _busy = false;

  Future<void> _test() async {
    setState(() => _busy = true);
    final app = AppScope.read(context);
    try {
      if (PushCenter.instance.status.value != PushStatus.on) await PushCenter.instance.enable(app.api);
      final delivered = await PushCenter.instance.sendTest(app.api);
      if (mounted) {
        showMessage(context, delivered > 0 ? 'Test sent to $delivered device${delivered == 1 ? '' : 's'}' : 'No device received it yet.');
      }
    } on ApiException catch (e) {
      if (mounted) {
        showMessage(context, e.status == 404 ? 'The workspace server update for phone alerts is still pending.' : e.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<PushStatus>(
        valueListenable: PushCenter.instance.status,
        builder: (context, status, _) {
          final (label, detail, color) = switch (status) {
            PushStatus.on => ('On', 'New website enquiries, reminders and assignments arrive instantly.', Brand.accent),
            PushStatus.denied => ('Blocked', 'Notifications are turned off for this app in Android settings.', Brand.red),
            PushStatus.serverPending => ('Waiting for server', 'This phone is registered with Firebase; the workspace update is pending.', Brand.amber),
            PushStatus.error => ('Not connected', 'Could not register this phone. Check your connection.', Brand.red),
            _ => ('Off', 'Turn on alerts to hear about new enquiries the moment they arrive.', Brand.grey),
          };
          return Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(status == PushStatus.on ? Icons.notifications_active_rounded : Icons.notifications_off_outlined, color: color),
                const SizedBox(width: 10),
                Text('Enquiry alerts', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const Spacer(),
                Pill(label, color: color),
              ]),
              const SizedBox(height: 8),
              Text(detail, style: const TextStyle(color: Brand.muted, height: 1.4)),
              const SizedBox(height: 14),
              Row(children: [
                if (status != PushStatus.on)
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                      onPressed: () => status == PushStatus.denied
                          ? PushCenter.instance.openSystemSettings()
                          : PushCenter.instance.enable(AppScope.read(context).api),
                      child: Text(status == PushStatus.denied ? 'Open settings' : 'Turn on'),
                    ),
                  ),
                if (status != PushStatus.on) const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _test,
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded, size: 18),
                    label: const Text('Send test'),
                  ),
                ),
              ]),
            ]),
          );
        },
      );
}
