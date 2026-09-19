import "package:flutter/material.dart";

import "../utils/preferences.dart";
import "../utils/theme.dart";

class TravelPreferenceSelector extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final bool enabled;
  final String title;
  final String subtitle;

  const TravelPreferenceSelector({
    super.key,
    required this.selected,
    required this.onToggle,
    this.enabled = true,
    this.title = "What pulls you in?",
    this.subtitle =
        "Choose a few signals so your recommendations feel personal.",
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_awesome_outlined,
                color: AppTheme.primary, size: 22),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontFamily: AppTheme.displayFontFamily,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: travelPreferenceOptions.map((option) {
            final isSelected = selected.contains(option.id);
            return Semantics(
              button: true,
              selected: isSelected,
              label: "${option.label}: ${option.description}",
              child: FilterChip(
                label: Text(option.label),
                selected: isSelected,
                showCheckmark: false,
                avatar: Icon(
                  isSelected ? Icons.check_rounded : option.icon,
                  size: 16,
                ),
                onSelected: enabled ? (_) => onToggle(option.id) : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          preferenceCountLabel(selected.length),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected.isEmpty
                    ? AppTheme.textSecondary
                    : AppTheme.primaryDark,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}
