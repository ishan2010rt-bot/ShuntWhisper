/// Enums for ShuntWhisper Mobile Client matching Section B of Master Blueprint.

enum AlignmentStatus {
  aligned,
  misaligned,
  unstable,
  notDetected,
  unknown;

  static AlignmentStatus fromString(String? val) => switch (val) {
        'ALIGNED' => AlignmentStatus.aligned,
        'MISALIGNED' => AlignmentStatus.misaligned,
        'UNSTABLE' => AlignmentStatus.unstable,
        'NOT_DETECTED' => AlignmentStatus.notDetected,
        _ => AlignmentStatus.unknown,
      };

  String toWire() => switch (this) {
        AlignmentStatus.aligned => 'ALIGNED',
        AlignmentStatus.misaligned => 'MISALIGNED',
        AlignmentStatus.unstable => 'UNSTABLE',
        AlignmentStatus.notDetected => 'NOT_DETECTED',
        AlignmentStatus.unknown => 'UNKNOWN',
      };
}

enum AlignmentViolation {
  tooFar,
  tooClose,
  pitch,
  yaw,
  roll,
  offCenter,
  lateralOffset,
  nearFrameEdge,
  blur,
  glare,
  underExposed,
  unknown;

  static AlignmentViolation fromString(String? val) => switch (val) {
        'TOO_FAR' => AlignmentViolation.tooFar,
        'TOO_CLOSE' => AlignmentViolation.tooClose,
        'PITCH' => AlignmentViolation.pitch,
        'YAW' => AlignmentViolation.yaw,
        'ROLL' => AlignmentViolation.roll,
        'OFF_CENTER' => AlignmentViolation.offCenter,
        'LATERAL_OFFSET' => AlignmentViolation.lateralOffset,
        'NEAR_FRAME_EDGE' => AlignmentViolation.nearFrameEdge,
        'BLUR' => AlignmentViolation.blur,
        'GLARE' => AlignmentViolation.glare,
        'UNDER_EXPOSED' => AlignmentViolation.underExposed,
        _ => AlignmentViolation.unknown,
      };

  String toWire() => switch (this) {
        AlignmentViolation.tooFar => 'TOO_FAR',
        AlignmentViolation.tooClose => 'TOO_CLOSE',
        AlignmentViolation.pitch => 'PITCH',
        AlignmentViolation.yaw => 'YAW',
        AlignmentViolation.roll => 'ROLL',
        AlignmentViolation.offCenter => 'OFF_CENTER',
        AlignmentViolation.lateralOffset => 'LATERAL_OFFSET',
        AlignmentViolation.nearFrameEdge => 'NEAR_FRAME_EDGE',
        AlignmentViolation.blur => 'BLUR',
        AlignmentViolation.glare => 'GLARE',
        AlignmentViolation.underExposed => 'UNDER_EXPOSED',
        AlignmentViolation.unknown => 'UNKNOWN',
      };
}

enum Classification {
  patentHigh,
  patentMarginal,
  occluded,
  inconclusive,
  unknown;

  static Classification fromString(String? val) => switch (val) {
        'PATENT_HIGH' => Classification.patentHigh,
        'PATENT_MARGINAL' => Classification.patentMarginal,
        'OCCLUDED' => Classification.occluded,
        'INCONCLUSIVE' => Classification.inconclusive,
        _ => Classification.unknown,
      };

  String toWire() => switch (this) {
        Classification.patentHigh => 'PATENT_HIGH',
        Classification.patentMarginal => 'PATENT_MARGINAL',
        Classification.occluded => 'OCCLUDED',
        Classification.inconclusive => 'INCONCLUSIVE',
        Classification.unknown => 'UNKNOWN',
      };

  String get clinicalDescription => switch (this) {
        Classification.patentHigh => 'Flow signature present',
        Classification.patentMarginal => 'Weak flow signature',
        Classification.occluded => 'Possible blockage — seek clinical evaluation',
        Classification.inconclusive => 'Test could not be interpreted',
        Classification.unknown => 'Pending verification',
      };
}

enum InconclusiveReason {
  insufficientHydration,
  outOfRangeWarm,
  outOfRangeCold,
  qcMotionBlur,
  qcRegistration,
  qcExposure,
  qcColorFit,
  qcIllumination,
  specularRoi,
  reverseGradient,
  lowSnr,
  sinkUnverifiable,
  other,
  unknown;

  static InconclusiveReason fromString(String? val) => switch (val) {
        'INSUFFICIENT_HYDRATION' => InconclusiveReason.insufficientHydration,
        'OUT_OF_RANGE_WARM' => InconclusiveReason.outOfRangeWarm,
        'OUT_OF_RANGE_COLD' => InconclusiveReason.outOfRangeCold,
        'QC_MOTION_BLUR' => InconclusiveReason.qcMotionBlur,
        'QC_REGISTRATION' => InconclusiveReason.qcRegistration,
        'QC_EXPOSURE' => InconclusiveReason.qcExposure,
        'QC_COLOR_FIT' => InconclusiveReason.qcColorFit,
        'QC_ILLUMINATION' => InconclusiveReason.qcIllumination,
        'SPECULAR_ROI' => InconclusiveReason.specularRoi,
        'REVERSE_GRADIENT' => InconclusiveReason.reverseGradient,
        'LOW_SNR' => InconclusiveReason.lowSnr,
        'SINK_UNVERIFIABLE' => InconclusiveReason.sinkUnverifiable,
        'OTHER' => InconclusiveReason.other,
        _ => InconclusiveReason.unknown,
      };

