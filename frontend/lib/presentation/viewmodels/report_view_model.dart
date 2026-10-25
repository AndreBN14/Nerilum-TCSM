import 'package:flutter/foundation.dart';

import '../../domain/models/analysis_result.dart';
import '../../domain/usecases/generate_report.dart';

class ReportViewModel extends ChangeNotifier {
  ReportViewModel(this.generateReport);
  final GenerateReport generateReport;

  bool busy = false;
  String? error;
  bool _disposed = false;

  Future<Uint8List?> create(
    AnalysisResult result, {
    Uint8List? imageBytes,
  }) async {
    if (busy) return null;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final bytes = await generateReport(result, imageBytes: imageBytes);
      return _disposed ? null : bytes;
    } catch (_) {
      if (!_disposed) error = 'No se pudo generar el PDF. Vuelve a intentarlo.';
      return null;
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
