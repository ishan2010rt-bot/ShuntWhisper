import 'package:equatable/equatable.dart';
import '../../../domain/models/payload_models.dart';

sealed class SessionEffect extends Equatable {
  const SessionEffect();

  @override
  List<Object?> get props => [];
}

class RunPreflightChecksEffect extends SessionEffect {
  const RunPreflightChecksEffect();
}

class EnableTorchEffect extends SessionEffect {
  final double level;
  const EnableTorchEffect({this.level = 1.0});

  @override
  List<Object?> get props => [level];
}

class DisableTorchEffect extends SessionEffect {
  const DisableTorchEffect();
}

class TriggerBurstCaptureEffect extends SessionEffect {
  final String part; // 'baseline', 't23', 't120'
  const TriggerBurstCaptureEffect({required this.part});

  @override
  List<Object?> get props => [part];
}

class ScheduleWindowEffect extends SessionEffect {
  final String windowName;
  final Duration delay;
  const ScheduleWindowEffect({required this.windowName, required this.delay});

  @override
  List<Object?> get props => [windowName, delay];
}

class UploadSessionPayloadEffect extends SessionEffect {
  final CapturePayload payload;
  final Map<String, String> filePaths;
  const UploadSessionPayloadEffect({required this.payload, required this.filePaths});

  @override
  List<Object?> get props => [payload, filePaths];
}

class HapticCueEffect extends SessionEffect {
  final String type; // 'warning', 'success', 'capture'
  const HapticCueEffect(this.type);

  @override
  List<Object?> get props => [type];
}

