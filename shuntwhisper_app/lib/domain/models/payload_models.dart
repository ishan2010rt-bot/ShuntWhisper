import 'package:equatable/equatable.dart';
import 'enums.dart';
import 'camera_models.dart';
import 'alignment_models.dart';

class AmbientMetadata extends Equatable {
  final double temperatureC;
  final double relativeHumidityPct;
  final AmbientSource source;
  final DateTime measuredAtUtc;

  const AmbientMetadata({
    required this.temperatureC,
    required this.relativeHumidityPct,
    this.source = AmbientSource.manual,
    required this.measuredAtUtc,
  });

  factory AmbientMetadata.fromJson(Map<String, dynamic> json) => AmbientMetadata(
        temperatureC: (json['temperatureC'] ?? json['temperature_c'] as num).toDouble(),
        relativeHumidityPct: (json['relativeHumidityPct'] ?? json['relative_humidity_pct'] as num).toDouble(),
        source: AmbientSource.fromString(json['source']),
        measuredAtUtc: DateTime.parse(json['measuredAtUtc'] ?? json['measured_at_utc']),
      );

  Map<String, dynamic> toJson() => {
        'temperatureC': temperatureC,
        'relativeHumidityPct': relativeHumidityPct,
        'source': source.toWire(),
        'measuredAtUtc': measuredAtUtc.toUtc().toIso8601String(),
      };

  @override
  List<Object?> get props => [temperatureC, relativeHumidityPct, source, measuredAtUtc];
}

class DosingRecord extends Equatable {
  final double volumeUl;
  final int tZeroMonotonicNs;
  final DateTime tZeroUtc;
  final DoseDetection detection;
  final bool outOfSpec;

  const DosingRecord({
    this.volumeUl = 70.0,
    required this.tZeroMonotonicNs,
    required this.tZeroUtc,
    this.detection = DoseDetection.manualTap,
    this.outOfSpec = false,
  });

  factory DosingRecord.fromJson(Map<String, dynamic> json) => DosingRecord(
        volumeUl: (json['volumeUl'] ?? json['volume_ul'] as num?)?.toDouble() ?? 70.0,
        tZeroMonotonicNs: (json['tZeroMonotonicNs'] ?? json['t_zero_monotonic_ns'] as num).toInt(),
        tZeroUtc: DateTime.parse(json['tZeroUtc'] ?? json['t_zero_utc']),
        detection: DoseDetection.fromString(json['detection']),
        outOfSpec: json['outOfSpec'] ?? json['out_of_spec'] ?? false,
      );

  Map<String, dynamic> toJson() => {
        'volumeUl': volumeUl,
        'tZeroMonotonicNs': tZeroMonotonicNs,
        'tZeroUtc': tZeroUtc.toUtc().toIso8601String(),
        'detection': detection.toWire(),
        'outOfSpec': outOfSpec,
      };

  @override
  List<Object?> get props => [volumeUl, tZeroMonotonicNs, tZeroUtc, detection, outOfSpec];
}

class Intrinsics extends Equatable {
  final double fx;
  final double fy;
  final double cx;
  final double cy;
  final int imageW;
  final int imageH;
  final IntrinsicsSource source;

  const Intrinsics({
    required this.fx,
    required this.fy,
    required this.cx,
    required this.cy,
    required this.imageW,
    required this.imageH,
    this.source = IntrinsicsSource.profile,
  });

  factory Intrinsics.fromJson(Map<String, dynamic> json) => Intrinsics(
        fx: (json['fx'] as num).toDouble(),
        fy: (json['fy'] as num).toDouble(),
        cx: (json['cx'] as num).toDouble(),
        cy: (json['cy'] as num).toDouble(),
        imageW: (json['imageW'] ?? json['image_w'] as num).toInt(),
        imageH: (json['imageH'] ?? json['image_h'] as num).toInt(),
        source: IntrinsicsSource.fromString(json['source']),
      );

