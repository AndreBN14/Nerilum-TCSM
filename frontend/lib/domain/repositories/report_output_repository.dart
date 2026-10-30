import 'dart:typed_data';

abstract class ReportOutputRepository {
  Future<void> open(Uint8List bytes, {required String filename});
  Future<void> share(Uint8List bytes, {required String filename});
}
