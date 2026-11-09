import 'package:equatable/equatable.dart';
import 'enums.dart';
import 'geometry_models.dart';

class FocusSpec extends Equatable {
  final double targetDistanceMm;
  final double? androidDiopters;
  final double? iosLensPosition;

  const FocusSpec({
    this.targetDistanceMm = 100.0,
    this.androidDiopters,
    this.iosLensPosition,
  });

  factory FocusSpec.fromJson(Map<String, dynamic> json) => FocusSpec(
        targetDistanceMm: (json['targetDistanceMm'] ?? json['target_distance_mm'] as num?)?.toDouble() ?? 100.0,
        androidDiopters: (json['androidDiopters'] ?? json['android_diopters'] as num?)?.toDouble(),
        iosLensPosition: (json['iosLensPosition'] ?? json['ios_lens_position'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'targetDistanceMm': targetDistanceMm,
        if (androidDiopters != null) 'androidDiopters': androidDiopters,
        if (iosLensPosition != null) 'iosLensPosition': iosLensPosition,
      };

  @override
  List<Object?> get props => [targetDistanceMm, androidDiopters, iosLensPosition];
}

class TorchSpec extends Equatable {
  final TorchMode mode;
  final double level;
  final TorchPolicy policy;
  final int preRollMs;

  const TorchSpec({
    this.mode = TorchMode.off,
    this.level = 1.0,
    this.policy = TorchPolicy.windowed,
    this.preRollMs = 2500,
  });

  factory TorchSpec.fromJson(Map<String, dynamic> json) => TorchSpec(
        mode: TorchMode.fromString(json['mode']),
        level: (json['level'] as num?)?.toDouble() ?? 1.0,
        policy: TorchPolicy.fromString(json['policy']),
        preRollMs: (json['preRollMs'] ?? json['pre_roll_ms'] as num?)?.toInt() ?? 2500,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.toWire(),
        'level': level,
        'policy': policy.toWire(),
        'preRollMs': preRollMs,
      };

  @override
  List<Object?> get props => [mode, level, policy, preRollMs];
}

class WbGains extends Equatable {
  final double r;
  final double gEven;
  final double gOdd;
  final double b;

  const WbGains({
    required this.r,
    required this.gEven,
    required this.gOdd,
    required this.b,
  });

  factory WbGains.fromJson(Map<String, dynamic> json) => WbGains(
        r: (json['r'] as num).toDouble(),
        gEven: (json['gEven'] ?? json['g_even'] as num).toDouble(),
        gOdd: (json['gOdd'] ?? json['g_odd'] as num).toDouble(),
        b: (json['b'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'r': r,
        'gEven': gEven,
        'gOdd': gOdd,
        'b': b,
      };

  @override
  List<Object?> get props => [r, gEven, gOdd, b];
}

class WhiteBalanceSpec extends Equatable {
  final WbGains? gains;
  final int kelvin;
  final int tint;

  const WhiteBalanceSpec({
    this.gains,
    this.kelvin = 5500,
    this.tint = 0,
  });

  factory WhiteBalanceSpec.fromJson(Map<String, dynamic> json) => WhiteBalanceSpec(
        gains: json['gains'] != null ? WbGains.fromJson(json['gains']) : null,
        kelvin: (json['kelvin'] as num?)?.toInt() ?? 5500,
        tint: (json['tint'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        if (gains != null) 'gains': gains!.toJson(),
        'kelvin': kelvin,
        'tint': tint,
      };

  @override
  List<Object?> get props => [gains, kelvin, tint];
}

class IspSpec extends Equatable {
  final String tonemap;
  final String noiseReduction;
  final String edgeMode;
  final String ois;
  final String videoStabilization;
  final String hdr;
  final double zoomRatio;

  const IspSpec({
    this.tonemap = 'srgbPreset',
    this.noiseReduction = 'minimal',
    this.edgeMode = 'off',
    this.ois = 'off',
    this.videoStabilization = 'off',
    this.hdr = 'off',
    this.zoomRatio = 1.0,
  });

  factory IspSpec.fromJson(Map<String, dynamic> json) => IspSpec(
        tonemap: json['tonemap'] ?? 'srgbPreset',
        noiseReduction: json['noiseReduction'] ?? json['noise_reduction'] ?? 'minimal',
        edgeMode: json['edgeMode'] ?? json['edge_mode'] ?? 'off',
        ois: json['ois'] ?? 'off',
        videoStabilization: json['videoStabilization'] ?? json['video_stabilization'] ?? 'off',
        hdr: json['hdr'] ?? 'off',
        zoomRatio: (json['zoomRatio'] ?? json['zoom_ratio'] as num?)?.toDouble() ?? 1.0,
      );

  Map<String, dynamic> toJson() => {
        'tonemap': tonemap,
        'noiseReduction': noiseReduction,
        'edgeMode': edgeMode,
        'ois': ois,
        'videoStabilization': videoStabilization,
        'hdr': hdr,
        'zoomRatio': zoomRatio,
      };

  @override
  List<Object?> get props => [
        tonemap,
        noiseReduction,
        edgeMode,
        ois,
        videoStabilization,
        hdr,
        zoomRatio,
      ];
}

class CameraHardwareConfig extends Equatable {
  final String cameraId;
  final int iso;
  final int exposureTimeNs;
  final int frameDurationNs;
  final FocusSpec focus;
  final TorchSpec torch;
  final WhiteBalanceSpec whiteBalance;
  final int mainsHz;
  final IspSpec isp;
  final SizeDto stillSize;
  final SizeDto previewAnalysisSize;

  const CameraHardwareConfig({
    required this.cameraId,
    this.iso = 50,
    this.exposureTimeNs = 10000000,
    this.frameDurationNs = 33333333,
    this.focus = const FocusSpec(),
    this.torch = const TorchSpec(),
    this.whiteBalance = const WhiteBalanceSpec(),
    this.mainsHz = 50,
    this.isp = const IspSpec(),
    required this.stillSize,
    required this.previewAnalysisSize,
  });

  factory CameraHardwareConfig.fromJson(Map<String, dynamic> json) => CameraHardwareConfig(
        cameraId: json['cameraId'] ?? json['camera_id'],
        iso: (json['iso'] as num?)?.toInt() ?? 50,
        exposureTimeNs: (json['exposureTimeNs'] ?? json['exposure_time_ns'] as num?)?.toInt() ?? 10000000,
        frameDurationNs: (json['frameDurationNs'] ?? json['frame_duration_ns'] as num?)?.toInt() ?? 33333333,
        focus: json['focus'] != null ? FocusSpec.fromJson(json['focus']) : const FocusSpec(),
        torch: json['torch'] != null ? TorchSpec.fromJson(json['torch']) : const TorchSpec(),
        whiteBalance: json['whiteBalance'] != null ? WhiteBalanceSpec.fromJson(json['whiteBalance']) : const WhiteBalanceSpec(),
        mainsHz: (json['mainsHz'] ?? json['mains_hz'] as num?)?.toInt() ?? 50,
        isp: json['isp'] != null ? IspSpec.fromJson(json['isp']) : const IspSpec(),
        stillSize: SizeDto.fromJson(json['stillSize'] ?? json['still_size']),
        previewAnalysisSize: SizeDto.fromJson(json['previewAnalysisSize'] ?? json['preview_analysis_size']),
      );

  Map<String, dynamic> toJson() => {
        'cameraId': cameraId,
        'iso': iso,
        'exposureTimeNs': exposureTimeNs,
        'frameDurationNs': frameDurationNs,
        'focus': focus.toJson(),
        'torch': torch.toJson(),
        'whiteBalance': whiteBalance.toJson(),
        'mainsHz': mainsHz,
        'isp': isp.toJson(),
        'stillSize': stillSize.toJson(),
        'previewAnalysisSize': previewAnalysisSize.toJson(),
      };

  @override
  List<Object?> get props => [
        cameraId,
        iso,
        exposureTimeNs,
        frameDurationNs,
        focus,
        torch,
        whiteBalance,
        mainsHz,
        isp,
        stillSize,
        previewAnalysisSize,
      ];
}

class ParamDeviation extends Equatable {
  final String param;
  final double requested;
  final double applied;
  final bool withinTolerance;

  const ParamDeviation({
    required this.param,
    required this.requested,
    required this.applied,
    required this.withinTolerance,
  });

  factory ParamDeviation.fromJson(Map<String, dynamic> json) => ParamDeviation(
        param: json['param'],
        requested: (json['requested'] as num).toDouble(),
        applied: (json['applied'] as num).toDouble(),
        withinTolerance: json['withinTolerance'] ?? json['within_tolerance'],
      );

  Map<String, dynamic> toJson() => {
        'param': param,
        'requested': requested,
        'applied': applied,
        'withinTolerance': withinTolerance,
      };

  @override
  List<Object?> get props => [param, requested, applied, withinTolerance];
}

class AppliedCameraState extends Equatable {
  final int iso;
  final int exposureTimeNs;
  final WbGains? whiteBalanceGains;
  final double? focusDistanceDiopters;
  final double? lensPosition;
  final double torchLevel;
  final bool awbLocked;
  final bool aeLocked;
  final int sensorTimestampNs;
  final bool verified;
  final List<ParamDeviation> deviations;

  const AppliedCameraState({
    required this.iso,
    required this.exposureTimeNs,
    this.whiteBalanceGains,
    this.focusDistanceDiopters,
    this.lensPosition,
    this.torchLevel = 1.0,
    this.awbLocked = true,
    this.aeLocked = true,
    required this.sensorTimestampNs,
    this.verified = true,
    this.deviations = const [],
  });

  factory AppliedCameraState.fromJson(Map<String, dynamic> json) => AppliedCameraState(
        iso: (json['iso'] as num).toInt(),
        exposureTimeNs: (json['exposureTimeNs'] ?? json['exposure_time_ns'] as num).toInt(),
        whiteBalanceGains: json['whiteBalanceGains'] != null ? WbGains.fromJson(json['whiteBalanceGains']) : null,
        focusDistanceDiopters: (json['focusDistanceDiopters'] ?? json['focus_distance_diopters'] as num?)?.toDouble(),
        lensPosition: (json['lensPosition'] ?? json['lens_position'] as num?)?.toDouble(),
        torchLevel: (json['torchLevel'] ?? json['torch_level'] as num?)?.toDouble() ?? 1.0,
        awbLocked: json['awbLocked'] ?? json['awb_locked'] ?? true,
        aeLocked: json['aeLocked'] ?? json['ae_locked'] ?? true,
        sensorTimestampNs: (json['sensorTimestampNs'] ?? json['sensor_timestamp_ns'] as num).toInt(),
        verified: json['verified'] ?? true,
        deviations: (json['deviations'] as List<dynamic>?)
                ?.map((e) => ParamDeviation.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'iso': iso,
        'exposureTimeNs': exposureTimeNs,
        if (whiteBalanceGains != null) 'whiteBalanceGains': whiteBalanceGains!.toJson(),
        if (focusDistanceDiopters != null) 'focusDistanceDiopters': focusDistanceDiopters,
        if (lensPosition != null) 'lensPosition': lensPosition,
        'torchLevel': torchLevel,
        'awbLocked': awbLocked,
        'aeLocked': aeLocked,
        'sensorTimestampNs': sensorTimestampNs,
        'verified': verified,
        'deviations': deviations.map((e) => e.toJson()).toList(),
      };

  @override
  List<Object?> get props => [
        iso,
        exposureTimeNs,
        whiteBalanceGains,
        focusDistanceDiopters,
        lensPosition,
        torchLevel,
        awbLocked,
        aeLocked,
        sensorTimestampNs,
        verified,
        deviations,
      ];
}

class CameraCapabilities extends Equatable {
  final bool hasManualSensor;
  final int isoMin;
  final int isoMax;
  final int exposureMinNs;
  final int exposureMaxNs;
  final double? minFocusDistanceMm;
  final bool hasTorch;
  final bool supportsWbGains;
  final List<SizeDto> supportedStillSizes;
  final String hardwareLevel;
  final List<String> physicalCameraIds;

  const CameraCapabilities({
    required this.hasManualSensor,
    required this.isoMin,
    required this.isoMax,
    required this.exposureMinNs,
    required this.exposureMaxNs,
    this.minFocusDistanceMm,
    required this.hasTorch,
    required this.supportsWbGains,
    this.supportedStillSizes = const [],
    this.hardwareLevel = 'FULL',
    this.physicalCameraIds = const [],
  });

  factory CameraCapabilities.fromJson(Map<String, dynamic> json) => CameraCapabilities(
        hasManualSensor: json['hasManualSensor'] ?? json['has_manual_sensor'],
        isoMin: (json['isoMin'] ?? json['iso_min'] as num).toInt(),
        isoMax: (json['isoMax'] ?? json['iso_max'] as num).toInt(),
        exposureMinNs: (json['exposureMinNs'] ?? json['exposure_min_ns'] as num).toInt(),
        exposureMaxNs: (json['exposureMaxNs'] ?? json['exposure_max_ns'] as num).toInt(),
        minFocusDistanceMm: (json['minFocusDistanceMm'] ?? json['min_focus_distance_mm'] as num?)?.toDouble(),
        hasTorch: json['hasTorch'] ?? json['has_torch'],
        supportsWbGains: json['supportsWbGains'] ?? json['supports_wb_gains'],
        supportedStillSizes: (json['supportedStillSizes'] as List<dynamic>?)
                ?.map((e) => SizeDto.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        hardwareLevel: json['hardwareLevel'] ?? json['hardware_level'] ?? 'FULL',
        physicalCameraIds: (json['physicalCameraIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      );

  Map<String, dynamic> toJson() => {
        'hasManualSensor': hasManualSensor,
        'isoMin': isoMin,
        'isoMax': isoMax,
        'exposureMinNs': exposureMinNs,
        'exposureMaxNs': exposureMaxNs,
        if (minFocusDistanceMm != null) 'minFocusDistanceMm': minFocusDistanceMm,
        'hasTorch': hasTorch,
        'supportsWbGains': supportsWbGains,
        'supportedStillSizes': supportedStillSizes.map((e) => e.toJson()).toList(),
        'hardwareLevel': hardwareLevel,
        'physicalCameraIds': physicalCameraIds,
      };

  @override
  List<Object?> get props => [
        hasManualSensor,
        isoMin,
        isoMax,
        exposureMinNs,
        exposureMaxNs,
        minFocusDistanceMm,
        hasTorch,
        supportsWbGains,
        supportedStillSizes,
        hardwareLevel,
        physicalCameraIds,
      ];
}