  String toWire() => switch (this) {
        InconclusiveReason.insufficientHydration => 'INSUFFICIENT_HYDRATION',
        InconclusiveReason.outOfRangeWarm => 'OUT_OF_RANGE_WARM',
        InconclusiveReason.outOfRangeCold => 'OUT_OF_RANGE_COLD',
        InconclusiveReason.qcMotionBlur => 'QC_MOTION_BLUR',
        InconclusiveReason.qcRegistration => 'QC_REGISTRATION',
        InconclusiveReason.qcExposure => 'QC_EXPOSURE',
        InconclusiveReason.qcColorFit => 'QC_COLOR_FIT',
        InconclusiveReason.qcIllumination => 'QC_ILLUMINATION',
        InconclusiveReason.specularRoi => 'SPECULAR_ROI',
        InconclusiveReason.reverseGradient => 'REVERSE_GRADIENT',
        InconclusiveReason.lowSnr => 'LOW_SNR',
        InconclusiveReason.sinkUnverifiable => 'SINK_UNVERIFIABLE',
        InconclusiveReason.other => 'OTHER',
        InconclusiveReason.unknown => 'UNKNOWN',
      };
}

enum TorchMode {
  off,
  on,
  unknown;

  static TorchMode fromString(String? val) => switch (val) {
        'OFF' => TorchMode.off,
        'ON' => TorchMode.on,
        _ => TorchMode.unknown,
      };

  String toWire() => switch (this) {
        TorchMode.off => 'OFF',
        TorchMode.on => 'ON',
        TorchMode.unknown => 'UNKNOWN',
      };
}

enum TorchPolicy {
  alwaysOn,
  windowed,
  unknown;

  static TorchPolicy fromString(String? val) => switch (val) {
        'always_on' => TorchPolicy.alwaysOn,
        'windowed' => TorchPolicy.windowed,
        _ => TorchPolicy.unknown,
      };

  String toWire() => switch (this) {
        TorchPolicy.alwaysOn => 'always_on',
        TorchPolicy.windowed => 'windowed',
        TorchPolicy.unknown => 'unknown',
      };
}

enum DoseDetection {
  manualTap,
  autoFoam,
  unknown;

  static DoseDetection fromString(String? val) => switch (val) {
        'manual_tap' => DoseDetection.manualTap,
        'auto_foam' => DoseDetection.autoFoam,
        _ => DoseDetection.unknown,
      };

  String toWire() => switch (this) {
        DoseDetection.manualTap => 'manual_tap',
        DoseDetection.autoFoam => 'auto_foam',
        DoseDetection.unknown => 'unknown',
      };
}

enum AmbientSource {
  manual,
  sensor,
  ble,
  unknown;

  static AmbientSource fromString(String? val) => switch (val) {
        'manual' => AmbientSource.manual,
        'sensor' => AmbientSource.sensor,
        'ble' => AmbientSource.ble,
        _ => AmbientSource.unknown,
      };

  String toWire() => switch (this) {
        AmbientSource.manual => 'manual',
        AmbientSource.sensor => 'sensor',
        AmbientSource.ble => 'ble',
        AmbientSource.unknown => 'unknown',
      };
}

enum IntrinsicsSource {
  cameraCharacteristics,
  profile,
  estimated,
  unknown;

  static IntrinsicsSource fromString(String? val) => switch (val) {
        'camera_characteristics' => IntrinsicsSource.cameraCharacteristics,
        'profile' => IntrinsicsSource.profile,
        'estimated' => IntrinsicsSource.estimated,
        _ => IntrinsicsSource.unknown,
      };

  String toWire() => switch (this) {
        IntrinsicsSource.cameraCharacteristics => 'camera_characteristics',
        IntrinsicsSource.profile => 'profile',
        IntrinsicsSource.estimated => 'estimated',
        IntrinsicsSource.unknown => 'unknown',
      };
}

enum RoiVisualKind {
  crop,
  overlay,
  normalized,
  specMask,
  unknown;

  static RoiVisualKind fromString(String? val) => switch (val) {
        'crop' => RoiVisualKind.crop,
        'overlay' => RoiVisualKind.overlay,
        'normalized' => RoiVisualKind.normalized,
        'spec_mask' => RoiVisualKind.specMask,
        _ => RoiVisualKind.unknown,
      };

  String toWire() => switch (this) {
        RoiVisualKind.crop => 'crop',
        RoiVisualKind.overlay => 'overlay',
        RoiVisualKind.normalized => 'normalized',
        RoiVisualKind.specMask => 'spec_mask',
        RoiVisualKind.unknown => 'unknown',
      };
}

