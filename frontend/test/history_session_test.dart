import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app/app_dependencies.dart';
import 'package:frontend/data/datasources/mock_session_data_source.dart';
import 'package:frontend/domain/models/history_sort.dart';
import 'package:frontend/main.dart';
import 'package:frontend/presentation/widgets/main_components.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test(
    'Sesión mock y orden se restauran; cerrar sesión no borra el orden',
    () async {
      final first = AppDependencies();
      addTearDown(first.dispose);
      final auth = first.createAuthViewModel();
      addTearDown(auth.dispose);
      expect(await auth.login('demo@nerilum.app', 'Demo1234'), isTrue);
      await first.mainViewModel.refreshHistory();
      expect(first.mainViewModel.analyses, hasLength(4));
      expect(
        await first.mainViewModel.setHistorySort(HistorySort.nameAZ),
        isTrue,
      );
      expect(
        first.mainViewModel.analyses.first.displayName,
        'Control de seguimiento',
      );

      final stored = await SharedPreferencesAsync().getString(
        LocalMockSessionDataSource.key,
      );
      expect(stored, contains('demo@nerilum.app'));
      expect(stored, isNot(contains('Demo1234')));

      final reopened = AppDependencies();
      addTearDown(reopened.dispose);
      await reopened.restoreLocalState();
      expect(reopened.accountRepository.currentAccount?.name, 'Cuenta demo');
      expect(reopened.mainViewModel.historySort, HistorySort.nameAZ);
      expect(
        reopened.mainViewModel.analyses.first.displayName,
        'Control de seguimiento',
      );

      await reopened.mainViewModel.logout();
      final loggedOut = AppDependencies();
      addTearDown(loggedOut.dispose);
      await loggedOut.restoreLocalState();
      expect(loggedOut.accountRepository.currentAccount, isNull);
      expect(loggedOut.mainViewModel.analyses, isEmpty);
      expect(loggedOut.mainViewModel.historySort, HistorySort.nameAZ);
      expect(
        await SharedPreferencesAsync().getString(
          LocalMockSessionDataSource.key,
        ),
        isNull,
      );
    },
  );

  test('Cuenta nueva no hereda análisis mock de la cuenta demo', () async {
    final first = AppDependencies();
    addTearDown(first.dispose);
    final auth = first.createAuthViewModel();
    addTearDown(auth.dispose);
    expect(await auth.register('ana@ejemplo.com', 'Clave1234', 'Ana'), isTrue);
    expect(await auth.login('ana@ejemplo.com', 'Clave1234'), isTrue);
    await first.mainViewModel.refreshHistory();
    expect(first.mainViewModel.analyses, isEmpty);

    final reopened = AppDependencies();
    addTearDown(reopened.dispose);
    await reopened.restoreLocalState();
    expect(reopened.accountRepository.currentAccount?.name, 'Ana');
    expect(reopened.mainViewModel.analyses, isEmpty);
  });

  testWidgets(
    'Inicio e Historial comparten el orden y el splash restaura sesión',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final first = AppDependencies();
      addTearDown(first.dispose);
      final auth = first.createAuthViewModel();
      addTearDown(auth.dispose);
      expect(await auth.login('demo@nerilum.app', 'Demo1234'), isTrue);

      final reopened = AppDependencies();
      addTearDown(reopened.dispose);
      await reopened.restoreLocalState();
      await tester.pumpWidget(NerilumApp(dependencies: reopened));
      await tester.pumpAndSettle();
      expect(find.text('Análisis recientes'), findsOneWidget);
      expect(find.text('Comenzar'), findsNothing);
      expect(find.text('Exploración inicial'), findsOneWidget);
      expect(find.text('MildDemented'), findsNothing);

      await tester.tap(find.text('Más recientes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Probabilidad').last);
      await tester.pumpAndSettle();
      expect(
        reopened.mainViewModel.analyses.first.displayName,
        'Revisión de imagen',
      );
      expect(
        tester
            .widget<ResultCard>(find.byType(ResultCard).first)
            .result
            .displayName,
        'Revisión de imagen',
      );

      await tester.tap(find.text('Ver todo'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ResultCard>(find.byType(ResultCard).first)
            .result
            .displayName,
        'Revisión de imagen',
      );
      expect(find.text('Probabilidad').first, findsOneWidget);
      await tester.tap(find.text('Probabilidad').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Más antiguos').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ResultCard>(find.byType(ResultCard).first)
            .result
            .displayName,
        'Estudio de referencia',
      );

      final afterRestart = AppDependencies();
      addTearDown(afterRestart.dispose);
      await afterRestart.restoreLocalState();
      expect(afterRestart.mainViewModel.historySort, HistorySort.oldest);
      expect(
        afterRestart.accountRepository.currentAccount?.email,
        'demo@nerilum.app',
      );

      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cerrar sesión'));
      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('Comenzar'), findsOneWidget);

      final afterLogout = AppDependencies();
      addTearDown(afterLogout.dispose);
      await afterLogout.restoreLocalState();
      expect(afterLogout.accountRepository.currentAccount, isNull);
      expect(afterLogout.mainViewModel.historySort, HistorySort.oldest);
    },
  );
}
