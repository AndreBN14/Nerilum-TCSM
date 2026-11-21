import 'package:flutter/foundation.dart';

import '../../domain/models/analysis_result.dart';
import '../../domain/usecases/generate_report.dart';
import '../../domain/usecases/present_report.dart';

class ReportViewModel extends ChangeNotifier {
  ReportViewModel(this.generateReport, this.presentReport, {this.loadImage});
  final GenerateReport generateReport;
  final PresentReport presentReport;
  final Future<Uint8List> Function(String id)? loadImage;

  bool busy = false;
  bool imageLoading = false;
  String? error;
  String? imageError;
  Uint8List? imageBytes;
  bool _disposed = false;

  Future<bool> loadRecordImage(
    AnalysisResult result, {
    Uint8List? cached,
  }) async {
    if (cached != null) {
      imageBytes = cached;
      imageError = null;
      notifyListeners();
      return true;
    }
    if (!result.hasImage) return true;
    if (result.id == null || loadImage == null) {
      imageError = 'No se puede recuperar la imagen del análisis.';
      notifyListeners();
      return false;
    }
    if (imageBytes != null) return true;
    if (imageLoading) return false;
    imageLoading = true;
    imageError = null;
    notifyListeners();
    try {
      final downloaded = await loadImage!(result.id!);
      if (_disposed) return false;
      imageBytes = downloaded;
      return true;
    } catch (_) {
      if (!_disposed) {
        imageError = 'No se pudo recuperar la imagen. Comprueba tu conexión.';
      }
      return false;
    } finally {
      imageLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> export(
    AnalysisResult result, {
    Uint8List? imageBytes,
    Uint8List? gradcamBytes,
    bool share = false,
  }) async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (result.hasImage &&
          (imageBytes ?? this.imageBytes) == null &&
          !await loadRecordImage(result)) {
        error =
            'No se pudo recuperar la imagen para el PDF. Inténtalo de nuevo.';
        return false;
      }
      final bytes = await generateReport(
        result,
        imageBytes: imageBytes ?? this.imageBytes,
        gradcamBytes: gradcamBytes,
      );
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
