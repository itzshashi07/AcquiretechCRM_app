import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/session.dart';
import '../features/notifications.dart';
import 'theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.onTap, this.large = false});
  final String status;
  final VoidCallback? onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final color = Brand.stage(status);
    final chip = Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 9, vertical: large ? 7 : 4),
      decoration: BoxDecoration(color: color.withValues(alpha: .11), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(
          status.isEmpty ? 'No stage' : status,
          style: TextStyle(color: Brand.onTint(color), fontWeight: FontWeight.w700, fontSize: large ? 13 : 11.5),
        ),
        if (onTap != null) ...[const SizedBox(width: 2), Icon(Icons.expand_more_rounded, size: 16, color: color)],
      ]),
    );
    if (onTap == null) return chip;
    return InkWell(borderRadius: BorderRadius.circular(99), onTap: onTap, child: chip);
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.icon, this.color = Brand.accent});
  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: Brand.onTint(color)), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: Brand.onTint(color), fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 44, this.icon});
  final String name;
  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = Brand.forName(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .34),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: .16), color.withValues(alpha: .26)],
        ),
      ),
      child: icon != null
          ? Icon(icon, color: color, size: size * .48)
          : Text(
              initials(name),
              style: TextStyle(color: Brand.onTint(color), fontWeight: FontWeight.w700, fontSize: size * .36, letterSpacing: -.3),
            ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 10),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

/// Rounded white surface with a soft border; the building block of every screen.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Brand.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Brand.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: Padding(padding: padding, child: child),
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: Brand.accentSoft, borderRadius: BorderRadius.circular(24)),
            child: Icon(icon, color: Brand.accent, size: 32),
          ),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted, height: 1.4)),
          ],
          if (action != null) ...[
            const SizedBox(height: 18),
            FilledButton.tonal(onPressed: onAction, child: Text(action!)),
          ],
        ]),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState(this.message, {super.key, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load this',
        message: message,
        action: 'Try again',
        onAction: onRetry,
      );
}

/// Gently pulsing placeholder rows while data loads.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.count = 6, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 16)});
  final int count;
  final EdgeInsets padding;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _bar(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: Brand.raised, borderRadius: BorderRadius.circular(8)),
      );

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: .45, end: 1.0).animate(_c),
        child: ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: widget.padding,
          itemCount: widget.count,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, i) => Panel(
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Brand.raised, borderRadius: BorderRadius.circular(15)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _bar(140.0 + (i % 3) * 30, 13),
                  const SizedBox(height: 8),
                  _bar(90.0 + (i % 2) * 50, 10),
                ]),
              ),
              _bar(56, 18),
            ]),
          ),
        ),
      );
}

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.light = false});
  final bool light;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final color = light ? Colors.white : Brand.text;
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
      },
      icon: Badge(
        isLabelVisible: app.unread > 0,
        backgroundColor: Brand.orange,
        label: Text(app.unread > 99 ? '99+' : '${app.unread}'),
        child: Icon(app.unread > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, color: color),
      ),
    );
  }
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Brand.red : Brand.ink,
      duration: Duration(milliseconds: error ? 4500 : 2600),
    ));
}

Future<bool> confirm(BuildContext context, {required String title, required String message, required String action}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      content: Text(message, style: const TextStyle(height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}
