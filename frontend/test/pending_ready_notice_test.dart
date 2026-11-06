import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app/app_dependencies.dart';
import 'package:frontend/domain/models/analysis_preview.dart';
import 'package:frontend/domain/models/analysis_result.dart';
import 'package:frontend/domain/models/pending_analysis.dart';
import 'package:frontend/domain/models/selected_image.dart';
import 'package:frontend/domain/repositories/analysis_repository.dart';
import 'package:frontend/domain/repositories/image_repository.dart';
import 'package:frontend/domain/repositories/pending_analysis_repository.dart';
import 'package:frontend/domain/repositories/preview_repository.dart';
import 'package:frontend/main.dart';
import 'package:frontend/presentation/views/preview_result_page.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _Image implements ImageRepository {
  @override
  Future<SelectedImage?> select() async => SelectedImage(
    name: 'nueva.png',
    extension: 'png',
    bytes: Uint8List.fromList([1, 2, 3]),
  );
}

class _Remote implements AnalysisRepository, PreviewRepository {
  bool connected = false;
  int calls = 0;

  @override
  Future<AnalysisPreview> preview(SelectedImage image) async {
    if (!connected) throw const AnalysisNetworkFailure('Sin conexión');
    calls++;
    return AnalysisPreview(
      result: AnalysisResult(
        id: 'an_abc123',
        category: 'NonDemented',
        createdAt: DateTime.now().toUtc(),
        probability: .8,
        scores: const {
          'NonDemented': .8,
          'VeryMildDemented': .1,
          'MildDemented': .06,
          'ModerateDemented': .04,
        },
      ),
      saveProof: 'proof',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 30)),
    );
  }

  @override
  Future<AnalysisResult> save(
    AnalysisPreview preview,
    SelectedImage image, {
    String? displayName,
  }) async => throw StateError('No debe guardarse automáticamente');

  @override
  Future<AnalysisResult> saveWithoutImage(
    AnalysisPreview preview, {
    String? displayName,
  }) async => throw StateError('No debe guardarse automáticamente');

  @override
  Future<AnalysisResult> analyze(
    SelectedImage image, {
    String? displayName,
    String? idempotencyKey,
  }) async => throw StateError('No usar legado');

  @override
  Future<List<AnalysisResult>> history() async => [];
}

class _Queue implements PendingAnalysisRepository {
  _Queue(this.item);
  final PendingAnalysis item;
  @override
  Future<List<PendingAnalysis>> list(String ownerId) async =>
      ownerId == item.ownerId ? [item] : [];
  @override
  Future<PendingAnalysis?> find(String ownerId, String id) async =>
      ownerId == item.ownerId && id == item.id ? item : null;
  @override
  Future<SelectedImage> image(String ownerId, String id) async => SelectedImage(
    name: item.filename,
    extension: 'png',
    bytes: Uint8List.fromList([1, 2, 3]),
  );
  @override
  Future<PendingAnalysis> enqueue(String ownerId, SelectedImage image) async =>
      item;
  @override
  Future<void> discard(String ownerId, String id) async {}
  @override
  Future<void> resetPreview(String ownerId, String id) async {}
  @override
  Future<void> releaseExpiredSave(String ownerId, String id) async {}
  @override
  Future<void> beginSave(
    String ownerId,
    String id, {
    required String previewId,
    required String proof,
    required DateTime expiresAt,
    required String name,
  }) async {}
  @override
  Future<void> complete(String ownerId, String id) async {}
}

