import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/domain/models/analysis_result.dart';
import 'package:frontend/domain/repositories/report_output_repository.dart';
import 'package:frontend/domain/repositories/report_repository.dart';
import 'package:frontend/domain/usecases/generate_report.dart';
import 'package:frontend/domain/usecases/present_report.dart';
import 'package:frontend/presentation/viewmodels/report_view_model.dart';

class _Pdf implements ReportRepository {
  Uint8List? lastImage;
  Uint8List? lastGradcam;
  @override
  Future<Uint8List> buildPdf(
    AnalysisResult analysis, {
    Uint8List? imageBytes,
    Uint8List? gradcamBytes,
  }) async {
    lastImage = imageBytes;
    lastGradcam = gradcamBytes;
    return Uint8List.fromList([1, 2, 3]);
  }
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

  test(
    'Reabre un análisis y recupera su original antes de generar el PDF',
    () async {
      final pdf = _Pdf();
      final output = _Output();
      var calls = 0;
      final model = ReportViewModel(
        GenerateReport(pdf),
        PresentReport(output),
        loadImage: (id) async {
          expect(id, 'an_abc123');
          calls++;
          return Uint8List.fromList([7, 8, 9]);
        },
      );
      addTearDown(model.dispose);
      final record = AnalysisResult(
        id: 'an_abc123',
        category: 'NonDemented',
        createdAt: DateTime.utc(2026),
        hasImage: true,
      );
      expect(await model.loadRecordImage(record), isTrue);
      expect(model.imageBytes, [7, 8, 9]);
      expect(await model.export(record), isTrue);
      expect(pdf.lastImage, [7, 8, 9]);
      expect(calls, 1);
    },
  );

  test('Reabre un análisis y recupera el mapa persistido antes del PDF', () async {
    final pdf = _Pdf();
    var calls = 0;
    final model = ReportViewModel(
      GenerateReport(pdf),
      PresentReport(_Output()),
      loadGradcam: (id) async {
        expect(id, 'an_abc123');
        calls++;
        return Uint8List.fromList([10, 11, 12]);
      },
    );
    addTearDown(model.dispose);
    final record = AnalysisResult(
      id: 'an_abc123',
      category: 'NonDemented',
      createdAt: DateTime.utc(2026),
      hasGradcam: true,
    );

    expect(await model.loadRecordGradcam(record), isTrue);
    expect(model.gradcamBytes, [10, 11, 12]);
    expect(await model.export(record), isTrue);
    expect(pdf.lastGradcam, [10, 11, 12]);
    expect(calls, 1);
  });

  test('El PDF recibe también el Grad-CAM cuando está disponible', () async {
    final pdf = _Pdf();
    final model = ReportViewModel(
      GenerateReport(pdf),
      PresentReport(_Output()),
    );
    addTearDown(model.dispose);
    final result = AnalysisResult(
      displayName: 'Caso',
      category: 'NonDemented',
      createdAt: DateTime.utc(2026, 10, 24),
    );
    final gradcam = Uint8List.fromList([4, 5, 6]);

    expect(await model.export(result, gradcamBytes: gradcam), isTrue);
    expect(pdf.lastGradcam, gradcam);
  });

  test('No genera un PDF incompleto cuando falta la imagen asociada', () async {
    final pdf = _Pdf();
    final model = ReportViewModel(
      GenerateReport(pdf),
      PresentReport(_Output()),
      loadImage: (_) async => throw StateError('sin red'),
    );
    addTearDown(model.dispose);
    final record = AnalysisResult(
      id: 'an_abc123',
      category: 'NonDemented',
      createdAt: DateTime.utc(2026),
      hasImage: true,
    );
    expect(await model.export(record), isFalse);
    expect(model.error, contains('imagen'));
    expect(pdf.lastImage, isNull);
  });
}
