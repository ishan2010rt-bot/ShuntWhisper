import 'package:flutter/material.dart';
import '../../../domain/models/enums.dart';

class StatusBanner extends StatelessWidget {
  final Classification classification;
  final String? inconclusiveReason;

  const StatusBanner({
    super.key,
    required this.classification,
    this.inconclusiveReason,
  });

  @override
  Widget build(BuildContext context) {
    final (Color bgColor, Color textColor, IconData icon) = switch (classification) {
      Classification.patentHigh => (
          const Color(0xFF1B5E20),
          const Color(0xFFB9F6CA),
          Icons.check_circle_outline
        ),
      Classification.patentMarginal => (
          const Color(0xFFE65100),
          const Color(0xFFFFE082),
          Icons.warning_amber_outlined
        ),
      Classification.occluded => (
          const Color(0xFFB71C1C),
          const Color(0xFFFF8A80),
          Icons.error_outline
        ),
      Classification.inconclusive => (
          const Color(0xFF37474F),
          const Color(0xFFCFD8DC),
          Icons.help_outline
        ),
      Classification.unknown => (
          const Color(0xFF263238),
          Colors.white70,
          Icons.info_outline
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: textColor, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  classification.clinicalDescription,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (inconclusiveReason != null && inconclusiveReason!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Reason: $inconclusiveReason',
              style: TextStyle(color: textColor.withOpacity(0.85), fontSize: 14),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Research prototype. Not a validated medical device. Does not replace clinical evaluation.',
              style: TextStyle(color: Colors.white70, fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}

