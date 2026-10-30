import 'package:flutter/foundation.dart';

import '../../domain/models/analysis_result.dart';
import '../../domain/usecases/generate_report.dart';
import '../../domain/usecases/present_report.dart';

class ReportViewModel extends ChangeNotifier {
  ReportViewModel(this.generateReport, this.presentReport);
  final GenerateReport generateReport;
  final PresentReport presentReport;

  bool busy = false;
  String? error;
  bool _disposed = false;

  Future<bool> export(
    AnalysisResult result, {
    Uint8List? imageBytes,
    bool share = false,
  }) async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final bytes = await generateReport(result, imageBytes: imageBytes);
      if (_disposed) return false;
      final rawName = result.displayName ?? 'analisis_nerilum';
      final safeName = rawName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final filename =
          '${safeName.isEmpty ? 'analisis_nerilum' : safeName}.pdf';
      await presentReport(bytes, filename: filename, share: share);
      return !_disposed;
    } catch (_) {
      if (!_disposed) {
        error = 'No se pudo generar o abrir el PDF. Inténtalo de nuevo.';
      }
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