  Map<String, dynamic> toJson() => {
        'fx': fx,
        'fy': fy,
        'cx': cx,
        'cy': cy,
        'imageW': imageW,
        'imageH': imageH,
        'source': source.toWire(),
      };

  @override
  List<Object?> get props => [fx, fy, cx, cy, imageW, imageH, source];
}

class CapturedImageMeta extends Equatable {
  final String part;
  final double tNominalS;
  final double tActualS;
  final String mime;
  final String encoding;
  final int? jpegQuality;
  final int widthPx;
  final int heightPx;
  final int sizeBytes;
  final String sha256;
  final AppliedCameraState appliedCamera;
  final FiducialAlignmentState alignmentAtCapture;
  final FrameValidationResult validation;
  final Intrinsics intrinsics;
  final int burstIndex;
  final int burstSize;

  const CapturedImageMeta({
    required this.part,
    required this.tNominalS,
    required this.tActualS,
    this.mime = 'image/png',
    this.encoding = 'raw',
    this.jpegQuality,
    required this.widthPx,
    required this.heightPx,
    required this.sizeBytes,
    required this.sha256,
    required this.appliedCamera,
    required this.alignmentAtCapture,
    required this.validation,
    required this.intrinsics,
    this.burstIndex = 0,
    this.burstSize = 3,
  });

  factory CapturedImageMeta.fromJson(Map<String, dynamic> json) => CapturedImageMeta(
        part: json['part'],
        tNominalS: (json['tNominalS'] ?? json['t_nominal_s'] as num).toDouble(),
        tActualS: (json['tActualS'] ?? json['t_actual_s'] as num).toDouble(),
        mime: json['mime'] ?? 'image/png',
        encoding: json['encoding'] ?? 'raw',
        jpegQuality: (json['jpegQuality'] ?? json['jpeg_quality'] as num?)?.toInt(),
        widthPx: (json['widthPx'] ?? json['width_px'] as num).toInt(),
        heightPx: (json['heightPx'] ?? json['height_px'] as num).toInt(),
        sizeBytes: (json['sizeBytes'] ?? json['size_bytes'] as num).toInt(),
        sha256: json['sha256'],
        appliedCamera: AppliedCameraState.fromJson(json['appliedCamera'] ?? json['applied_camera']),
        alignmentAtCapture: FiducialAlignmentState.fromJson(json['alignmentAtCapture'] ?? json['alignment_at_capture']),
        validation: FrameValidationResult.fromJson(json['validation']),
        intrinsics: Intrinsics.fromJson(json['intrinsics']),
        burstIndex: (json['burstIndex'] ?? json['burst_index'] as num?)?.toInt() ?? 0,
        burstSize: (json['burstSize'] ?? json['burst_size'] as num?)?.toInt() ?? 3,
      );

  Map<String, dynamic> toJson() => {
        'part': part,
        'tNominalS': tNominalS,
        'tActualS': tActualS,
        'mime': mime,
        'encoding': encoding,
        if (jpegQuality != null) 'jpegQuality': jpegQuality,
        'widthPx': widthPx,
        'heightPx': heightPx,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
        'appliedCamera': appliedCamera.toJson(),
        'alignmentAtCapture': alignmentAtCapture.toJson(),
        'validation': validation.toJson(),
        'intrinsics': intrinsics.toJson(),
        'burstIndex': burstIndex,
        'burstSize': burstSize,
      };

  @override
  List<Object?> get props => [
        part,
        tNominalS,
        tActualS,
        mime,
        encoding,
        jpegQuality,
        widthPx,
        heightPx,
        sizeBytes,
        sha256,
        appliedCamera,
        alignmentAtCapture,
        validation,
        intrinsics,
        burstIndex,
        burstSize,
      ];
}

class AppInfo extends Equatable {
  final String version;
  final String build;
  final String platform;
  final String osVersion;

  const AppInfo({
    required this.version,
    required this.build,
    required this.platform,
    required this.osVersion,
  });

