import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/app/api_configuration.dart';
import 'package:frontend/data/datasources/http_analysis_data_source.dart';
import 'package:frontend/domain/models/selected_image.dart';
import 'package:frontend/domain/repositories/analysis_repository.dart';

Map<String, Object?> result(String id) => {
  'id': id,
  'category': 'NonDemented',
  'created_at': '2026-10-20T12:00:00Z',
  'display_name': 'Mi análisis',
  'probability': 0.8,
  'is_demo': false,
  'scores': {
    'NonDemented': 0.8,
    'VeryMildDemented': 0.1,
    'MildDemented': 0.05,
    'ModerateDemented': 0.05,
  },
};

http.Response jsonResponse(Object data, int status) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

SelectedImage image() => SelectedImage(
  name: 'mri.png',
  extension: 'png',
  bytes: Uint8List.fromList([1, 2, 3]),
);

HttpAnalysisDataSource source(
  http.Client client, {
  Future<String?> Function()? token,
  Duration timeout = const Duration(seconds: 120),
}) => HttpAnalysisDataSource(
  baseUri: Uri.parse('https://nerilum-tcsm.onrender.com/api/v1/'),
  client: client,
  accessToken: token ?? () async => 'test-token',
  timeout: timeout,
);

void main() {
  test('Configura Render, normaliza paths y rechaza API con sesiones mock', () {
    const config = ApiConfiguration(
      baseUrl: 'https://nerilum-tcsm.onrender.com',
    );
    config.validate(authMode: 'supabase');
    expect(
      config.baseUri.resolve('analyses').toString(),
      'https://nerilum-tcsm.onrender.com/api/v1/analyses',
    );
    expect(() => config.validate(authMode: 'mock'), throwsStateError);
    expect(
      () =>
          const ApiConfiguration(baseUrl: 'https://user:pass@example.com')
              .validate(authMode: 'supabase'),
      throwsStateError,
    );
    expect(const ApiConfiguration(baseUrl: '').enabled, isFalse);
  });

  test(
    'POST envía token, archivo y nombre e interpreta el contrato de Render',
    () async {
      final api = source(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/analyses');
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(request.followRedirects, isFalse);
          expect(
            request.headers['content-type'],
            startsWith('multipart/form-data'),
          );
          expect(request.body, contains('name="file"; filename="mri.png"'));
          expect(request.body, contains('Mi análisis'));
          return jsonResponse(result('an_1'), 201);
        }),
      );
      addTearDown(api.close);
      final analysis = await api.analyze(image(), displayName: ' Mi análisis ');
      expect(analysis.id, 'an_1');
      expect(analysis.category, 'NonDemented');
      expect(analysis.displayName, 'Mi análisis');
      expect(analysis.probability, 0.8);
    },
  );

  test(
    'Lee todas las páginas sin exigir sort ni funciones aún no desplegadas',
    () async {
      var calls = 0;
      final api = source(
        MockClient((request) async {
          expect(request.url.queryParameters['limit'], '100');
          expect(request.url.queryParameters['offset'], '$calls');
          expect(request.url.queryParameters.containsKey('sort'), isFalse);
          calls++;
          return jsonResponse({
            'items': [result('an_$calls')],
            'total': 2,
            'limit': 100,
            'offset': calls - 1,
          }, 200);
        }),
      );
      addTearDown(api.close);
      expect((await api.history()).map((item) => item.id), ['an_1', 'an_2']);
      expect(calls, 2);
    },
  );

  for (final status in [401, 413, 503]) {
    test('HTTP $status se muestra como error de dominio', () async {
      final api = source(MockClient((_) async => http.Response('{}', status)));
      addTearDown(api.close);
      await expectLater(
        api.analyze(image()),
        throwsA(
          status == 503 ? isA<AnalysisUnavailable>() : isA<AnalysisFailure>(),
        ),
      );
    });
  }

  test(
    'No envía peticiones sin token ni oculta los errores de conexión',
    () async {
      var calls = 0;
      final api = source(
        MockClient((_) async {
          calls++;
          throw http.ClientException('offline');
        }),
        token: () async => null,
      );
      addTearDown(api.close);
      await expectLater(api.history(), throwsA(isA<AnalysisFailure>()));
      expect(calls, 0);
      final offline = source(
        MockClient((_) async => throw http.ClientException('offline')),
      );
      addTearDown(offline.close);
      await expectLater(offline.history(), throwsA(isA<AnalysisFailure>()));
    },
  );

  test('Timeout no reenvía el POST automáticamente', () async {
    var calls = 0;
    final pending = Completer<http.Response>();
    final api = source(
      MockClient((_) {
        calls++;
        return pending.future;
      }),
      timeout: const Duration(milliseconds: 10),
    );
    addTearDown(api.close);
    await expectLater(
      api.analyze(image()),
      throwsA(
        isA<AnalysisFailure>().having(
          (e) => e.message,
          'mensaje',
          contains('historial'),
        ),
      ),
    );
    expect(calls, 1);
    pending.complete(http.Response('{}', 503));
  });
}
