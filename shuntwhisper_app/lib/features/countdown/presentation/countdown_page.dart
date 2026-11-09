import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../session/bloc/session_bloc.dart';
import '../../session/bloc/session_state.dart';
import '../../session/bloc/session_event.dart';

class CountdownPage extends StatefulWidget {
  final int targetSeconds;
  final String label;

  const CountdownPage({
    super.key,
    required this.targetSeconds,
    required this.label,
  });

  @override
  State<CountdownPage> createState() => _CountdownPageState();
}

class _CountdownPageState extends State<CountdownPage> {
  late Timer _timer;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _elapsed++;
      });

      if (_elapsed >= widget.targetSeconds) {
        timer.cancel();
        if (widget.targetSeconds == 23) {
          context.read<SessionBloc>().add(const TransientWindowOpened());
        } else if (widget.targetSeconds == 120) {
          context.read<SessionBloc>().add(const SteadyWindowOpened());
        }
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = (widget.targetSeconds - _elapsed).clamp(0, widget.targetSeconds);
    final progress = (_elapsed / widget.targetSeconds).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.label,
              style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 32),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 220,
                  height: 220,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 8,
                    color: const Color(0xFF00E676),
                    backgroundColor: Colors.white12,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$remaining',
                      style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.bold),
                    ),
                    const Text('SECONDS', style: TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 1.5)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 48),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.camera_alt_outlined, color: Colors.white70, size: 20),
                  SizedBox(width: 8),
                  Text('Keep camera aligned with patch', style: TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

