import 'package:flutter/material.dart';

import '../providers/app_controller.dart';
import '../services/device_exception.dart';

Future<void> runAction(
  BuildContext context,
  Future<ActionReport> action,
) async {
  final report = await action;
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(report.message),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: report.hasFailures ? 6 : 2),
    ),
  );
}

Future<void> runSetting(BuildContext context, Future<void> action) async {
  try {
    await action;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(userMessage(error))));
    }
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key, this.trailing});
  final String title;
  final String subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 8),
              Text(subtitle),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(24), child: child),
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(
    this.label, {
    super.key,
    this.good = true,
    this.neutral = false,
  });
  final String label;
  final bool good;
  final bool neutral;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: neutral
            ? scheme.surfaceContainerHighest
            : good
            ? scheme.primary.withValues(alpha: .12)
            : scheme.errorContainer,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            neutral
                ? Icons.add_circle_outline
                : good
                ? Icons.check_circle_outline
                : Icons.cloud_off_outlined,
            size: 15,
            color: neutral
                ? scheme.onSurfaceVariant
                : good
                ? scheme.primary
                : scheme.onErrorContainer,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
        ],
      ),
    );
  }
}
