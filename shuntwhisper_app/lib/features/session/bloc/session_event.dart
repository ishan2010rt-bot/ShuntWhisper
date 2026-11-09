import 'package:equatable/equatable.dart';
import '../../../domain/models/alignment_models.dart';
import '../../../domain/models/diagnostic_models.dart';
import '../../../domain/models/payload_models.dart';

sealed class SessionEvent extends Equatable {
  const SessionEvent();

  @override
  List<Object?> get props => [];
}

class StartSession extends SessionEvent {
  const StartSession();
}

class PreChecksPassed extends SessionEvent {
  const PreChecksPassed();
}

class PreCheckFailed extends SessionEvent {
  final String code;
  final String reason;
  const PreCheckFailed({required this.code, required this.reason});

  @override
  List<Object?> get props => [code, reason];
}

class AlignmentUpdated extends SessionEvent {
  final FiducialAlignmentState alignment;
  const AlignmentUpdated(this.alignment);

  @override
  List<Object?> get props => [alignment];
}

class BaselineCaptured extends SessionEvent {
  final String filePath;
  final CapturedImageMeta meta;
  const BaselineCaptured({required this.filePath, required this.meta});

  @override
  List<Object?> get props => [filePath, meta];
}

class DoseConfirmed extends SessionEvent {
  final int tZeroMonotonicNs;
  final DateTime tZeroUtc;
  final double volumeUl;

  const DoseConfirmed({
    required this.tZeroMonotonicNs,
    required this.tZeroUtc,
    this.volumeUl = 70.0,
  });

  @override
  List<Object?> get props => [tZeroMonotonicNs, tZeroUtc, volumeUl];
}

class TransientWindowOpened extends SessionEvent {
  const TransientWindowOpened();
}

class TransientCaptured extends SessionEvent {
  final String filePath;
  final CapturedImageMeta meta;
  const TransientCaptured({required this.filePath, required this.meta});

  @override
  List<Object?> get props => [filePath, meta];
}

class SteadyWindowOpened extends SessionEvent {
  const SteadyWindowOpened();
}

class SteadyCaptured extends SessionEvent {
  final String filePath;
  final CapturedImageMeta meta;
  const SteadyCaptured({required this.filePath, required this.meta});

  @override
  List<Object?> get props => [filePath, meta];
}

class UploadProgressUpdated extends SessionEvent {
  final double progress;
  const UploadProgressUpdated(this.progress);

  @override
  List<Object?> get props => [progress];
}

class DiagnosticReportReceived extends SessionEvent {
  final DiagnosticResponse report;
  const DiagnosticReportReceived(this.report);

  @override
  List<Object?> get props => [report];
}

class SessionFailed extends SessionEvent {
  final String code;
  final String message;
  const SessionFailed({required this.code, required this.message});

  @override
  List<Object?> get props => [code, message];
}

class ResetSession extends SessionEvent {
  const ResetSession();
}

