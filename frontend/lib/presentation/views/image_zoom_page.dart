import 'package:flutter/material.dart';

import '../../domain/models/selected_image.dart';

class ImageZoomPage extends StatelessWidget {
  const ImageZoomPage({super.key, required this.image});

  final SelectedImage image;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(image.name)),
      body: SizedBox(
        width: size.width,
        height: size.height,
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 8,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          child: Center(
            child: Image.memory(
              image.bytes,
              width: size.width,
              height: size.height,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
