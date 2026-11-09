import 'package:equatable/equatable.dart';
import 'enums.dart';

class Measured extends Equatable {
  final double value;
  final double sigma;
  final double? ci95Lo;
  final double? ci95Hi;

  const Measured({
    required this.value,
    required this.sigma,
    this.ci95Lo,
    this.ci95Hi,
  });

  factory Measured.fromJson(Map<String, dynamic> json) => Measured(
        value: (json['value'] as num).toDouble(),
        sigma: (json['sigma'] as num).toDouble(),
        ci95Lo: (json['ci95Lo'] ?? json['ci95_lo'] as num?)?.toDouble(),
        ci95Hi: (json['ci95Hi'] ?? json['ci95_hi'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'sigma': sigma,
        if (ci95Lo != null) 'ci95Lo': ci95Lo,
        if (ci95Hi != null) 'ci95Hi': ci95Hi,
      };

  @override
  List<Object?> get props => [value, sigma, ci95Lo, ci95Hi];
}

class EvapMeasured extends Equatable {
  final double value;
  final double sigma;
  final bool isLowerBound;
  final String definition;

  const EvapMeasured({
    required this.value,
    required this.sigma,
    this.isLowerBound = false,
    this.definition = 'T_lateral_ref - 0.5*(T_up + T_down)',
  });

  factory EvapMeasured.fromJson(Map<String, dynamic> json) => EvapMeasured(
        value: (json['value'] as num).toDouble(),
        sigma: (json['sigma'] as num).toDouble(),
        isLowerBound: json['isLowerBound'] ?? json['is_lower_bound'] ?? false,
        definition: json['definition'] ?? 'T_lateral_ref - 0.5*(T_up + T_down)',
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'sigma': sigma,
        'isLowerBound': isLowerBound,
        'definition': definition,
      };

  @override
  List<Object?> get props => [value, sigma, isLowerBound, definition];
}

class FlowEstimate extends Equatable {
  final double? point;
  final double lo;
  final double hi;
  final String method;
  final bool validated;
  final bool isExperimental;

  const FlowEstimate({
    this.point,
    required this.lo,
    required this.hi,
    this.method = 'empirical_characteristic_inversion',
    this.validated = false,
    this.isExperimental = true,
  });

  factory FlowEstimate.fromJson(Map<String, dynamic> json) => FlowEstimate(
        point: (json['point'] as num?)?.toDouble(),
        lo: (json['lo'] as num).toDouble(),
        hi: (json['hi'] as num).toDouble(),
        method: json['method'] ?? 'empirical_characteristic_inversion',
        validated: json['validated'] ?? false,
        isExperimental: json['isExperimental'] ?? json['is_experimental'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        if (point != null) 'point': point,
        'lo': lo,
        'hi': hi,
        'method': method,
        'validated': validated,
        'isExperimental': isExperimental,
      };

  @override
  List<Object?> get props => [point, lo, hi, method, validated, isExperimental];
}

class TimepointResult extends Equatable {
  final double tNominalS;
  final Classification classification;
  final Measured? deltaTUdC;
  final double confidencePct;
  final bool qaPassed;
  final List<String> qaFailures;

  const TimepointResult({
    required this.tNominalS,
    required this.classification,
    this.deltaTUdC,
    required this.confidencePct,
    required this.qaPassed,
    this.qaFailures = const [],
  });

  factory TimepointResult.fromJson(Map<String, dynamic> json) => TimepointResult(
        tNominalS: (json['tNominalS'] ?? json['t_nominal_s'] as num).toDouble(),
        classification: Classification.fromString(json['classification']),
        deltaTUdC: json['deltaTUdC'] != null || json['delta_t_ud_c'] != null
            ? Measured.fromJson(json['deltaTUdC'] ?? json['delta_t_ud_c'])
            : null,
        confidencePct: (json['confidencePct'] ?? json['confidence_pct'] as num).toDouble(),
        qaPassed: json['qaPassed'] ?? json['qa_passed'] ?? true,
        qaFailures: (json['qaFailures'] ?? json['qa_failures'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'tNominalS': tNominalS,
        'classification': classification.toWire(),
        if (deltaTUdC != null) 'deltaTUdC': deltaTUdC!.toJson(),
        'confidencePct': confidencePct,
        'qaPassed': qaPassed,
        'qaFailures': qaFailures,
      };

  @override
  List<Object?> get props => [
        tNominalS,
        classification,
        deltaTUdC,
        confidencePct,
        qaPassed,
        qaFailures,
      ];
}

class TemperaturesBreakdown extends Equatable {
  final Measured? upstreamC;
  final Measured? downstreamC;
  final Measured? lateralRefC;

  const TemperaturesBreakdown({
    this.upstreamC,
    this.downstreamC,
    this.lateralRefC,
  });

  factory TemperaturesBreakdown.fromJson(Map<String, dynamic> json) => TemperaturesBreakdown(
        upstreamC: json['upstreamC'] != null || json['upstream_c'] != null
            ? Measured.fromJson(json['upstreamC'] ?? json['upstream_c'])
            : null,
        downstreamC: json['downstreamC'] != null || json['downstream_c'] != null
            ? Measured.fromJson(json['downstreamC'] ?? json['downstream_c'])
            : null,
        lateralRefC: json['lateralRefC'] != null || json['lateral_ref_c'] != null
            ? Measured.fromJson(json['lateralRefC'] ?? json['lateral_ref_c'])
            : null,
      );

  Map<String, dynamic> toJson() => {
        if (upstreamC != null) 'upstreamC': upstreamC!.toJson(),
        if (downstreamC != null) 'downstreamC': downstreamC!.toJson(),
        if (lateralRefC != null) 'lateralRefC': lateralRefC!.toJson(),
      };

  @override
  List<Object?> get props => [upstreamC, downstreamC, lateralRefC];
}

class RoiVisual extends Equatable {
  final String name;
  final RoiVisualKind kind;
  final String url;
  final DateTime expiresAtUtc;
  final int widthPx;
  final int heightPx;

  const RoiVisual({
    required this.name,
    required this.kind,
    required this.url,
    required this.expiresAtUtc,
    required this.widthPx,
    required this.heightPx,
  });

  factory RoiVisual.fromJson(Map<String, dynamic> json) => RoiVisual(
        name: json['name'],
        kind: RoiVisualKind.fromString(json['kind']),
        url: json['url'],
        expiresAtUtc: DateTime.parse(json['expiresAtUtc'] ?? json['expires_at_utc']),
        widthPx: (json['widthPx'] ?? json['width_px'] as num).toInt(),
        heightPx: (json['heightPx'] ?? json['height_px'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': kind.toWire(),
        'url': url,
        'expiresAtUtc': expiresAtUtc.toUtc().toIso8601String(),
        'widthPx': widthPx,
        'heightPx': heightPx,
      };

  @override
  List<Object?> get props => [name, kind, url, expiresAtUtc, widthPx, heightPx];
}

class RetestAdvice extends Equatable {
  final String code;
  final bool requiresNewPatch;

  const RetestAdvice({
    required this.code,
    required this.requiresNewPatch,
  });

  factory RetestAdvice.fromJson(Map<String, dynamic> json) => RetestAdvice(
        code: json['code'],
        requiresNewPatch: json['requiresNewPatch'] ?? json['requires_new_patch'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'requiresNewPatch': requiresNewPatch,
      };

  @override
  List<Object?> get props => [code, requiresNewPatch];
}

class DiagnosticResponse extends Equatable {
  final String sessionId;
  final String engineVersion;
  final String calibrationIdUsed;
  final DateTime processedAtUtc;
  final Classification classification;
  final InconclusiveReason? inconclusiveReason;
  final String? inconclusiveReasonRaw;
  final Measured? deltaTUdC;
  final EvapMeasured? deltaTEvapC;
  final FlowEstimate? estimatedFlowMlMin;
  final double confidencePct;
  final Map<String, double> confidenceFactors;
  final double? snrResolutionDb;
  final TemperaturesBreakdown temperatures;
  final List<TimepointResult> timepoints;
  final List<String> flags;
  final List<RoiVisual> roiVisuals;
  final RetestAdvice? retestAdvice;

  const DiagnosticResponse({
    required this.sessionId,
    this.engineVersion = '1.2.0',
    required this.calibrationIdUsed,
    required this.processedAtUtc,
    required this.classification,
    this.inconclusiveReason,
    this.inconclusiveReasonRaw,
    this.deltaTUdC,
    this.deltaTEvapC,
    this.estimatedFlowMlMin,
    required this.confidencePct,
    this.confidenceFactors = const {},
    this.snrResolutionDb,
    this.temperatures = const TemperaturesBreakdown(),
    this.timepoints = const [],
    this.flags = const [],
    this.roiVisuals = const [],
    this.retestAdvice,
  });

  factory DiagnosticResponse.fromJson(Map<String, dynamic> json) => DiagnosticResponse(
        sessionId: json['sessionId'] ?? json['session_id'],
        engineVersion: json['engineVersion'] ?? json['engine_version'] ?? '1.2.0',
        calibrationIdUsed: json['calibrationIdUsed'] ?? json['calibration_id_used'],
        processedAtUtc: DateTime.parse(json['processedAtUtc'] ?? json['processed_at_utc']),
        classification: Classification.fromString(json['classification']),
        inconclusiveReason: json['inconclusiveReason'] != null || json['inconclusive_reason'] != null
            ? InconclusiveReason.fromString(json['inconclusiveReason'] ?? json['inconclusive_reason'])
            : null,
        inconclusiveReasonRaw: json['inconclusiveReasonRaw'] ?? json['inconclusive_reason_raw'],
        deltaTUdC: json['deltaTUdC'] != null || json['delta_t_ud_c'] != null
            ? Measured.fromJson(json['deltaTUdC'] ?? json['delta_t_ud_c'])
            : null,
        deltaTEvapC: json['deltaTEvapC'] != null || json['delta_t_evap_c'] != null
            ? EvapMeasured.fromJson(json['deltaTEvapC'] ?? json['delta_t_evap_c'])
            : null,
        estimatedFlowMlMin: json['estimatedFlowMlMin'] != null || json['estimated_flow_ml_min'] != null
            ? FlowEstimate.fromJson(json['estimatedFlowMlMin'] ?? json['estimated_flow_ml_min'])
            : null,
        confidencePct: (json['confidencePct'] ?? json['confidence_pct'] as num).toDouble(),
        confidenceFactors: (json['confidenceFactors'] ?? json['confidence_factors'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toDouble())) ??
            const {},
        snrResolutionDb: (json['snrResolutionDb'] ?? json['snr_resolution_db'] as num?)?.toDouble(),
        temperatures: json['temperatures'] != null
            ? TemperaturesBreakdown.fromJson(json['temperatures'])
            : const TemperaturesBreakdown(),
        timepoints: (json['timepoints'] as List<dynamic>?)
                ?.map((e) => TimepointResult.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        flags: (json['flags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
        roiVisuals: (json['roiVisuals'] ?? json['roi_visuals'] as List<dynamic>?)
                ?.map((e) => RoiVisual.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        retestAdvice: json['retestAdvice'] != null || json['retest_advice'] != null
            ? RetestAdvice.fromJson(json['retestAdvice'] ?? json['retest_advice'])
            : null,
      );

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'engineVersion': engineVersion,
        'calibrationIdUsed': calibrationIdUsed,
        'processedAtUtc': processedAtUtc.toUtc().toIso8601String(),
        'classification': classification.toWire(),
        if (inconclusiveReason != null) 'inconclusiveReason': inconclusiveReason!.toWire(),
        if (inconclusiveReasonRaw != null) 'inconclusiveReasonRaw': inconclusiveReasonRaw,
        if (deltaTUdC != null) 'deltaTUdC': deltaTUdC!.toJson(),
        if (deltaTEvapC != null) 'deltaTEvapC': deltaTEvapC!.toJson(),
        if (estimatedFlowMlMin != null) 'estimatedFlowMlMin': estimatedFlowMlMin!.toJson(),
        'confidencePct': confidencePct,
        'confidenceFactors': confidenceFactors,
        if (snrResolutionDb != null) 'snrResolutionDb': snrResolutionDb,
        'temperatures': temperatures.toJson(),
        'timepoints': timepoints.map((e) => e.toJson()).toList(),
        'flags': flags,
        'roiVisuals': roiVisuals.map((e) => e.toJson()).toList(),
        if (retestAdvice != null) 'retestAdvice': retestAdvice!.toJson(),
      };

  @override
  List<Object?> get props => [
        sessionId,
        engineVersion,
        calibrationIdUsed,
        processedAtUtc,
        classification,
        inconclusiveReason,
        inconclusiveReasonRaw,
        deltaTUdC,
        deltaTEvapC,
        estimatedFlowMlMin,
        confidencePct,
        confidenceFactors,
        snrResolutionDb,
        temperatures,
        timepoints,
        flags,
        roiVisuals,
        retestAdvice,
      ];
}

