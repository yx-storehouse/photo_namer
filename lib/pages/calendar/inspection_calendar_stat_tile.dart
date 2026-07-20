
import 'package:flutter/material.dart';


class InspectionCalendarStatTile extends StatelessWidget {
  final String label;
  final String value;
  final String hint;

  const InspectionCalendarStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF667085),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            hint,
            style: const TextStyle(fontSize: 12, color: Color(0xFF98A2B3)),
          ),
        ],
      ),
    );
  }
}

