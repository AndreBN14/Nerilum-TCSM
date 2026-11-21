import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/app/api_configuration.dart';
import 'package:frontend/app/app_dependencies.dart';
import 'package:frontend/data/datasources/connectivity_data_source.dart';
import 'package:frontend/data/datasources/http_analysis_data_source.dart';
import 'package:frontend/data/datasources/supabase_account_data_source.dart';
import 'package:frontend/data/repositories/encrypted_pending_analysis_repository.dart';
import 'package:frontend/data/repositories/http_analysis_repository.dart';
import 'package:frontend/data/repositories/supabase_account_repository.dart';
import 'package:frontend/domain/repositories/image_repository.dart';
import 'package:frontend/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'e2e_config.dart';
import 'e2e_wait.dart';

Future<Supabase>? _clientInit;

Future<SupabaseClient> _supabaseClient(E2EConfig config) async {
  _clientInit ??= Supabase.initialize(
    url: config.supabaseUrl,
    publishableKey: config.supabaseKey,
  );
  await _clientInit;
  return Supabase.instance.client;
}

class E2ESession {
  E2ESession({
    required this.config,
    required this.dependencies,
    required this.source,
    required this.client,
    required this.pendingAnalyses,
  });

  final E2EConfig config;
  final AppDependencies dependencies;
  final HttpAnalysisDataSource source;
  final SupabaseClient client;
  final EncryptedPendingAnalysisRepository? pendingAnalyses;

  String? get accessToken => client.auth.currentSession?.accessToken;

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    dependencies.dispose();
    source.close();
    if (pendingAnalyses != null) {
      await pendingAnalyses!.close();
    }
  }
}

Future<E2ESession> pumpRealApp(
  WidgetTester tester,
  E2EConfig config, {
  ImageRepository? images,
  Stream<bool>? networkAvailability,
}) async {
  final client = await _supabaseClient(config);
  final source = HttpAnalysisDataSource(
    baseUri: ApiConfiguration(baseUrl: config.apiBaseUrl).baseUri,
    accessToken: () async {
      var session = client.auth.currentSession;
      if (session != null && session.isExpired) {
        session = (await client.auth.refreshSession()).session;
      }
      return session?.accessToken;
    },
  );
  final pending = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? EncryptedPendingAnalysisRepository()
      : null;
  final dependencies = AppDependencies(
    accounts: SupabaseAccountRepository(
      SupabaseAccountDataSource(client, config.redirect),
    ),
    images: images,
    analysis: HttpAnalysisRepository(source),
    pendingAnalyses: pending,
    networkAvailability:
        networkAvailability ??
        (pending == null ? null : const ConnectivityDataSource().available),
    usesRemoteAnalysis: true,
  );
  await dependencies.restoreLocalState();
  await tester.pumpWidget(NerilumApp(dependencies: dependencies));
  await pumpUntilAnyText(tester, const [
    'Iniciar sesión',
    'Inicio',
    'Analizar',
  ], timeout: const Duration(seconds: 45));
  return E2ESession(
    config: config,
    dependencies: dependencies,
    source: source,
    client: client,
    pendingAnalyses: pending,
  );
}
