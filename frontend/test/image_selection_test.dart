import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/datasources/local_image_data_source.dart';
import 'package:frontend/domain/repositories/image_repository.dart';

class _FakePicker extends FilePicker {
  _FakePicker(this.result);
  final FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    expect(type, FileType.custom);
    expect(allowedExtensions, containsAll(['jpg', 'jpeg', 'png']));
    expect(withData, isTrue);
    return result;
  }
}

void main() {
  test('Cancelar la selección no cambia el estado del análisis', () async {
    final service = LocalImageDataSource(picker: _FakePicker(null));
    expect(await service.pick(), isNull);
  });

  test('Rechaza archivos que no son imágenes válidas', () async {
    final file = PlatformFile(
      name: 'imagen.jpg',
      size: 4,
      bytes: Uint8List.fromList([1, 2, 3, 4]),
    );
    final service = LocalImageDataSource(
      picker: _FakePicker(FilePickerResult([file])),
    );
    await expectLater(
      service.pick(),
      throwsA(
        isA<ImageSelectionFailure>().having(
          (failure) => failure.message,
          'mensaje',
          contains('no contiene una imagen válida'),
        ),
      ),
    );
  });
}
