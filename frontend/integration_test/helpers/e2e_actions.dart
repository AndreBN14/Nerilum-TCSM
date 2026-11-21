import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'e2e_config.dart';
import 'e2e_wait.dart';

Future<void> login(WidgetTester tester, E2EConfig config) async {
  await pumpUntilAnyText(tester, const ['Iniciar sesión', 'Inicio']);
  if (find.text('Iniciar sesión').evaluate().isEmpty) {
    return;
  }
  await tester.tap(find.text('Iniciar sesión'));
  await pumpUntilText(tester, 'Ingresar');
  final fields = find.byType(TextFormField);
  expect(fields, findsNWidgets(2));
  await tester.enterText(fields.at(0), config.email);
  await tester.enterText(fields.at(1), config.password);
  await tester.tap(find.text('Ingresar'));
  await pumpUntilAnyText(tester, const [
    'Inicio',
    'Analizar',
  ], timeout: const Duration(seconds: 90));
}

Future<void> logout(WidgetTester tester) async {
  await tester.tap(find.text('Perfil').first);
  await pumpUntilText(tester, 'Cerrar sesión');
  await tester.tap(find.text('Cerrar sesión').first);
  await pumpUntilText(tester, '¿Quieres salir de tu cuenta?');
  await tester.tap(find.text('Cerrar sesión').last);
  await pumpUntilAnyText(tester, const [
    'Iniciar sesión',
    'Registrarse',
  ], timeout: const Duration(seconds: 60));
}

Future<void> openAnalysisTab(WidgetTester tester) async {
  await tester.tap(find.text('Analizar'));
  await pumpUntilText(tester, 'Nuevo análisis');
}

Future<void> selectE2EImage(WidgetTester tester) async {
  final selector = find.bySemanticsLabel('Seleccionar imagen');
  expect(selector, findsOneWidget);
  await tester.tap(selector);
  await pumpUntilText(tester, 'e2e-scan.png');
}

Future<void> analyzeAndOpenPreview(WidgetTester tester) async {
  await tester.tap(find.text('Analizar imagen'));
  await pumpUntilText(
    tester,
    'Guardar en historial',
    timeout: const Duration(seconds: 180),
  );
}

Future<void> savePreview(WidgetTester tester, E2EConfig config) async {
  final nameField = find.byType(TextFormField);
  if (nameField.evaluate().isNotEmpty) {
    await tester.enterText(nameField.first, config.displayName);
  }
  await tester.tap(find.text('Guardar en historial'));
  await pumpUntilAnyText(tester, const [
    'Inicio',
    'Analizar',
  ], timeout: const Duration(seconds: 120));
}

Future<void> openHistory(WidgetTester tester) async {
  await tester.tap(find.text('Inicio'));
  await pumpUntilText(tester, 'Ver todo');
  final link = find.text('Ver todo');
  await tester.tap(link.first);
  await pumpUntilText(tester, 'Historial');
}