  factory AppInfo.fromJson(Map<String, dynamic> json) => AppInfo(
        version: json['version'],
        build: json['build'],
        platform: json['platform'],
        osVersion: json['osVersion'] ?? json['os_version'],
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'build': build,
        'platform': platform,
        'osVersion': osVersion,
      };

  @override
  List<Object?> get props => [version, build, platform, osVersion];
}

class DeviceInfo extends Equatable {
  final String model;
  final String cameraId;
  final String hardwareLevel;
  final int profileVersion;

  const DeviceInfo({
    required this.model,
    required this.cameraId,
    this.hardwareLevel = 'FULL',
    this.profileVersion = 1,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        model: json['model'],
        cameraId: json['cameraId'] ?? json['camera_id'],
        hardwareLevel: json['hardwareLevel'] ?? json['hardware_level'] ?? 'FULL',
        profileVersion: (json['profileVersion'] ?? json['profile_version'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'model': model,
        'cameraId': cameraId,
        'hardwareLevel': hardwareLevel,
        'profileVersion': profileVersion,
      };

  @override
  List<Object?> get props => [model, cameraId, hardwareLevel, profileVersion];
}

class CapturePayload extends Equatable {
  final String sessionId;
  final int schemaVersion;
  final DateTime createdAtUtc;
  final String? subjectRef;
  final AppInfo app;
  final DeviceInfo device;
  final String calibrationId;
  final String? patchLotId;
  final String? patchSerial;
  final AmbientMetadata ambient;
  final DosingRecord dosing;
  final List<CapturedImageMeta> images;
  final List<String> flags;
  final Map<String, dynamic> policySnapshot;

  const CapturePayload({
    required this.sessionId,
    this.schemaVersion = 1,
    required this.createdAtUtc,
    this.subjectRef,
    required this.app,
    required this.device,
    required this.calibrationId,
    this.patchLotId,
    this.patchSerial,
    required this.ambient,
    required this.dosing,
    this.images = const [],
    this.flags = const [],
    this.policySnapshot = const {},
  });

  factory CapturePayload.fromJson(Map<String, dynamic> json) => CapturePayload(
        sessionId: json['sessionId'] ?? json['session_id'],
        schemaVersion: (json['schemaVersion'] ?? json['schema_version'] as num?)?.toInt() ?? 1,
        createdAtUtc: DateTime.parse(json['createdAtUtc'] ?? json['created_at_utc']),
        subjectRef: json['subjectRef'] ?? json['subject_ref'],
        app: AppInfo.fromJson(json['app']),
        device: DeviceInfo.fromJson(json['device']),
        calibrationId: json['calibrationId'] ?? json['calibration_id'],
        patchLotId: json['patchLotId'] ?? json['patch_lot_id'],
        patchSerial: json['patchSerial'] ?? json['patch_serial'],
        ambient: AmbientMetadata.fromJson(json['ambient']),
        dosing: DosingRecord.fromJson(json['dosing']),
        images: (json['images'] as List<dynamic>?)
                ?.map((e) => CapturedImageMeta.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        flags: (json['flags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
        policySnapshot: json['policySnapshot'] ?? json['policy_snapshot'] ?? const {},
      );

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'schemaVersion': schemaVersion,
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        if (subjectRef != null) 'subjectRef': subjectRef,
        'app': app.toJson(),
        'device': device.toJson(),
        'calibrationId': calibrationId,
        if (patchLotId != null) 'patchLotId': patchLotId,
        if (patchSerial != null) 'patchSerial': patchSerial,
        'ambient': ambient.toJson(),
        'dosing': dosing.toJson(),
        'images': images.map((e) => e.toJson()).toList(),
        'flags': flags,
        'policySnapshot': policySnapshot,
      };

  @override
  List<Object?> get props => [
        sessionId,
        schemaVersion,
        createdAtUtc,
        subjectRef,
        app,
        device,
        calibrationId,
        patchLotId,
        patchSerial,
        ambient,
        dosing,
        images,
        flags,
        policySnapshot,
      ];
}

