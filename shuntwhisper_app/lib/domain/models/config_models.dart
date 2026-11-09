import 'package:equatable/equatable.dart';
import 'camera_models.dart';
import 'geometry_models.dart';

class RemoteConfig extends Equatable {
  final Map<String, dynamic> sessionPolicy;
  final Map<String, double> alignmentThresholds;
  final Map<String, double> validatorThresholds;
  final PatchLayout patchLayout;
  final Map<String, bool> featureFlags;
  final int deviceProfileVersion;

  const RemoteConfig({
    this.sessionPolicy = const {},
    this.alignmentThresholds = const {},
    this.validatorThresholds = const {},
    required this.patchLayout,
    this.featureFlags = const {},
    this.deviceProfileVersion = 1,
  });

  factory RemoteConfig.fromJson(Map<String, dynamic> json) => RemoteConfig(
        sessionPolicy: json['sessionPolicy'] ?? json['session_policy'] ?? const {},
        alignmentThresholds: (json['alignmentThresholds'] ?? json['alignment_thresholds'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
            const {},
        validatorThresholds: (json['validatorThresholds'] ?? json['validator_thresholds'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
            const {},
        patchLayout: PatchLayout.fromJson(json['patchLayout'] ?? json['patch_layout']),
        featureFlags: (json['featureFlags'] ?? json['feature_flags'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as bool)) ??
            const {},
        deviceProfileVersion: (json['deviceProfileVersion'] ?? json['device_profile_version'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'sessionPolicy': sessionPolicy,
        'alignmentThresholds': alignmentThresholds,
        'validatorThresholds': validatorThresholds,
        'patchLayout': patchLayout.toJson(),
        'featureFlags': featureFlags,
        'deviceProfileVersion': deviceProfileVersion,
      };

  @override
  List<Object?> get props => [
        sessionPolicy,
        alignmentThresholds,
        validatorThresholds,
        patchLayout,
        featureFlags,
        deviceProfileVersion,
      ];
}

class DeviceProfile extends Equatable {
  final String platform;
  final String model;
  final String cameraId;
  final SizeDto previewAnalysisSize;
  final SizeDto stillSize;
  final double targetDistanceMm;
  final double? androidFocusDiopters;
  final double? iosLensPosition;
  final WbGains? neutralWbGains;
  final List<Intrinsics> intrinsicsByStill;
  final int version;

  const DeviceProfile({
    required this.platform,
    required this.model,
    required this.cameraId,
    required this.previewAnalysisSize,
    required this.stillSize,
    this.targetDistanceMm = 100.0,
    this.androidFocusDiopters,
    this.iosLensPosition,
    this.neutralWbGains,
    this.intrinsicsByStill = const [],
    this.version = 1,
  });

  factory DeviceProfile.fromJson(Map<String, dynamic> json) => DeviceProfile(
        platform: json['platform'],
        model: json['model'],
        cameraId: json['cameraId'] ?? json['camera_id'],
        previewAnalysisSize: SizeDto.fromJson(json['previewAnalysisSize'] ?? json['preview_analysis_size']),
        stillSize: SizeDto.fromJson(json['stillSize'] ?? json['still_size']),
        targetDistanceMm: (json['targetDistanceMm'] ?? json['target_distance_mm'] as num?)?.toDouble() ?? 100.0,
        androidFocusDiopters: (json['androidFocusDiopters'] ?? json['android_focus_diopters'] as num?)?.toDouble(),
        iosLensPosition: (json['iosLensPosition'] ?? json['ios_lens_position'] as num?)?.toDouble(),
        neutralWbGains: json['neutralWbGains'] != null || json['neutral_wb_gains'] != null
            ? WbGains.fromJson(json['neutralWbGains'] ?? json['neutral_wb_gains'])
            : null,
        intrinsicsByStill: (json['intrinsicsByStill'] ?? json['intrinsics_by_still'] as List<dynamic>?)
                ?.map((e) => Intrinsics.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        version: (json['version'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'model': model,
        'cameraId': cameraId,
        'previewAnalysisSize': previewAnalysisSize.toJson(),
        'stillSize': stillSize.toJson(),
        'targetDistanceMm': targetDistanceMm,
        if (androidFocusDiopters != null) 'androidFocusDiopters': androidFocusDiopters,
        if (iosLensPosition != null) 'iosLensPosition': iosLensPosition,
        if (neutralWbGains != null) 'neutralWbGains': neutralWbGains!.toJson(),
        'intrinsicsByStill': intrinsicsByStill.map((e) => e.toJson()).toList(),
        'version': version,
      };

  @override
  List<Object?> get props => [
        platform,
        model,
        cameraId,
        previewAnalysisSize,
        stillSize,
        targetDistanceMm,
        androidFocusDiopters,
        iosLensPosition,
        neutralWbGains,
        intrinsicsByStill,
        version,
      ];
}

