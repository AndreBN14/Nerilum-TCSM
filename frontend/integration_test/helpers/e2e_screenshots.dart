import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

class E2EScreenshots {
  E2EScreenshots(this._tester);

  final WidgetTester _tester;
  Directory? _directory;

  Future<void> initialize() async {
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (android) {
      await IntegrationTestWidgetsFlutterBinding.instance
          .convertFlutterSurfaceToImage();
      final root = await getExternalStorageDirectory();
      if (root != null) {
        _directory = Directory('${root.path}/e2e-screenshots');
        await _directory!.create(recursive: true);
      }
    }
    await _tester.pump();
  }

  Future<void> capture(String name) async {
    try {
      await _tester.pump();
      final bytes = await IntegrationTestWidgetsFlutterBinding.instance
          .takeScreenshot(name);
      final directory = _directory;
      if (bytes.isEmpty || directory == null) {
        return;
      }
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes, flush: true);
    } catch (_) {
      return;
    }
  }
}

Future<void> withE2EScreenshots(
  WidgetTester tester,
  String testName,
  Future<void> Function(E2EScreenshots screenshots) body,
) async {
  final screenshots = E2EScreenshots(tester);
  await screenshots.initialize();
  try {
    await body(screenshots);
  } catch (_) {
    await screenshots.capture('$testName-99-failure');
    rethrow;
  }
}
