import '../models/selected_image.dart';

class ImageSelectionFailure implements Exception {
  const ImageSelectionFailure(this.message);
  final String message;
}

abstract class ImageRepository {
  // Devuelve null si el usuario cancela la selección.
  Future<SelectedImage?> select();
}
