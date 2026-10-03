import '../../domain/models/selected_image.dart';
import '../../domain/repositories/image_repository.dart';
import '../datasources/local_image_data_source.dart';

class LocalImageRepository implements ImageRepository {
  const LocalImageRepository(this.source);
  final LocalImageDataSource source;

  @override
  Future<SelectedImage?> select() => source.pick();
}
