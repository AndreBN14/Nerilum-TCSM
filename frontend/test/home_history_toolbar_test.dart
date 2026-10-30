import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/nerilum_theme.dart';
import 'package:frontend/domain/models/history_sort.dart';
import 'package:frontend/presentation/views/home_view.dart';
import 'package:frontend/presentation/widgets/history_sort_control.dart';
import 'package:frontend/presentation/widgets/history_status.dart';

void main() {
  testWidgets(
    'Inicio pone orden y actualización en la misma fila en ancho de teléfono',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var refreshed = 0;
      HistorySort? changedSort;

      Widget home({String? error, bool loading = false}) => MaterialApp(
        theme: NerilumTheme.dark,
        home: Scaffold(
          body: HomeView(
            onProfile: () {},
            onSelectImage: () {},
            onHistory: () {},
            analyses: const [],
            onOpenAnalysis: (_) {},
            historySort: HistorySort.newest,
            onSortChanged: (value) => changedSort = value,
            historyLoading: loading,
            historyError: error,
            onRefreshHistory: () => refreshed++,
          ),
        ),
      );

      await tester.pumpWidget(home());
      await tester.ensureVisible(find.byTooltip('Actualizar historial'));
      await tester.pumpAndSettle();
      final sort = find.byType(HistorySortControl);
      final refresh = find.byTooltip('Actualizar historial');
      expect(tester.widget<HistorySortControl>(sort).compact, isTrue);
      expect(find.text('Actualizar historial'), findsNothing);
      expect(
        (tester.getTopLeft(sort).dy - tester.getTopLeft(refresh).dy).abs(),
        lessThan(12),
      );
      await tester.tap(find.byType(DropdownButton<HistorySort>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Puntuación').last);
      await tester.pumpAndSettle();
      expect(changedSort, HistorySort.probability);
      await tester.tap(refresh);
      expect(refreshed, 1);

      await tester.pumpWidget(home(error: 'Sin conexión'));
      await tester.ensureVisible(find.byTooltip('Reintentar historial'));
      await tester.pumpAndSettle();
      expect(find.text('Sin conexión'), findsOneWidget);
      await tester.tap(find.byTooltip('Reintentar historial'));
      expect(refreshed, 2);

      await tester.pumpWidget(home(loading: true));
      await tester.ensureVisible(find.byTooltip('Actualizar historial'));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip('Actualizar historial'),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Cargando historial…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('La vista completa conserva su botón de actualizar con texto', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryStatus(loading: false, error: null, onRetry: () {}),
        ),
      ),
    );
    expect(find.text('Actualizar historial'), findsOneWidget);
  });
}
