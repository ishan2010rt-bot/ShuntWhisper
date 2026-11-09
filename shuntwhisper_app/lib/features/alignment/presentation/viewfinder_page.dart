import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../session/bloc/session_bloc.dart';
import '../../session/bloc/session_state.dart';
import '../../session/bloc/session_event.dart';
import 'alignment_hud_painter.dart';

class ViewfinderPage extends StatelessWidget {
  const ViewfinderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionBloc, SessionState>(
      builder: (context, state) {
        final alignment = state.lastAlignment;
        final consecutive = state.alignConsecutiveFrames;

        String guidanceText = 'Align patch within guide reticle';
        if (alignment != null && alignment.violations.isNotEmpty) {
          guidanceText = alignment.violations.first.name.toUpperCase();
        } else if (consecutive > 0) {
          guidanceText = 'Hold still... capturing ($consecutive/8)';
        }

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // Simulated live camera preview plane
              Container(color: const Color(0xFF121212)),

              // Alignment Reticle Overlay
              CustomPaint(
                painter: AlignmentHudPainter(
                  alignment: alignment,
                  consecutiveAligned: consecutive,
                  targetAlignedFrames: 8,
                ),
              ),

              // Top Guidance Banner
              Positioned(
                top: 60,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    guidanceText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),

              // Bottom Manual Override / Trigger
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: () {
                      // Manual capture trigger
                      context.read<SessionBloc>().add(
                            const BaselineCaptured(
                              filePath: '/tmp/manual_baseline.png',
                              meta: null as dynamic,
                            ),
                          );
                    },
                    child: const Text('Capture Manually', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

