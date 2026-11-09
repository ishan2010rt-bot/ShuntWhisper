import 'dart:math';
import 'package:flutter/material.dart';
import '../../../domain/models/alignment_models.dart';
import '../../../domain/models/enums.dart';

/// Reticle and HUD CustomPainter rendering projectively mapped patch targets.
class AlignmentHudPainter extends CustomPainter {
  final FiducialAlignmentState? alignment;
  final int consecutiveAligned;
  final int targetAlignedFrames;

  AlignmentHudPainter({
    required this.alignment,
    this.consecutiveAligned = 0,
    this.targetAlignedFrames = 8,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final status = alignment?.status ?? AlignmentStatus.notDetected;
    final Color hudColor = switch (status) {
      AlignmentStatus.aligned => const Color(0xFF00E676),    // Bright medical green
      AlignmentStatus.unstable => const Color(0xFFFFD600),   // Warning yellow
      AlignmentStatus.misaligned => const Color(0xFFFF9100), // Amber
      AlignmentStatus.notDetected => const Color(0xFF9E9E9E),// Dim grey
      AlignmentStatus.unknown => const Color(0xFF9E9E9E),
    };

    final paintStroke = Paint()
      ..color = hudColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final paintFill = Paint()
      ..color = hudColor.withOpacity(0.12)
      ..style = PaintingStyle.fill;

    // 1. Draw central guide reticle
    final center = Offset(size.width / 2, size.height / 2);
    const boxW = 240.0;
    const boxH = 140.0;
    final guideRect = Rect.fromCenter(center: center, width: boxW, height: boxH);
    canvas.drawRRect(RRect.fromRectAndRadius(guideRect, const Radius.circular(12)), paintStroke);

    // 2. Draw 4 Corner Fiducial Markers
    _drawCornerBrackets(canvas, guideRect, hudColor);

    // 3. Draw 3 Patch Targets (Upstream, Downstream, Lateral Reference)
    _drawPatchTargets(canvas, center, hudColor, paintFill);

    // 4. Draw Stability Progress Ring
    if (consecutiveAligned > 0) {
      final double progress = (consecutiveAligned / targetAlignedFrames).clamp(0.0, 1.0);
      final ringPaint = Paint()
        ..color = const Color(0xFF00E676)
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 28),
        -pi / 2,
        2 * pi * progress,
        false,
        ringPaint,
      );
    }
  }

  void _drawCornerBrackets(Canvas canvas, Rect rect, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    const len = 20.0;

    // Top-Left
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(len, 0), p);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, len), p);

    // Top-Right
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-len, 0), p);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, len), p);

    // Bottom-Left
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(len, 0), p);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -len), p);

    // Bottom-Right
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-len, 0), p);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -len), p);
  }

  void _drawPatchTargets(Canvas canvas, Offset center, Color color, Paint fillPaint) {
    final p = Paint()
      ..color = color.withOpacity(0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Upstream ROI (left, x = -8.7mm)
    final upRect = Rect.fromCenter(center: center - const Offset(65, 0), width: 34, height: 48);
    canvas.drawRect(upRect, fillPaint);
    canvas.drawRect(upRect, p);

    // Downstream ROI (right, x = +8.7mm)
    final dnRect = Rect.fromCenter(center: center + const Offset(65, 0), width: 34, height: 48);
    canvas.drawRect(dnRect, fillPaint);
    canvas.drawRect(dnRect, p);

    // Lateral Reference ROI (bottom, y = +12mm)
    final latRect = Rect.fromCenter(center: center + const Offset(0, 48), width: 34, height: 48);
    canvas.drawRect(latRect, fillPaint);
    canvas.drawRect(latRect, p);

    // Flow arrow connecting Upstream -> Downstream
    final arrowPaint = Paint()
      ..color = color.withOpacity(0.6)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(center - const Offset(42, 0), center + const Offset(42, 0), arrowPaint);
  }

  @override
  bool shouldRepaint(covariant AlignmentHudPainter oldDelegate) {
    return oldDelegate.alignment != alignment ||
        oldDelegate.consecutiveAligned != consecutiveAligned;
  }
}

