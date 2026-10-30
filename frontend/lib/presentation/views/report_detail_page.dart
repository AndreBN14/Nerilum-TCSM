import 'dart:typed_data';

import 'package:flutter/material.dart';

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
    final success = await _report!.export(
      widget.result,
      imageBytes: widget.imageBytes,
      share: share,
    );
    if (!mounted) return;
    if (!success && _report!.error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_report!.error!)));
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
