import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';

// ── Shared section building blocks ──────────────────────────────────────────

class SettingsSectionTitle extends StatelessWidget {
  final String text;
  const SettingsSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTypeScale.sizeBody,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const SettingsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    final glass = context.tokens;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: glass.cardFill,
        borderRadius: BorderRadius.circular(AppRadii.panel),
        border: Border.all(color: glass.stroke),
      ),
      child: child,
    );
  }
}

class SettingsDivider extends StatelessWidget {
  const SettingsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final glass = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(height: 1, color: glass.stroke),
    );
  }
}
