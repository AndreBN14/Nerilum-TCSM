import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app/app_dependencies.dart';
import 'package:frontend/core/utils/score_text.dart';
import 'package:frontend/domain/models/analysis_result.dart';
import 'package:frontend/domain/models/selected_image.dart';
import 'package:frontend/domain/repositories/analysis_repository.dart';
import 'package:frontend/main.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _History implements AnalysisRepository {
  @override
  Future<AnalysisResult> analyze(
    SelectedImage image, {
    String? displayName,
    String? idempotencyKey,
  }) async => throw StateError('No se realiza inferencia');

  @override
  Future<List<AnalysisResult>> history() async => [
    AnalysisResult(
      id: 'an_1',
      displayName: 'Control de seguimiento',
      createdAt: DateTime(2026, 10, 24, 18, 59),
      category: 'VeryMildDemented',
      probability: .72,
      scores: const {
        'NonDemented': .08,
        'VeryMildDemented': .72,
        'MildDemented': .16,
        'ModerateDemented': .04,
      },
      modelName: 'yolov8n-cls',
      modelVersion: 'v0.1',
    ),
    AnalysisResult(
      id: 'an_2',
      displayName: 'Revisión anual',
      createdAt: DateTime(2026, 10, 23),
      category: 'NonDemented',
    ),
  ];
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test('Formato no convierte una puntuación menor de 1 en 100 %', () {
    expect(scoreText(.999999), '99,99 %');
    expect(scoreText(1), '100,00 %');
    expect(scoreText(.000001), '<0,01 %');
  });

  testWidgets('Historial a ancho completo, búsqueda y detalle accesible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final deps = AppDependencies(analysis: _History());
    addTearDown(deps.dispose);
    await tester.pumpWidget(NerilumApp(dependencies: deps));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'demo@nerilum.app',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Demo1234');
    await tester.ensureVisible(find.text('Ingresar'));
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver todo'));
    await tester.pumpAndSettle();
    expect(find.text('Historial'), findsOneWidget);
    expect(find.text('Control de seguimiento'), findsOneWidget);
    expect(find.text('VeryMildDemented'), findsOneWidget);
    expect(find.text('Análisis sin nombre'), findsNothing);

    await tester.tap(find.byTooltip('Buscar por nombre'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'sin coincidencia');
    await tester.pumpAndSettle();
    expect(
      find.text('No hay análisis que coincidan con la búsqueda o el filtro.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Borrar búsqueda'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filtrar por clase'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ModerateDemented').last);
    await tester.pumpAndSettle();
    expect(
      find.text('No hay análisis que coincidan con la búsqueda o el filtro.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Filtrar por clase'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todas las clases').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Control de seguimiento'));
    await tester.tap(find.text('Control de seguimiento'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle del análisis'), findsOneWidget);
    expect(find.text('Puntuación del modelo: 72,00 %'), findsOneWidget);
    expect(find.byIcon(Icons.hide_image_outlined), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Modelo: yolov8n-cls · v0.1'),
      find.byType(ListView).last,
      const Offset(0, -360),
    );
    await tester.pump();
    expect(find.text('Modelo: yolov8n-cls · v0.1'), findsOneWidget);
  });
}
