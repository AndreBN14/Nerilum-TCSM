import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/domain/models/analysis_result.dart';
import 'package:frontend/domain/repositories/report_output_repository.dart';
import 'package:frontend/domain/repositories/report_repository.dart';
import 'package:frontend/domain/usecases/generate_report.dart';
import 'package:frontend/domain/usecases/present_report.dart';
import 'package:frontend/presentation/viewmodels/report_view_model.dart';

class _Pdf implements ReportRepository {
  @override
  Future<Uint8List> buildPdf(
    AnalysisResult analysis, {
    Uint8List? imageBytes,
  }) async => Uint8List.fromList([1, 2, 3]);
}

class _Output implements ReportOutputRepository {
  String? action;
  String? filename;
  bool fail = false;

  @override
  Future<void> open(Uint8List bytes, {required String filename}) async {
    if (fail) throw StateError('Fallo al abrir');
    action = 'open';
    this.filename = filename;
    expect(bytes, [1, 2, 3]);
  }

  @override
  Future<void> share(Uint8List bytes, {required String filename}) async {
    action = 'share';
    this.filename = filename;
    expect(bytes, [1, 2, 3]);
  }
}

void main() {
  test(
    'El ViewModel delega abrir y compartir; mantiene visible el error',
    () async {
      final output = _Output();
      final model = ReportViewModel(
        GenerateReport(_Pdf()),
        PresentReport(output),
      );
      addTearDown(model.dispose);
      final result = AnalysisResult(
        displayName: 'Caso 1 / revisión',
        category: 'NonDemented',
        createdAt: DateTime.utc(2026, 10, 24),
      );

      expect(await model.export(result), isTrue);
      expect(output.action, 'open');
      expect(output.filename, 'Caso_1___revisi_n.pdf');
      expect(await model.export(result, share: true), isTrue);
      expect(output.action, 'share');

      output.fail = true;
      expect(await model.export(result), isFalse);
      expect(model.error, contains('PDF'));
      expect(model.busy, isFalse);
    },
  );
}
