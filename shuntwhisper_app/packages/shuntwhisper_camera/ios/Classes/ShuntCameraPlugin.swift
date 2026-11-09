import Flutter
import UIKit
import AVFoundation

public class ShuntCameraPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var channel: FlutterMethodChannel?
    private var lumaChannel: FlutterEventChannel?
    private var lumaSink: FlutterEventSink?

    private var captureSession: AVCaptureSession?
    private var videoDevice: AVCaptureDevice?

    private var lastIso: Float = 50.0
    private var lastExposureDurationNs: Int64 = 10000000

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.shuntwhisper.camera/methods", binaryMessenger: registrar.messenger())
        let lumaChannel = FlutterEventChannel(name: "com.shuntwhisper.camera/luma_stream", binaryMessenger: registrar.messenger())

        let instance = ShuntCameraPlugin()
        instance.channel = channel
        instance.lumaChannel = lumaChannel

        registrar.addMethodCallDelegate(instance, channel: channel)
        lumaChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getCapabilities":
            let caps: [String: Any] = [
                "hasManualSensor": true,
                "isoMin": 50,
                "isoMax": 3000,
                "exposureMinNs": 10000,
                "exposureMaxNs": 1000000000,
                "minFocusDistanceMm": 100.0,
                "hasTorch": true,
                "supportsWbGains": true,
                "supportedStillSizes": [
                    ["widthPx": 4032, "heightPx": 3024],
                    ["widthPx": 1920, "heightPx": 1080]
                ],
                "hardwareLevel": "FULL",
                "physicalCameraIds": ["com.apple.avfoundation.back.telephoto", "com.apple.avfoundation.back.wide"]
            ]
            result(caps)

        case "initialize", "applyConfig":
            if let args = call.arguments as? [String: Any] {
                if let isoVal = args["iso"] as? NSNumber {
                    lastIso = isoVal.floatValue
                }
                if let expVal = args["exposureTimeNs"] as? NSNumber {
                    lastExposureDurationNs = expVal.int64Value
                }
            }

            let appliedState: [String: Any] = [
                "iso": Int(lastIso),
                "exposureTimeNs": lastExposureDurationNs,
                "whiteBalanceGains": ["r": 1.88, "gEven": 1.0, "gOdd": 1.0, "b": 1.92],
                "focusDistanceDiopters": 10.0,
                "lensPosition": 0.10,
                "torchLevel": 1.0,
                "awbLocked": true,
                "aeLocked": true,
                "sensorTimestampNs": Int64(mach_absolute_time()),
                "verified": true,
                "deviations": []
            ]
            result(appliedState)

        case "setTorch":
            result(nil)

        case "captureBurst":
            let burstCount = (call.arguments as? [String: Any])?["burstCount"] as? Int ?? 3
            var bursts: [[String: Any]] = []

            for i in 0..<burstCount {
                bursts.append([
                    "part": "sample",
                    "tNominalS": 0.0,
                    "tActualS": 0.0,
                    "mime": "image/png",
                    "encoding": "raw",
                    "widthPx": 4032,
                    "heightPx": 3024,
                    "sizeBytes": 2048,
                    "sha256": "mock_ios_sha256_\(i)",
                    "appliedCamera": [
                        "iso": Int(lastIso),
                        "exposureTimeNs": lastExposureDurationNs,
                        "torchLevel": 1.0,
                        "awbLocked": true,
                        "aeLocked": true,
                        "sensorTimestampNs": Int64(mach_absolute_time()),
                        "verified": true,
                        "deviations": []
                    ],
                    "alignmentAtCapture": [
                        "analysisSize": ["widthPx": 1280, "heightPx": 960],
                        "markersDetected": 4,
                        "stabilityScore": 1.0,
                        "status": "ALIGNED",
                        "violations": []
                    ],
                    "validation": [
                        "passed": true,
                        "sharpness": 0.22,
                        "whiteLevel": 0.54,
                        "whiteClipFrac": 0.003,
                        "specularFracByRoi": [:],
                        "markersDetected": 4,
                        "failures": []
                    ],
                    "intrinsics": [
                        "fx": 3080.0, "fy": 3080.0, "cx": 2016.0, "cy": 1512.0,
                        "imageW": 4032, "imageH": 3024, "source": "profile"
                    ],
                    "burstIndex": i,
                    "burstSize": burstCount
                ])
            }
            result(bursts)

        case "startPreviewAnalysis", "stopPreviewAnalysis", "dispose":
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        lumaSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        lumaSink = null
        return nil
    }
}

