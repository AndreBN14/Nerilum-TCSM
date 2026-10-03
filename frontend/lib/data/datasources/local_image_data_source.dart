import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';

import '../../domain/models/selected_image.dart';
import '../../domain/repositories/image_repository.dart';

// La selección valida el archivo antes de entregarlo a la interfaz.
class LocalImageDataSource {
  const LocalImageDataSource({this.picker});

  final FilePicker? picker;

  Future<SelectedImage?> pick() async {
    try {
      final result = await (picker ?? FilePicker.platform).pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (result == null) return null;
      final file = result.files.single;
      final extension = file.extension?.toLowerCase();
      if (!['jpg', 'jpeg', 'png'].contains(extension)) {
        throw const ImageSelectionFailure('Selecciona una imagen JPG o PNG.');
      }
      if (file.size > 10 * 1024 * 1024) {
        throw const ImageSelectionFailure(
          'La imagen supera el límite de 10 MB. Elige otra.',
        );
      }
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw const ImageSelectionFailure(
          'No se pudo leer la imagen. Vuelve a seleccionarla.',
        );
      }
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        codec.dispose();
      } catch (_) {
        throw const ImageSelectionFailure(
          'El archivo no contiene una imagen válida. Elige otra.',
        );
      }
      return SelectedImage(
        name: file.name,
        extension: extension!,
        bytes: bytes,
      );
    } on ImageSelectionFailure {
      rethrow;
    } catch (_) {
      throw const ImageSelectionFailure(
        'No se pudo abrir el archivo. Inténtalo de nuevo.',
      );
    }
  }
}
