import 'dart:typed_data';

import '../repositories/report_output_repository.dart';

class PresentReport {
  const PresentReport(this.repository);

  final ReportOutputRepository repository;

  Future<void> call(
    Uint8List bytes, {
    required String filename,
    bool share = false,
  }) => share
      ? repository.share(bytes, filename: filename)
      : repository.open(bytes, filename: filename);
}
