import 'dart:async';
import 'dart:typed_data';
import 'package:shuntwhisper_app/core/result.dart';
import 'package:shuntwhisper_app/domain/models/camera_models.dart';
import 'package:shuntwhisper_app/domain/models/alignment_models.dart';
import 'package:shuntwhisper_app/domain/models/payload_models.dart';

abstract class CameraService {
  Stream<FiducialAlignmentState> get alignmentStream;
  Stream<Uint8List> get lumaFrameStream;

  Future<Result<CameraCapabilities>> getCapabilities();
  Future<Result<AppliedCameraState>> initialize(CameraHardwareConfig config);
  Future<Result<AppliedCameraState>> applyConfig(CameraHardwareConfig config);
  Future<Result<void>> setTorch(TorchMode mode, double level);
  Future<Result<List<CapturedImageMeta>>> captureBurst({int burstCount = 3});
  Future<void> startPreviewAnalysis();
  Future<void> stopPreviewAnalysis();
  Future<void> dispose();
}

