import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';
import '../../session/bloc/session_bloc.dart';
import '../../session/bloc/session_state.dart';
import '../../session/bloc/session_event.dart';
import '../../../domain/models/diagnostic_models.dart';
import '../pdf/report_pdf_builder.dart';
import 'status_banner.dart';
import 'metric_card.dart';

class ReportPage extends StatelessWidget {
  const ReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionBloc, SessionState>(
      builder: (context, state) {
        final report = state.diagnosticResponse;
        if (report == null) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator(color: Color(0xFF00E676))),
          );
        }

        final deltaT = report.deltaTUdC;
        final deltaEvap = report.deltaTEvapC;
        final flow = report.estimatedFlowMlMin;

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Diagnostic Verdict', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: 'Export PDF Report',
                onPressed: () async {
                  final bytes = await ReportPdfBuilder.build(report: report);
                  await Printing.layoutPdf(onLayout: (_) => bytes);
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Clinical Status Banner
                StatusBanner(
                  classification: report.classification,
                  inconclusiveReason: report.inconclusiveReasonRaw,
                ),
                const SizedBox(height: 20),

                // 2. Metrics Grid
                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        title: 'ΔT (Up - Down)',
                        value: deltaT != null ? '${deltaT.value.toStringAsFixed(3)} °C' : 'N/A',
                        subtitle: deltaT != null ? '± ${deltaT.sigma.toStringAsFixed(3)} °C (1-σ)' : null,
                        accentColor: const Color(0xFF00E676),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(
                        title: 'Evaporative Sink',
                        value: deltaEvap != null ? '${deltaEvap.value.toStringAsFixed(2)} °C' : 'N/A',
                        subtitle: 'Req: >= 1.50 °C',
                        accentColor: Colors.lightBlueAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: MetricCard(
                        title: 'Confidence Score',
                        value: '${report.confidencePct.toStringAsFixed(1)} %',
                        subtitle: 'Algorithm certainty',
                        accentColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MetricCard(
                        title: 'Est. Flow (Q)',
                        value: flow != null ? '${flow.point?.toStringAsFixed(3) ?? "0.000"} mL/min' : 'N/A',
                        badgeText: 'EXPERIMENTAL',
                        subtitle: 'Unvalidated',
                        accentColor: Colors.amberAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 3. Temperature Sensors Breakdown Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Measured Surface Temperatures',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _temperatureRow(
                        'Upstream TLC ROI (x = -8.7 mm):',
                        report.temperatures.upstreamC?.value != null
                            ? '${report.temperatures.upstreamC!.value.toStringAsFixed(2)} °C'
                            : 'N/A',
                      ),
                      const Divider(color: Colors.white12, height: 16),
                      _temperatureRow(
                        'Downstream TLC ROI (x = +8.7 mm):',
                        report.temperatures.downstreamC?.value != null
                            ? '${report.temperatures.downstreamC!.value.toStringAsFixed(2)} °C'
                            : 'N/A',
                      ),
                      const Divider(color: Colors.white12, height: 16),
                      _temperatureRow(
                        'Lateral Reference ROI (y = +12.0 mm):',
                        report.temperatures.lateralRefC?.value != null
                            ? '${report.temperatures.lateralRefC!.value.toStringAsFixed(2)} °C'
                            : 'N/A',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // 4. Reset & New Test Button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    context.read<SessionBloc>().add(const ResetSession());
                  },
                  child: const Text('Start New Test', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _temperatureRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

