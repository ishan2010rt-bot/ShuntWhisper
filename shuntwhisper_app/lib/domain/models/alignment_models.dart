import 'package:equatable/equatable.dart';
import 'enums.dart';
import 'geometry_models.dart';

class FiducialAlignmentState extends Equatable {
  final int frameSeq;
  final int timestampNs;
  final SizeDto analysisSize;
  final int markersDetected;
  final List<PointDto?> markerCentersPx;
  final List<double>? canonToImageH;
  final Map<String, List<PointDto>> roiQuadsPx;
  final double? pitchDeg;
  final double? yawDeg;
  final double? rollDeg;
  final double? distanceMm;
  final PointDto? lateralOffsetMm;
  final double? centerOffsetFrac;
  final double? sharpness;
  final double stabilityScore;
  final int consecutiveAlignedFrames;
  final int alignedForMs;
  final AlignmentStatus status;
  final List<AlignmentViolation> violations;

  const FiducialAlignmentState({
    this.frameSeq = 0,
    this.timestampNs = 0,
    required this.analysisSize,
    required this.markersDetected,
    this.markerCentersPx = const [],
    this.canonToImageH,
    this.roiQuadsPx = const {},
    this.pitchDeg,
    this.yawDeg,
    this.rollDeg,
    this.distanceMm,
    this.lateralOffsetMm,
    this.centerOffsetFrac,
    this.sharpness,
    this.stabilityScore = 1.0,
    this.consecutiveAlignedFrames = 0,
    this.alignedForMs = 0,
    this.status = AlignmentStatus.misaligned,
    this.violations = const [],
  });

  factory FiducialAlignmentState.fromJson(Map<String, dynamic> json) {
    Map<String, List<PointDto>> rois = {};
    final rawRois = json['roiQuadsPx'] ?? json['roi_quads_px'];
    if (rawRois is Map<String, dynamic>) {
      for (final entry in rawRois.entries) {
        rois[entry.key] = (entry.value as List<dynamic>)
            .map((p) => PointDto.fromJson(p as Map<String, dynamic>))
            .toList();
      }
    }

    return FiducialAlignmentState(
      frameSeq: (json['frameSeq'] ?? json['frame_seq'] as num?)?.toInt() ?? 0,
      timestampNs: (json['timestampNs'] ?? json['timestamp_ns'] as num?)?.toInt() ?? 0,
      analysisSize: SizeDto.fromJson(json['analysisSize'] ?? json['analysis_size']),
      markersDetected: (json['markersDetected'] ?? json['markers_detected'] as num).toInt(),
      markerCentersPx: (json['markerCentersPx'] ?? json['marker_centers_px'] as List<dynamic>?)
              ?.map((e) => e != null ? PointDto.fromJson(e as Map<String, dynamic>) : null)
              .toList() ??
          const [],
      canonToImageH: (json['canonToImageH'] ?? json['canon_to_image_h'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
      roiQuadsPx: rois,
      pitchDeg: (json['pitchDeg'] ?? json['pitch_deg'] as num?)?.toDouble(),
      yawDeg: (json['yawDeg'] ?? json['yaw_deg'] as num?)?.toDouble(),
      rollDeg: (json['rollDeg'] ?? json['roll_deg'] as num?)?.toDouble(),
      distanceMm: (json['distanceMm'] ?? json['distance_mm'] as num?)?.toDouble(),
      lateralOffsetMm: json['lateralOffsetMm'] != null || json['lateral_offset_mm'] != null
          ? PointDto.fromJson(json['lateralOffsetMm'] ?? json['lateral_offset_mm'])
          : null,
      centerOffsetFrac: (json['centerOffsetFrac'] ?? json['center_offset_frac'] as num?)?.toDouble(),
      sharpness: (json['sharpness'] as num?)?.toDouble(),
      stabilityScore: (json['stabilityScore'] ?? json['stability_score'] as num?)?.toDouble() ?? 1.0,
      consecutiveAlignedFrames:
          (json['consecutiveAlignedFrames'] ?? json['consecutive_aligned_frames'] as num?)?.toInt() ?? 0,
      alignedForMs: (json['alignedForMs'] ?? json['aligned_for_ms'] as num?)?.toInt() ?? 0,
      status: AlignmentStatus.fromString(json['status']),
      violations: (json['violations'] as List<dynamic>?)
              ?.map((e) => AlignmentViolation.fromString(e.toString()))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'frameSeq': frameSeq,
        'timestampNs': timestampNs,
        'analysisSize': analysisSize.toJson(),
        'markersDetected': markersDetected,
        'markerCentersPx': markerCentersPx.map((e) => e?.toJson()).toList(),
        if (canonToImageH != null) 'canonToImageH': canonToImageH,
        'roiQuadsPx': roiQuadsPx.map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList())),
        if (pitchDeg != null) 'pitchDeg': pitchDeg,
        if (yawDeg != null) 'yawDeg': yawDeg,
        if (rollDeg != null) 'rollDeg': rollDeg,
        if (distanceMm != null) 'distanceMm': distanceMm,
        if (lateralOffsetMm != null) 'lateralOffsetMm': lateralOffsetMm!.toJson(),
        if (centerOffsetFrac != null) 'centerOffsetFrac': centerOffsetFrac,
        if (sharpness != null) 'sharpness': sharpness,
        'stabilityScore': stabilityScore,
        'consecutiveAlignedFrames': consecutiveAlignedFrames,
        'alignedForMs': alignedForMs,
        'status': status.toWire(),
        'violations': violations.map((e) => e.toWire()).toList(),
      };

  @override
  List<Object?> get props => [
        frameSeq,
        timestampNs,
        analysisSize,
        markersDetected,
        markerCentersPx,
        canonToImageH,
        roiQuadsPx,
        pitchDeg,
        yawDeg,
        rollDeg,
        distanceMm,
        lateralOffsetMm,
        centerOffsetFrac,
        sharpness,
        stabilityScore,
        consecutiveAlignedFrames,
        alignedForMs,
        status,
        violations,
      ];
}

class FrameValidationResult extends Equatable {
  final bool passed;
  final double sharpness;
  final double whiteLevel;
  final double whiteClipFrac;
  final Map<String, double> specularFracByRoi;
  final int markersDetected;
  final double? regRmsPx;
  final List<String> failures;

