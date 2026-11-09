import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../session/bloc/session_bloc.dart';
import '../../session/bloc/session_event.dart';

class DosingPromptSheet extends StatefulWidget {
  const DosingPromptSheet({super.key});

  @override
  State<DosingPromptSheet> createState() => _DosingPromptSheetState();
}

class _DosingPromptSheetState extends State<DosingPromptSheet> {
  double _volumeUl = 70.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.water_drop_outlined, color: Color(0xFF00E676), size: 28),
              SizedBox(width: 12),
              Text(
                'Hydrate Evaporative Foam',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Dispense 60–80 µL of distilled water onto the central foam aperture using a 1 mL syringe.',
            style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Dose Volume:', style: TextStyle(color: Colors.white, fontSize: 16)),
              Text('${_volumeUl.toInt()} µL', style: const TextStyle(color: Color(0xFF00E676), fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: _volumeUl,
            min: 50.0,
            max: 100.0,
            divisions: 10,
            activeColor: const Color(0xFF00E676),
            inactiveColor: Colors.white24,
            onChanged: (val) => setState(() => _volumeUl = val),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final nowUtc = DateTime.now().toUtc();
              final nowNanos = Stopwatch().elapsedTicks * 1000;
              context.read<SessionBloc>().add(
                    DoseConfirmed(
                      tZeroMonotonicNs: nowNanos,
                      tZeroUtc: nowUtc,
                      volumeUl: _volumeUl,
                    ),
                  );
            },
            child: const Text('Dosed & Ready (Start Timer)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

