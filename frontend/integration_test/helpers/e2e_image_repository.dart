import 'package:flutter/services.dart';
import 'package:frontend/domain/models/selected_image.dart';
import 'package:frontend/domain/repositories/image_repository.dart';

import 'e2e_config.dart';

class E2EImageRepository implements ImageRepository {
  E2EImageRepository(this.config);

  final E2EConfig config;

  @override
  Future<SelectedImage?> select() async {
    final data = await rootBundle.load(config.imageAsset);
    return SelectedImage(
      name: 'e2e-scan.png',
      extension: 'png',
      bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
}
