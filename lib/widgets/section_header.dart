
import 'package:flutter/material.dart';


class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader({super.key, required this.title});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 4,
        height: 18,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
      const SizedBox(width: 10),
      Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    ],
  );
}

