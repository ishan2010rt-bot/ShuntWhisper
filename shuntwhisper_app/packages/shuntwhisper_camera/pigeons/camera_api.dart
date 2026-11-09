import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/generated/camera_api.g.dart',
  dartOptions: DartOptions(),
  kotlinOut: 'android/src/main/kotlin/com/shuntwhisper/camera/CameraApi.g.kt',
  kotlinOptions: KotlinOptions(package: 'com.shuntwhisper.camera'),
  swiftOut: 'ios/Classes/CameraApi.g.swift',
  swiftOptions: SwiftOptions(),
))
class PigeonSize {
  int width;
  int height;
  PigeonSize({required this.width, required this.height});
}

class PigeonPoint {
  double x;
  double y;
  PigeonPoint({required this.x, required this.y});
}

class PigeonWbGains {
  double r;
  double gEven;
  double gOdd;
  double b;
  PigeonWbGains({
    required this.r,
    required this.gEven,
    required this.gOdd,
    required this.b,
  });
}

class PigeonCameraConfig {
  String cameraId;
  int iso;
  int exposureTimeNs;
  int frameDurationNs;
  double targetDistanceMm;
  double? androidDiopters;
  double? iosLensPosition;
  String torchMode;
  double torchLevel;
  PigeonWbGains? wbGains;
  int kelvin;
  int mainsHz;
  PigeonSize stillSize;
  PigeonSize previewAnalysisSize;

  PigeonCameraConfig({
    required this.cameraId,
    required this.iso,
    required this.exposureTimeNs,
    required this.frameDurationNs,
    required this.targetDistanceMm,
    this.androidDiopters,
    this.iosLensPosition,
    required this.torchMode,
    required this.torchLevel,
    this.wbGains,
    required this.kelvin,
    required this.mainsHz,
    required this.stillSize,
    required this.previewAnalysisSize,
  });
}

class PigeonAppliedState {
  int iso;
  int exposureTimeNs;
  PigeonWbGains? wbGains;
  double? focusDistanceDiopters;
  double? lensPosition;
  double torchLevel;
  bool awbLocked;
  bool aeLocked;
  int sensorTimestampNs;
  bool verified;

  PigeonAppliedState({
    required this.iso,
    required this.exposureTimeNs,
    this.wbGains,
    this.focusDistanceDiopters,
    this.lensPosition,
    required this.torchLevel,
    required this.awbLocked,
    required this.aeLocked,
    required this.sensorTimestampNs,
    required this.verified,
  });
}

class PigeonCaptureResult {
  String filePath;
  int width;
  int height;
  int sizeBytes;
  String sha256;
  PigeonAppliedState appliedState;

  PigeonCaptureResult({
    required this.filePath,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.sha256,
    required this.appliedState,
  });
}

@HostApi()
abstract class CameraHostApi {
  void initialize(PigeonCameraConfig config);
  PigeonAppliedState applyConfig(PigeonCameraConfig config);
  void setTorch(String mode, double level);
  PigeonCaptureResult captureBurst(int burstCount);
  void startPreviewAnalysis();
  void stopPreviewAnalysis();
  void dispose();
}

@FlutterApi()
abstract class CameraFlutterApi {
  void onPreviewLumaFrame(Uint8List lumaPlane, int width, int height, int timestampNs);
  void onConfigDeviation(String param, double requested, double applied);
}

