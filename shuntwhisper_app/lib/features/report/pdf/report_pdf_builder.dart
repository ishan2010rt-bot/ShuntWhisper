import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../domain/models/diagnostic_models.dart';

class ReportPdfBuilder {
  static Future<Uint8List> build({
    required DiagnosticResponse report,
    String? subjectRef,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'ShuntWhisper Diagnostic Report',
                        style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Non-invasive VP Shunt Patency Diagnostic Platform',
                        style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Text(
                    'Session: ${report.sessionId.substring(0, 8)}',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                ],
              ),
              pw.Divider(thickness: 1.5, color: PdfColors.grey300),
              pw.SizedBox(height: 12),

              // Subject Info
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Subject Ref: ${subjectRef ?? "ANONYMOUS"}', style: const pw.TextStyle(fontSize: 12)),
                    pw.Text('Date: ${report.processedAtUtc.toIso8601String().substring(0, 10)}', style: const pw.TextStyle(fontSize: 12)),
                    pw.Text('Engine: v${report.engineVersion}', style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Verdict Banner
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: report.classification.toWire() == 'PATENT_HIGH' ? PdfColors.green50 : PdfColors.red50,
                  border: pw.Border.all(
                    color: report.classification.toWire() == 'PATENT_HIGH' ? PdfColors.green700 : PdfColors.red700,
                  ),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'STATUS: ${report.classification.clinicalDescription}',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: report.classification.toWire() == 'PATENT_HIGH' ? PdfColors.green900 : PdfColors.red900,
                      ),
                    ),
                    if (report.inconclusiveReasonRaw != null) ...[
                      pw.SizedBox(height: 6),
                      pw.Text('Reason: ${report.inconclusiveReasonRaw}', style: const pw.TextStyle(fontSize: 12)),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Primary Differential Metric Table
              pw.Text('Thermal Differential Metrics', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: ['Metric', 'Observed Value', 'Uncertainty (1-sigma)', 'Reference Patent Band'],
                data: [
                  [
                    'Catheter Temperature Delta (ΔT_UD)',
                    report.deltaTUdC != null ? '${report.deltaTUdC!.value.toStringAsFixed(3)} °C' : 'N/A',
                    report.deltaTUdC != null ? '±${report.deltaTUdC!.sigma.toStringAsFixed(3)} °C' : 'N/A',
                    '0.20 to 0.80 °C'
                  ],
                  [
                    'Evaporative Sink Depression (ΔT_evap)',
                    report.deltaTEvapC != null ? '${report.deltaTEvapC!.value.toStringAsFixed(2)} °C' : 'N/A',
                    '±0.05 °C',
                    '>= 1.50 °C'
                  ],
                  [
                    'Confidence Score',
                    '${report.confidencePct.toStringAsFixed(1)} %',
                    'N/A',
                    '> 80.0 %'
                  ],
                ],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                cellAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              pw.SizedBox(height: 24),

              // Experimental Flow Rate
              if (report.estimatedFlowMlMin != null) ...[
                pw.Text('Flow Rate Estimation (Experimental)', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.amber50,
                    border: pw.Border.all(color: PdfColors.amber400),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Estimated Flow (Q): ${report.estimatedFlowMlMin!.point?.toStringAsFixed(3) ?? "0.000"} mL/min', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text('Method: ${report.estimatedFlowMlMin!.method}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 24),
              ],

              pw.Spacer(),

              // Mandatory Clinical Disclaimer
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.Container(
                alignment: pw.Alignment.center,
                padding: const pw.EdgeInsets.symmetric(vertical: 8),
                child: pw.Text(
                  'Research prototype. Not a validated medical device. Does not replace clinical evaluation.',
                  style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}

