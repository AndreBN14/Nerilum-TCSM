import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/data/models/analysis_result_dto.dart';
import 'package:frontend/data/repositories/pdf_report_repository.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/e2e_actions.dart';
import 'helpers/e2e_api.dart';
import 'helpers/e2e_app.dart';
import 'helpers/e2e_config.dart';
import 'helpers/e2e_image_repository.dart';
import 'helpers/e2e_screenshots.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('preview, guardado con imagen y PDF reales', (tester) async {
    final config = E2EConfig.fromEnvironment();
    config.validate();
    await withE2EScreenshots(tester, 'analysis', (shots) async {
      final session = await pumpRealApp(
        tester,
        config,
        images: E2EImageRepository(config),
      );
      addTearDown(() => session.dispose(tester));

      await shots.capture('analysis-01-app');
      await login(tester, config);
      await shots.capture('analysis-02-login');
      await openAnalysisTab(tester);
      await shots.capture('analysis-03-analysis');
      await selectE2EImage(tester);
      await shots.capture('analysis-04-image');
      await analyzeAndOpenPreview(tester);
      await shots.capture('analysis-05-preview');
      await savePreview(tester, config);
      await shots.capture('analysis-06-saved');

      final api = E2EApiClient(config, () => session.accessToken);
      final list = await api.getJson(
        'analyses',
        query: {'limit': '100', 'offset': '0'},
      );
      final items = (list['items'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final saved = items.firstWhere(
        (item) => item['display_name'] == config.displayName,
        orElse: () =>
            throw StateError('No aparece el análisis guardado en la API'),
      );
      expect(saved['has_image'], isTrue);

      final id = saved['id'] as String;
      final detail = await api.getJson('analyses/$id');
      expect(detail['id'], id);

      final image = await api.get('analyses/$id/image');
      expect(image.statusCode, 200);
      expect(String.fromCharCodes(image.bodyBytes.take(4)), '\x89PNG');

      final pdf = await const PdfReportRepository().buildPdf(
        AnalysisResultDto.fromJson(detail),
        imageBytes: image.bodyBytes,
        gradcamBytes: session.dependencies.mainViewModel.gradcamForRecord(id),
      );
      expect(ascii.decode(pdf.sublist(0, 4)), '%PDF');
    });
  });
}
