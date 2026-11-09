import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shuntwhisper_camera/src/camera_service.dart';
import 'package:shuntwhisper_camera/src/camera_service_impl.dart';
import 'data/api/shuntwhisper_api.dart';
import 'data/api/dio_shuntwhisper_api.dart';
import 'features/session/bloc/session_bloc.dart';
import 'features/session/bloc/session_state.dart';
import 'features/session/bloc/session_event.dart';
import 'features/preflight/presentation/preflight_page.dart';
import 'features/alignment/presentation/viewfinder_page.dart';
import 'features/dosing/presentation/dosing_prompt_sheet.dart';
import 'features/countdown/presentation/countdown_page.dart';
import 'features/report/presentation/report_page.dart';

class ShuntWhisperApp extends StatelessWidget {
  final String backendBaseUrl;

  const ShuntWhisperApp({
    super.key,
    this.backendBaseUrl = 'http://127.0.0.1:8000',
  });

  @override
  Widget build(BuildContext context) {
    final cameraService = CameraServiceImpl();
    final api = DioShuntwhisperApi(
      baseUrl: backendBaseUrl,
      tokenProvider: () async => 'shuntwhisper-p0-local-token',
    );

    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<CameraService>.value(value: cameraService),
        RepositoryProvider<ShuntWhisperApi>.value(value: api),
      ],
      child: BlocProvider(
        create: (context) => SessionBloc(
          cameraService: cameraService,
          api: api,
          initialSessionId: 'session_${DateTime.now().millisecondsSinceEpoch}',
        ),
        child: MaterialApp(
          title: 'ShuntWhisper',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF121212),
            primaryColor: const Color(0xFF00E676),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF00E676),
              secondary: Color(0xFF00B0FF),
              surface: Color(0xFF1E1E1E),
            ),
          ),
          home: const SessionCoordinatorView(),
        ),
      ),
    );
  }
}

class SessionCoordinatorView extends StatelessWidget {
  const SessionCoordinatorView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionBloc, SessionState>(
      builder: (context, state) {
        return switch (state.step) {
          SessionStep.idle => const HomeScreen(),
          SessionStep.preCheck => const PreflightPage(),
          SessionStep.baselineAlign => const ViewfinderPage(),
          SessionStep.baselineCaptured => const DosingPromptSheet(),
          SessionStep.dosingPrompt => const Scaffold(
              backgroundColor: Colors.black,
              body: Center(child: DosingPromptSheet()),
            ),
          SessionStep.countdownTransient => const CountdownPage(
              targetSeconds: 23,
              label: 'Transient Thermal Inflection',
            ),
          SessionStep.countdownSteady => const CountdownPage(
              targetSeconds: 120,
              label: 'Thermal Steady State',
            ),
          SessionStep.uploading => const Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF00E676)),
                    SizedBox(height: 24),
                    Text(
                      'Analyzing Thermal Signatures...',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          SessionStep.reportReady => const ReportPage(),
          SessionStep.errorHandling => Scaffold(
              backgroundColor: const Color(0xFF1E1E1E),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        state.errorCode ?? 'SESSION_ERROR',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.errorMessage ?? 'An error occurred during diagnosis.',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => context.read<SessionBloc>().add(const ResetSession()),
                        child: const Text('Restart Test'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        };
      },
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00E676), width: 2),
                  ),
                  child: const Icon(Icons.thermostat_outlined, color: Color(0xFF00E676), size: 48),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'ShuntWhisper',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(height: 8),
              const Text(
                'Non-Invasive Smartphone VP Shunt Diagnostic Platform',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Research prototype. Not a validated medical device. Does not replace clinical evaluation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  context.read<SessionBloc>().add(const StartSession());
                },
                child: const Text('Start Diagnostic Test', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

