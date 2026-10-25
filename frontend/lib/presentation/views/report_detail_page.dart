import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../app/app_scope.dart';
import '../../domain/models/analysis_result.dart';
import '../viewmodels/report_view_model.dart';
import 'analysis_detail_view.dart';

class ReportDetailPage extends StatefulWidget {
  const ReportDetailPage({
    super.key,
    required this.result,
    required this.imageBytes,
  });

  final AnalysisResult result;
  final Uint8List? imageBytes;

  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  ReportViewModel? _report;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _report ??= AppScope.of(context).createReportViewModel();
  }

  @override
  void dispose() {
    _report?.dispose();
    super.dispose();
  }

  Future<void> _export({bool share = false}) async {
    final bytes = await _report!.create(
      widget.result,
      imageBytes: widget.imageBytes,
    );
    if (!mounted) return;
    if (bytes == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_report!.error!)));
      return;
    }
    final rawName = widget.result.displayName ?? 'analisis_nerilum';
    final safeName = rawName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final filename = '${safeName.isEmpty ? 'analisis_nerilum' : safeName}.pdf';
    try {
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: filename);
      } else {
        await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir el PDF. Inténtalo de nuevo.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _report!,
    builder: (context, _) => AnalysisDetailView(
      result: widget.result,
      imageBytes: widget.imageBytes,
      onBack: () => Navigator.of(context).pop(),
      onExport: () => _export(),
      onShare: () => _export(share: true),
      exporting: _report!.busy,
    ),
  );
}
