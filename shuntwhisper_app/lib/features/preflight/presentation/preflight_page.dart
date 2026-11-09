import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../session/bloc/session_bloc.dart';
import '../../session/bloc/session_event.dart';

class PreflightPage extends StatelessWidget {
  const PreflightPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Pre-Check Inspection', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Instrument & Environmental Preflight',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Verify hardware readiness and ambient parameters prior to baseline capture.',
              style: TextStyle(color: Colors.white60, fontSize: 14),
            ),
            const SizedBox(height: 24),
            _checkItem(Icons.camera_alt_outlined, 'Camera Manual Control', 'ISO 50, 10ms shutter, daylight WB locked', true),
            _checkItem(Icons.battery_charging_full_outlined, 'Battery Level', '>= 20% required for stable LED torching', true),
            _checkItem(Icons.thermostat_outlined, 'Ambient Environment', '22.5 °C, 45% RH (within 15–30 °C safe range)', true),
            _checkItem(Icons.qr_code_scanner_outlined, 'TLC Lot Calibration', 'Lot CAL-TLC-2025-01 verified (expires in 90 days)', true),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E676),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                context.read<SessionBloc>().add(const PreChecksPassed());
              },
              child: const Text('Proceed to Baseline Capture', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkItem(IconData icon, String title, String subtitle, bool passed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: passed ? const Color(0xFF00E676) : Colors.amber, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
          ),
          Icon(
            passed ? Icons.check_circle : Icons.error_outline,
            color: passed ? const Color(0xFF00E676) : Colors.amber,
            size: 20,
          ),
        ],
      ),
    );
  }
}