  const FrameValidationResult({
    required this.passed,
    required this.sharpness,
    required this.whiteLevel,
    required this.whiteClipFrac,
    this.specularFracByRoi = const {},
    this.markersDetected = 4,
    this.regRmsPx,
    this.failures = const [],
  });

  factory FrameValidationResult.fromJson(Map<String, dynamic> json) => FrameValidationResult(
        passed: json['passed'],
        sharpness: (json['sharpness'] as num).toDouble(),
        whiteLevel: (json['whiteLevel'] ?? json['white_level'] as num).toDouble(),
        whiteClipFrac: (json['whiteClipFrac'] ?? json['white_clip_frac'] as num).toDouble(),
        specularFracByRoi: (json['specularFracByRoi'] ?? json['specular_frac_by_roi'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
            const {},
        markersDetected: (json['markersDetected'] ?? json['markers_detected'] as num?)?.toInt() ?? 4,
        regRmsPx: (json['regRmsPx'] ?? json['reg_rms_px'] as num?)?.toDouble(),
        failures: (json['failures'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'passed': passed,
        'sharpness': sharpness,
        'whiteLevel': whiteLevel,
        'whiteClipFrac': whiteClipFrac,
        'specularFracByRoi': specularFracByRoi,
        'markersDetected': markersDetected,
        if (regRmsPx != null) 'regRmsPx': regRmsPx,
        'failures': failures,
      };

  @override
  List<Object?> get props => [
        passed,
        sharpness,
        whiteLevel,
        whiteClipFrac,
        specularFracByRoi,
        markersDetected,
        regRmsPx,
        failures,
      ];
}

