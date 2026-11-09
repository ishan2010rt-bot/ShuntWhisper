import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuntwhisper_app/domain/models/diagnostic_models.dart';
import 'package:shuntwhisper_app/domain/models/config_models.dart';
import 'package:shuntwhisper_app/domain/models/enums.dart';

void main() {
  group('Golden JSON Fixture Contract Round-Trip Tests', () {
    const fixturesDir = '../test/models/fixtures';

    test('Round-trip golden_remote_config.json', () {
      final file = File('$fixturesDir/golden_remote_config.json');
      expect(file.existsSync(), isTrue);
      final jsonStr = file.readAsStringSync();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      final config = RemoteConfig.fromJson(map);
      expect(config.patchLayout.upstreamCenterMm.x, -8.7);
      expect(config.patchLayout.downstreamCenterMm.x, 8.7);
      expect(config.patchLayout.lateralRefCenterMm.y, 12.0);
      expect(config.patchLayout.apertureSizeMm.w, 7.6);
      expect(config.patchLayout.fiducials.length, 4);

      final reserialized = config.toJson();
      expect(reserialized['patchLayout']['upstreamCenterMm']['x'], -8.7);
    });

    test('Round-trip golden_device_profile.json', () {
      final file = File('$fixturesDir/golden_device_profile.json');
      expect(file.existsSync(), isTrue);
      final jsonStr = file.readAsStringSync();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      final profile = DeviceProfile.fromJson(map);
      expect(profile.platform, 'android');
      expect(profile.model, 'pixel_8');
      expect(profile.targetDistanceMm, 100.0);
      expect(profile.neutralWbGains?.r, 1.95);
    });

    test('Round-trip golden_diagnostic_response_patent_high.json', () {
      final file = File('$fixturesDir/golden_diagnostic_response_patent_high.json');
      expect(file.existsSync(), isTrue);
      final jsonStr = file.readAsStringSync();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      final resp = DiagnosticResponse.fromJson(map);
      expect(resp.classification, Classification.patentHigh);
      expect(resp.deltaTUdC?.value, 0.452);
      expect(resp.deltaTEvapC?.value, 2.41);
      expect(resp.confidencePct, 96.0);
      expect(resp.roiVisuals.length, 1);
      expect(resp.roiVisuals.first.name, 'overlay');
    });

    test('Round-trip golden_diagnostic_response_patent_marginal.json', () {
      final file = File('$fixturesDir/golden_diagnostic_response_patent_marginal.json');
      expect(file.existsSync(), isTrue);
      final jsonStr = file.readAsStringSync();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      final resp = DiagnosticResponse.fromJson(map);
      expect(resp.classification, Classification.patentMarginal);
      expect(resp.deltaTUdC?.value, 0.185);
      expect(resp.flags.contains('NEAR_DECISION_BOUNDARY'), isTrue);
    });

    test('Round-trip golden_diagnostic_response_occluded.json', () {
      final file = File('$fixturesDir/golden_diagnostic_response_occluded.json');
      expect(file.existsSync(), isTrue);
      final jsonStr = file.readAsStringSync();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      final resp = DiagnosticResponse.fromJson(map);
      expect(resp.classification, Classification.occluded);
      expect(resp.deltaTUdC?.value, -0.012);
      expect(resp.flags.contains('SYMMETRIC_PROFILE'), isTrue);
    });

    test('Round-trip golden_diagnostic_response_inconclusive.json', () {
      final file = File('$fixturesDir/golden_diagnostic_response_inconclusive.json');
      expect(file.existsSync(), isTrue);
      final jsonStr = file.readAsStringSync();
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      final resp = DiagnosticResponse.fromJson(map);
      expect(resp.classification, Classification.inconclusive);
      expect(resp.inconclusiveReason, InconclusiveReason.insufficientHydration);
      expect(resp.retestAdvice?.requiresNewPatch, isTrue);
    });
  });
}

