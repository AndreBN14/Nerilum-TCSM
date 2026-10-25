import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:frontend/app/app_dependencies.dart';
import 'package:frontend/main.dart';
import 'package:frontend/domain/models/analysis_result.dart';
import 'package:frontend/domain/models/appearance.dart';
import 'package:frontend/domain/models/selected_image.dart';
import 'package:frontend/domain/repositories/analysis_repository.dart';
import 'package:frontend/domain/repositories/appearance_repository.dart';
import 'package:frontend/domain/repositories/image_repository.dart';

class _Images implements ImageRepository {
  @override
  Future<SelectedImage?> select() async => SelectedImage(
    name: 'prueba.png',
    extension: 'png',
    bytes: Uint8List.fromList([1]),
  );
}

class _Analysis implements AnalysisRepository {
  final result = AnalysisResult(
    category: 'MildDemented',
    displayName: 'Caso de prueba',
    probability: 0.83,
    createdAt: DateTime(2026, 9, 29),
  );

  @override
  Future<AnalysisResult> analyze(
    SelectedImage image, {
    String? displayName,
    String? idempotencyKey,
  }) async {
    expect(image.name, 'prueba.png');
    return result;
  }

  @override
  Future<List<AnalysisResult>> history() async => [result];
}

class _Appearance implements AppearanceRepository {
  AppAppearance stored = AppAppearance.dark;

  @override
  Future<AppAppearance> load() async => stored;

  @override
  Future<void> save(AppAppearance appearance) async {
    stored = appearance;
  }
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  test(
    'El flujo por capas permite sustituir repositorios sin tocar vistas',
    () async {
      final analysis = _Analysis();
      final dependencies = AppDependencies(
        images: _Images(),
        analysis: analysis,
        settings: _Appearance(),
      );
      addTearDown(dependencies.dispose);

      final auth = dependencies.createAuthViewModel();
      addTearDown(auth.dispose);
      expect(await auth.login('demo@nerilum.app', 'Demo1234'), isTrue);
      expect(dependencies.mainViewModel.account?.name, 'Cuenta demo');

      final model = dependencies.mainViewModel;
      await model.selectFromHome();
      expect(model.tab, 1);
      expect(model.image?.name, 'prueba.png');
      await model.analyze();
      expect(model.result?.category, 'MildDemented');
      expect(model.analyses, [analysis.result]);
      await model.logout();
      expect(model.account, isNull);
      expect(model.image, isNull);
      expect(model.analyses, isEmpty);
    },
  );

  test(
    'La apariencia pasa por el repositorio y conserva la selección',
    () async {
      final repository = _Appearance();
      final dependencies = AppDependencies(settings: repository);
      addTearDown(dependencies.dispose);
      final model = dependencies.appearanceViewModel;
      expect(model.appearance, AppAppearance.dark);
      expect(await model.setAppearance(AppAppearance.light), isTrue);
      expect(repository.stored, AppAppearance.light);
      await model.load();
      expect(model.appearance, AppAppearance.light);
    },
  );

  test('El adaptador sin API no fabrica resultados de clasificación', () async {
    final dependencies = AppDependencies(images: _Images());
    addTearDown(dependencies.dispose);
    final model = dependencies.mainViewModel;
    await model.pickImage();
    await model.analyze();
    expect(model.result, isNull);
    expect(model.analyses, isEmpty);
    expect(model.error, contains('aún no está conectado'));
  });

  testWidgets(
    'Una respuesta real del repositorio se muestra en Inicio e historial',
    (tester) async {
      final dependencies = AppDependencies(analysis: _Analysis());
      addTearDown(dependencies.dispose);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(NerilumApp(dependencies: dependencies));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ya tengo cuenta'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'demo@nerilum.app',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'Demo1234');
      await tester.ensureVisible(find.text('Ingresar'));
      await tester.tap(find.text('Ingresar'));
      await tester.pumpAndSettle();
      expect(find.text('Caso de prueba'), findsOneWidget);
      await tester.tap(find.text('Ver todo'));
      await tester.pumpAndSettle();
      expect(find.text('Caso de prueba'), findsOneWidget);
      expect(find.text('MildDemented'), findsOneWidget);
      await tester.tap(find.text('Caso de prueba'));
      await tester.pumpAndSettle();
      expect(find.text('Detalle del análisis'), findsOneWidget);
      expect(find.text('Puntuación del modelo: 83,00 %'), findsOneWidget);
    },
  );
}
