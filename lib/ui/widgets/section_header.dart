import 'package:flutter/material.dart';
import '../../util/app_spacing.dart';

/// Reusable section header with a green accent bar on the left.
/// Used across settings pages for visual section separation.
class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
        AppSpacing.horizontalSm,
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
