import '../models/selected_image.dart';
import '../repositories/image_repository.dart';

class SelectImage {
  const SelectImage(this.repository);
  final ImageRepository repository;
  Future<SelectedImage?> call() => repository.select();
}
