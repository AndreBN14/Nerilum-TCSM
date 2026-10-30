import 'dart:typed_data';

import 'package:printing/printing.dart';

import '../../domain/repositories/report_output_repository.dart';

class PrintingReportOutputRepository implements ReportOutputRepository {
  const PrintingReportOutputRepository();

  @override
  Future<void> open(Uint8List bytes, {required String filename}) async {
    await Printing.layoutPdf(name: filename, onLayout: (_) async => bytes);
  }

  @override
  Future<void> share(Uint8List bytes, {required String filename}) =>
      Printing.sharePdf(bytes: bytes, filename: filename);
}