void main() {
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  testWidgets(
    'Al reconectar ofrece ver resultado o dejarlo para más tarde una sola vez',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = StreamController<bool>.broadcast();
      addTearDown(events.close);
      final remote = _Remote();
      final deps = AppDependencies(
        images: _Image(),
        analysis: remote,
        networkAvailability: events.stream,
      );
      addTearDown(deps.dispose);
      await deps.accountRepository.login('demo@nerilum.app', 'Demo1234');
      final ownerId = deps.accountRepository.currentAccount!.id;
      final queue = _Queue(
        PendingAnalysis(
          id: 'local-1',
          ownerId: ownerId,
          filename: 'scan.png',
          extension: 'png',
          createdAt: DateTime.now().toUtc(),
          status: 'pending',
        ),
      );
      // La cola se inyecta antes de construir la app para habilitar la sincronización.
      final connectedDeps = AppDependencies(
        images: _Image(),
        analysis: remote,
        pendingAnalyses: queue,
        networkAvailability: events.stream,
        accounts: deps.accountRepository,
      );
      addTearDown(connectedDeps.dispose);
      await tester.pumpWidget(NerilumApp(dependencies: connectedDeps));
      await tester.pumpAndSettle();
      expect(find.text('Resultado listo'), findsNothing);
      remote.connected = true;
      events.add(true);
      await tester.pumpAndSettle();
      expect(remote.calls, 1);
      expect(find.text('Resultado listo'), findsOneWidget);
      expect(find.text('Ver resultado'), findsOneWidget);
      await tester.tap(find.text('Más tarde'));
      await tester.pumpAndSettle();
      events.add(true);
      await tester.pumpAndSettle();
      expect(find.text('Resultado listo'), findsNothing);
      expect(remote.calls, 1);
      expect(connectedDeps.mainViewModel.preview, isNotNull);
      await tester.tap(find.text('Ver todo'));
      await tester.pumpAndSettle();
      expect(
        find.text('Resultado listo para revisar · sin guardar'),
        findsOneWidget,
      );
      await tester.tap(find.text('scan.png'));
      await tester.pumpAndSettle();
      expect(find.byType(PreviewResultPage), findsOneWidget);
    },
  );

  testWidgets(
    'Si hay otra imagen seleccionada explica por qué no abre el pendiente',
    (tester) async {
      final remote = _Remote();
      final deps = AppDependencies(images: _Image(), analysis: remote);
      addTearDown(deps.dispose);
      await deps.accountRepository.login('demo@nerilum.app', 'Demo1234');
      final queue = _Queue(
        PendingAnalysis(
          id: 'local-2',
          ownerId: deps.accountRepository.currentAccount!.id,
          filename: 'scan.png',
          extension: 'png',
          createdAt: DateTime.now().toUtc(),
          status: 'pending',
        ),
      );
      final connectedDeps = AppDependencies(
        images: _Image(),
        analysis: remote,
        pendingAnalyses: queue,
        accounts: deps.accountRepository,
      );
      addTearDown(connectedDeps.dispose);
      await tester.pumpWidget(NerilumApp(dependencies: connectedDeps));
      await tester.pumpAndSettle();
      connectedDeps.mainViewModel.selectTab(1);
      await connectedDeps.mainViewModel.pickImage();
      connectedDeps.mainViewModel.selectTab(0);
      remote.connected = true;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver todo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('scan.png'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Quita o termina la imagen seleccionada'),
        findsOneWidget,
      );
      expect(remote.calls, 0);
    },
  );

  testWidgets(
    'Ver resultado desde el aviso abre la previsualización sin guardar',
    (tester) async {
      final events = StreamController<bool>.broadcast();
      addTearDown(events.close);
      final remote = _Remote();
      final deps = AppDependencies(images: _Image(), analysis: remote);
      addTearDown(deps.dispose);
      await deps.accountRepository.login('demo@nerilum.app', 'Demo1234');
      final queue = _Queue(
        PendingAnalysis(
          id: 'local-3',
          ownerId: deps.accountRepository.currentAccount!.id,
          filename: 'scan.png',
          extension: 'png',
          createdAt: DateTime.now().toUtc(),
          status: 'pending',
        ),
      );
      final connectedDeps = AppDependencies(
        images: _Image(),
        analysis: remote,
        pendingAnalyses: queue,
        networkAvailability: events.stream,
        accounts: deps.accountRepository,
      );
      addTearDown(connectedDeps.dispose);
      await tester.pumpWidget(NerilumApp(dependencies: connectedDeps));
      await tester.pumpAndSettle();
      remote.connected = true;
      events.add(true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver resultado'));
      await tester.pumpAndSettle();
      expect(find.byType(PreviewResultPage), findsOneWidget);
      expect(connectedDeps.mainViewModel.result, isNull);
      expect(connectedDeps.mainViewModel.activePendingId, 'local-3');
    },
  );
}
