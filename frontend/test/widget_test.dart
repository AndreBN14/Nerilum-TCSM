import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:frontend/main.dart';
import 'package:frontend/presentation/views/splash_screen.dart';
import 'package:frontend/presentation/theme/nerilum_theme.dart';

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );
  testWidgets('La entrada permanece visible hasta completar cuatro segundos', (
    tester,
  ) async {
    await tester.pumpWidget(const NerilumApp());
    await tester.pump(const Duration(milliseconds: 3500));
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Explora imágenes\ncerebrales'), findsOneWidget);
  });

  testWidgets('Entrada conduce a bienvenida y las dos rutas son distintas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NerilumApp());
    await tester.pumpAndSettle();

    expect(find.text('Explora imágenes\ncerebrales'), findsOneWidget);
    await tester.tap(find.text('Comenzar'));
    await tester.pumpAndSettle();
    expect(find.text('Crear cuenta'), findsWidgets);

    await tester.ensureVisible(find.text('Inicia sesión'));
    await tester.tap(find.text('Inicia sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Demo: demo@nerilum.app / Demo1234'), findsOneWidget);
  });

  testWidgets('El login valida el correo y admite una cuenta de demostración', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NerilumApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ya tengo cuenta'));
    await tester.tap(find.text('Ya tengo cuenta'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ingresar'));
    await tester.pump();
    expect(find.text('Introduce tu correo electrónico'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'demo@nerilum.app',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Demo1234');
    await tester.ensureVisible(find.text('Ingresar'));
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
    expect(find.text('Análisis recientes'), findsOneWidget);
    expect(find.text('Exploración inicial'), findsOneWidget);
    await tester.tap(find.text('Analizar'));
    await tester.pumpAndSettle();
    expect(find.text('Ninguna imagen seleccionada'), findsOneWidget);
    expect(
      find.widgetWithText(ElevatedButton, 'Analizar imagen'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Analizar imagen'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Mi perfil'), findsOneWidget);
    expect(find.text('demo@nerilum.app'), findsOneWidget);
    await tester.tap(find.text('Historial completo'));
    await tester.pumpAndSettle();
    expect(find.text('Exploración inicial'), findsOneWidget);
  });

  testWidgets('El registro valida confirmación y crea una cuenta simulada', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const NerilumApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comenzar'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Ana');
    await tester.enterText(find.byType(TextFormField).at(1), 'ana@example.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'Clave1234');
    await tester.enterText(find.byType(TextFormField).at(3), 'Otra1234');
    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Crear cuenta'),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Crear cuenta'));
    await tester.pump();
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(3), 'Clave1234');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Crear cuenta'),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Crear cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });

  testWidgets(
    'Preferencias cambia claro y oscuro en todas las vistas y guarda la elección',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      bool? savedLightMode;
      await tester.pumpWidget(
        NerilumApp(saveLightMode: (light) async => savedLightMode = light),
      );
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
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preferencias'));
      await tester.pumpAndSettle();

      expect(
        Theme.of(tester.element(find.text('Apariencia'))).brightness,
        Brightness.dark,
      );
      await tester.tap(find.text('Claro'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 325));
      final intermediate = NerilumPalette.of(
        tester.element(find.text('Apariencia')),
      );
      expect(intermediate.background, isNot(NerilumPalette.dark.background));
      expect(intermediate.background, isNot(NerilumPalette.light.background));
      await tester.pumpAndSettle();
      expect(savedLightMode, isTrue);
      expect(
        Theme.of(tester.element(find.text('Apariencia'))).brightness,
        Brightness.light,
      );

      // Simula un nuevo inicio con la preferencia recuperada del almacenamiento.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        NerilumApp(
          initialLightMode: savedLightMode!,
          saveLightMode: (light) async => savedLightMode = light,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Ya tengo cuenta'))).brightness,
        Brightness.light,
      );
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

      expect(
        Theme.of(tester.element(find.text('Análisis recientes'))).brightness,
        Brightness.light,
      );
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preferencias'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oscuro'));
      await tester.pumpAndSettle();
      expect(savedLightMode, isFalse);
      expect(
        Theme.of(tester.element(find.text('Apariencia'))).brightness,
        Brightness.dark,
      );
    },
  );
}
