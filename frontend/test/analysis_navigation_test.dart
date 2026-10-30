import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app/app_dependencies.dart';
import 'package:frontend/domain/models/analysis_preview.dart';
import 'package:frontend/domain/models/analysis_result.dart';
import 'package:frontend/domain/models/selected_image.dart';
import 'package:frontend/domain/repositories/analysis_repository.dart';
import 'package:frontend/domain/repositories/image_repository.dart';
import 'package:frontend/domain/repositories/preview_repository.dart';
import 'package:frontend/main.dart';
import 'package:frontend/presentation/views/analysis_view.dart';
import 'package:frontend/presentation/views/image_zoom_page.dart';
import 'package:frontend/presentation/views/preview_result_page.dart';
import 'package:frontend/presentation/widgets/main_components.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Images implements ImageRepository {
  @override
  Future<SelectedImage?> select() async {
    final data = await rootBundle.load('assets/nerilum-mark-512.png');
    return SelectedImage(
      name: 'imagen.png',
      extension: 'png',
      bytes: data.buffer.asUint8List(),
    );
  }
}

class _Analysis implements AnalysisRepository, PreviewRepository {
  int saved = 0;
  bool failSave = false;

  @override
  Future<AnalysisPreview> preview(SelectedImage image) async => AnalysisPreview(
    result: AnalysisResult(
      id: 'an_test',
      category: 'NonDemented',
      probability: .8,
      scores: const {
        'NonDemented': .8,
        'VeryMildDemented': .1,
        'MildDemented': .06,
        'ModerateDemented': .04,
      },
      createdAt: DateTime.utc(2026, 10, 24),
    ),
    saveProof: 'proof',
    expiresAt: DateTime.utc(2026, 10, 24, 1),
  );

  @override
  Future<AnalysisResult> save(
    AnalysisPreview preview, {
    String? displayName,
  }) async {
    if (failSave) throw const AnalysisFailure('No se pudo guardar.');
    saved++;
    return AnalysisResult(
      id: preview.result.id,
      category: preview.result.category,
      probability: preview.result.probability,
      scores: preview.result.scores,
      createdAt: preview.result.createdAt,
      displayName: displayName,
    );
  }

  @override
  Future<AnalysisResult> analyze(
    SelectedImage image, {
    String? displayName,
    String? idempotencyKey,
  }) async => throw StateError('No se usa el endpoint antiguo');

  @override
  Future<List<AnalysisResult>> history() async => [];
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  testWidgets(
    'Imagen ampliable, resultado separado y aviso al volver sin guardar',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final analysis = _Analysis();
      final deps = AppDependencies(images: _Images(), analysis: analysis);
      addTearDown(deps.dispose);
      final auth = deps.createAuthViewModel();
      addTearDown(auth.dispose);
      await auth.login('demo@nerilum.app', 'Demo1234');
      await tester.pumpWidget(NerilumApp(dependencies: deps));
      await tester.pumpAndSettle();
      deps.mainViewModel.selectTab(1);
      await deps.mainViewModel.pickImage();
      await tester.pumpAndSettle();
      expect(find.text('Nombre del análisis (opcional)'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('selected-image-zoom')));
      await tester.pumpAndSettle();
      expect(find.byType(ImageZoomPage), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('Analizar imagen'),
        find.byType(ListView).last,
        const Offset(0, -300),
      );
      await tester.tap(find.text('Analizar imagen'));
      await tester.pumpAndSettle();
      expect(find.byType(PreviewResultPage), findsOneWidget);
      expect(find.byType(AnalysisView), findsNothing);
      expect(find.text('Nombre del análisis (opcional)'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ResultCard),
          matching: find.byType(TextFormField),
        ),
        findsOneWidget,
      );
      expect(find.byType(Table), findsNothing);
      expect(analysis.saved, 0);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.textContaining('perderás este análisis'), findsOneWidget);
      await tester.tap(find.text('Seguir aquí'));
      await tester.pumpAndSettle();
      expect(deps.mainViewModel.preview, isNotNull);
      await tester.tap(find.byTooltip('Volver al análisis'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salir sin guardar'));
      await tester.pumpAndSettle();
      expect(deps.mainViewModel.preview, isNull);
      expect(find.byType(AnalysisView), findsOneWidget);
      expect(analysis.saved, 0);

      await tester.ensureVisible(find.text('Analizar imagen'));
      await tester.tap(find.text('Analizar imagen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'Mi análisis');
      expect(deps.mainViewModel.analysisName, 'Mi análisis');
      expect(find.text('Mi análisis'), findsOneWidget);
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('Guardar en historial'),
        find.byType(ListView).last,
        const Offset(0, -350),
      );
      await tester.tap(find.text('Guardar en historial'));
      await tester.pumpAndSettle();
      expect(analysis.saved, 1);
      expect(find.text('Detalle del análisis'), findsOneWidget);
      expect(find.byType(Table), findsNothing);
    },
  );

  testWidgets(
    'Guardar desde el aviso mantiene el resultado si falla el guardado',
    (tester) async {
      final analysis = _Analysis()..failSave = true;
      final deps = AppDependencies(images: _Images(), analysis: analysis);
      addTearDown(deps.dispose);
      final auth = deps.createAuthViewModel();
      addTearDown(auth.dispose);
      await auth.login('demo@nerilum.app', 'Demo1234');
      await tester.pumpWidget(NerilumApp(dependencies: deps));
      await tester.pumpAndSettle();
      deps.mainViewModel.selectTab(1);
      await deps.mainViewModel.pickImage();
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('Analizar imagen'),
        find.byType(ListView).last,
        const Offset(0, -300),
      );
      await tester.tap(find.text('Analizar imagen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Volver al análisis'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.byType(PreviewResultPage), findsOneWidget);
      expect(deps.mainViewModel.preview, isNotNull);
      expect(deps.mainViewModel.error, 'No se pudo guardar.');

      analysis.failSave = false;
      await tester.tap(find.byTooltip('Volver al análisis'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Detalle del análisis'), findsOneWidget);
      expect(analysis.saved, 1);
    },
  );
}
