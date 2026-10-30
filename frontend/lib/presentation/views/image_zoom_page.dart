import 'package:flutter/material.dart';

import '../../domain/models/selected_image.dart';

class ImageZoomPage extends StatelessWidget {
  const ImageZoomPage({super.key, required this.image});

  final SelectedImage image;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(title: Text(image.name)),
    body: Center(
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 6,
        child: Image.memory(image.bytes, fit: BoxFit.contain),
      ),
    ),
  );
}
