import 'dart:math';
import 'dart:typed_data';
import 'package:shuntwhisper_app/domain/models/alignment_models.dart';

/// Client-side image validation rules (Section D.2 of Blueprint).
class FrameValidator {
  final double minSharpness;
  final double maxWhiteClipFrac;
  final double maxSpecularFrac;

  const FrameValidator({
    this.minSharpness = 0.06,
    this.maxWhiteClipFrac = 0.02,
    this.maxSpecularFrac = 0.05,
  });

  /// Computes normalised Laplacian variance and exposure metrics over a luma plane (Y plane).
  FrameValidationResult validateLumaPlane({
    required Uint8List luma,
    required int width,
    required int height,
    int stride = 1,
  }) {
    if (luma.isEmpty || width <= 2 || height <= 2) {
      return const FrameValidationResult(
        passed: false,
        sharpness: 0.0,
        whiteLevel: 0.0,
        whiteClipFrac: 1.0,
        failures: ['EMPTY_FRAME'],
      );
    }

    final int sampleStep = stride > 0 ? stride : 1;
    double sumLuma = 0;
    int clippedCount = 0;
    int totalSampled = 0;

    // 1. Exposure and clipping pass
    for (int y = 0; y < height; y += sampleStep) {
      final int rowOffset = y * width;
      for (int x = 0; x < width; x += sampleStep) {
        final int val = luma[rowOffset + x];
        sumLuma += val;
        if (val >= 254) {
          clippedCount++;
        }
        totalSampled++;
      }
    }

    final double meanLuma = totalSampled > 0 ? (sumLuma / totalSampled) / 255.0 : 0.0;
    final double clipFrac = totalSampled > 0 ? clippedCount / totalSampled : 1.0;

    // 2. Discrete 3x3 Laplacian variance pass (sampled at central grid)
    double sumLap = 0;
    double sumLapSq = 0;
    int lapCount = 0;

    const int margin = 16;
    for (int y = margin; y < height - margin; y += (sampleStep * 2)) {
      final int row = y * width;
      final int rowPrev = (y - 1) * width;
      final int rowNext = (y + 1) * width;

      for (int x = margin; x < width - margin; x += (sampleStep * 2)) {
        // Discrete Laplacian kernel [[0, 1, 0], [1, -4, 1], [0, 1, 0]]
        final int center = luma[row + x];
        final int lap = luma[rowPrev + x] +
            luma[rowNext + x] +
            luma[row + x - 1] +
            luma[row + x + 1] -
            (center << 2);

        sumLap += lap;
        sumLapSq += lap * lap;
        lapCount++;
      }
    }

    double variance = 0.0;
    if (lapCount > 0) {
      final double mean = sumLap / lapCount;
      variance = (sumLapSq / lapCount) - (mean * mean);
    }

    // Normalised sharpness metric
    final double sharpness = meanLuma > 0.05 ? (variance / 1000.0) / (meanLuma * meanLuma) : 0.0;

    final List<String> failures = [];
    if (sharpness < minSharpness) {
      failures.add('QC_MOTION_BLUR');
    }
    if (clipFrac > maxWhiteClipFrac) {
      failures.add('QC_EXPOSURE_CLIPPED');
    }
    if (meanLuma < 0.20) {
      failures.add('QC_UNDER_EXPOSED');
    }

    return FrameValidationResult(
      passed: failures.isEmpty,
      sharpness: double.parse(sharpness.toStringAsFixed(4)),
      whiteLevel: double.parse(meanLuma.toStringAsFixed(3)),
      whiteClipFrac: double.parse(clipFrac.toStringAsFixed(4)),
      specularFracByRoi: {'overall': clipFrac},
      failures: failures,
    );
  }
}

