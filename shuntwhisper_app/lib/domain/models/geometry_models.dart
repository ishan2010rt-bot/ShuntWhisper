import 'package:equatable/equatable.dart';

class SizeDto extends Equatable {
  final int widthPx;
  final int heightPx;

  const SizeDto({required this.widthPx, required this.heightPx});

  factory SizeDto.fromJson(Map<String, dynamic> json) => SizeDto(
        widthPx: (json['widthPx'] ?? json['width_px'] as num).toInt(),
        heightPx: (json['heightPx'] ?? json['height_px'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'widthPx': widthPx,
        'heightPx': heightPx,
      };

  @override
  List<Object?> get props => [widthPx, heightPx];
}

class PointDto extends Equatable {
  final double x;
  final double y;

  const PointDto({required this.x, required this.y});

  factory PointDto.fromJson(Map<String, dynamic> json) => PointDto(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  @override
  List<Object?> get props => [x, y];
}

class SizeMm extends Equatable {
  final double w;
  final double h;

  const SizeMm({required this.w, required this.h});

  factory SizeMm.fromJson(Map<String, dynamic> json) => SizeMm(
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'w': w, 'h': h};

  @override
  List<Object?> get props => [w, h];
}

class FiducialSpec extends Equatable {
  final int id;
  final PointDto centerMm;
  final double sideMm;

  const FiducialSpec({
    required this.id,
    required this.centerMm,
    required this.sideMm,
  });

  factory FiducialSpec.fromJson(Map<String, dynamic> json) => FiducialSpec(
        id: (json['id'] as num).toInt(),
        centerMm: PointDto.fromJson(json['centerMm'] ?? json['center_mm']),
        sideMm: (json['sideMm'] ?? json['side_mm'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'centerMm': centerMm.toJson(),
        'sideMm': sideMm,
      };

  @override
  List<Object?> get props => [id, centerMm, sideMm];
}

class PatchLayout extends Equatable {
  final PointDto upstreamCenterMm;
  final PointDto downstreamCenterMm;
  final PointDto lateralRefCenterMm;
  final PointDto apertureCenterMm;
  final SizeMm apertureSizeMm;
  final SizeMm roiSizeMm;
  final List<FiducialSpec> fiducials;

  const PatchLayout({
    required this.upstreamCenterMm,
    required this.downstreamCenterMm,
    required this.lateralRefCenterMm,
    required this.apertureCenterMm,
    required this.apertureSizeMm,
    required this.roiSizeMm,
    required this.fiducials,
  });

  factory PatchLayout.fromJson(Map<String, dynamic> json) => PatchLayout(
        upstreamCenterMm: PointDto.fromJson(json['upstreamCenterMm'] ?? json['upstream_center_mm']),
        downstreamCenterMm: PointDto.fromJson(json['downstreamCenterMm'] ?? json['downstream_center_mm']),
        lateralRefCenterMm: PointDto.fromJson(json['lateralRefCenterMm'] ?? json['lateral_ref_center_mm']),
        apertureCenterMm: PointDto.fromJson(json['apertureCenterMm'] ?? json['aperture_center_mm']),
        apertureSizeMm: SizeMm.fromJson(json['apertureSizeMm'] ?? json['aperture_size_mm']),
        roiSizeMm: SizeMm.fromJson(json['roiSizeMm'] ?? json['roi_size_mm']),
        fiducials: (json['fiducials'] as List<dynamic>)
            .map((e) => FiducialSpec.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'upstreamCenterMm': upstreamCenterMm.toJson(),
        'downstreamCenterMm': downstreamCenterMm.toJson(),
        'lateralRefCenterMm': lateralRefCenterMm.toJson(),
        'apertureCenterMm': apertureCenterMm.toJson(),
        'apertureSizeMm': apertureSizeMm.toJson(),
        'roiSizeMm': roiSizeMm.toJson(),
        'fiducials': fiducials.map((e) => e.toJson()).toList(),
      };

  @override
  List<Object?> get props => [
        upstreamCenterMm,
        downstreamCenterMm,
        lateralRefCenterMm,
        apertureCenterMm,
        apertureSizeMm,
        roiSizeMm,
        fiducials,
      ];
}
