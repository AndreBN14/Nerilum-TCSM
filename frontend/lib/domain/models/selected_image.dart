import 'dart:typed_data';

class SelectedImage {
  const SelectedImage({
    required this.name,
    required this.extension,
    required this.bytes,
  });

  final String name;
  final String extension;
  final Uint8List bytes;
}
