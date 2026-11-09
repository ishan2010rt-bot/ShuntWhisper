import 'package:equatable/equatable.dart';
import '../../../domain/models/alignment_models.dart';
import '../../../domain/models/diagnostic_models.dart';
import '../../../domain/models/payload_models.dart';

enum SessionStep {
  idle,
  preCheck,
  baselineAlign,
  baselineCaptured,
  dosingPrompt,
  countdownTransient,
  countdownSteady,
  uploading,
  reportReady,
  errorHandling,
}

class SessionState extends Equatable {
  final SessionStep step;
  final String sessionId;
  final int? tZeroMonotonicNs;
  final DateTime? tZeroUtc;
  final double doseVolumeUl;
  final Map<String, String> capturedFilePaths; // 'baseline', 't23', 't120'
  final List<CapturedImageMeta> capturedImages;
  final FiducialAlignmentState? lastAlignment;
  final DiagnosticResponse? diagnosticResponse;
  final String? errorMessage;
  final String? errorCode;
  final int baselineRetries;
  final int alignConsecutiveFrames;

  const SessionState({
    required this.step,
    required this.sessionId,
    this.tZeroMonotonicNs,
    this.tZeroUtc,
    this.doseVolumeUl = 70.0,
    this.capturedFilePaths = const {},
    this.capturedImages = const [],
    this.lastAlignment,
    this.diagnosticResponse,
    this.errorMessage,
    this.errorCode,
    this.baselineRetries = 0,
    this.alignConsecutiveFrames = 0,
  });

  factory SessionState.initial(String sessionId) => SessionState(
        step: SessionStep.idle,
        sessionId: sessionId,
      );

  SessionState copyWith({
    SessionStep? step,
    String? sessionId,
    int? tZeroMonotonicNs,
    DateTime? tZeroUtc,
    double? doseVolumeUl,
    Map<String, String>? capturedFilePaths,
    List<CapturedImageMeta>? capturedImages,
    FiducialAlignmentState? lastAlignment,
    DiagnosticResponse? diagnosticResponse,
    String? errorMessage,
    String? errorCode,
    int? baselineRetries,
    int? alignConsecutiveFrames,
  }) {
    return SessionState(
      step: step ?? this.step,
      sessionId: sessionId ?? this.sessionId,
      tZeroMonotonicNs: tZeroMonotonicNs ?? this.tZeroMonotonicNs,
      tZeroUtc: tZeroUtc ?? this.tZeroUtc,
      doseVolumeUl: doseVolumeUl ?? this.doseVolumeUl,
      capturedFilePaths: capturedFilePaths ?? this.capturedFilePaths,
      capturedImages: capturedImages ?? this.capturedImages,
      lastAlignment: lastAlignment ?? this.lastAlignment,
      diagnosticResponse: diagnosticResponse ?? this.diagnosticResponse,
      errorMessage: errorMessage ?? this.errorMessage,
      errorCode: errorCode ?? this.errorCode,
      baselineRetries: baselineRetries ?? this.baselineRetries,
      alignConsecutiveFrames: alignConsecutiveFrames ?? this.alignConsecutiveFrames,
    );
  }

  @override
  List<Object?> get props => [
        step,
        sessionId,
        tZeroMonotonicNs,
        tZeroUtc,
        doseVolumeUl,
        capturedFilePaths,
        capturedImages,
        lastAlignment,
        diagnosticResponse,
        errorMessage,
        errorCode,
        baselineRetries,
        alignConsecutiveFrames,
      ];
}

