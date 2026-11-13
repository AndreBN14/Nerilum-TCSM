import 'dart:typed_data';
import 'dart:async';

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
    this.gradcamBytes,
  });

  final AnalysisResult result;
  final Uint8List? imageBytes;
  final Uint8List? gradcamBytes;

  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  ReportViewModel? _report;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_report == null) {
      _report = AppScope.of(context).createReportViewModel();
      unawaited(
        _report!.loadRecordImage(widget.result, cached: widget.imageBytes),
      );
    }
  }

  @override
  void dispose() {
    _report?.dispose();
    super.dispose();
  }

  Future<void> _export({bool share = false}) async {
    final success = await _report!.export(
      widget.result,
      imageBytes: _report!.imageBytes,
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
      imageBytes: _report!.imageBytes,
      gradcamBytes: widget.gradcamBytes,
      imageLoading: _report!.imageLoading,
      imageError: _report!.imageError,
      onRetryImage: _report!.imageError != null
          ? () => _report!.loadRecordImage(widget.result)
          : null,
      onBack: () => Navigator.of(context).pop(),
      onExport: () => _export(),
      onShare: () => _export(share: true),
      exporting: _report!.busy,
    ),
  );
}
