import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/data/datasources/http_analysis_data_source.dart';
import 'package:frontend/domain/models/selected_image.dart';
import 'package:frontend/domain/repositories/analysis_repository.dart';

Map<String, Object?> _result(String id) => {
  'id': id,
  'category': 'NonDemented',
  'created_at': '2026-10-09T12:30:00Z',
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

SelectedImage _image() => SelectedImage(
  name: 'mri.png',
  extension: 'png',
  bytes: Uint8List.fromList([1, 2, 3]),
);

HttpAnalysisDataSource _source(
  http.Client client, {
  Future<String?> Function()? token,
  Duration timeout = const Duration(seconds: 120),
}) => HttpAnalysisDataSource(
  baseUri: Uri.parse('https://api.ejemplo.com/api/v1/'),
  client: client,
  accessToken: token ?? () async => 'test-access-token',
  timeout: timeout,
);

void main() {
  test(
    'Envía archivo, nombre, token e idempotencia y mapea la respuesta',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/analyses');
        expect(request.headers['Authorization'], 'Bearer test-access-token');
        expect(request.headers['Idempotency-Key'], 'operation-1');
        expect(request.followRedirects, isFalse);
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data'),
        );
        expect(request.body, contains('name="file"; filename="mri.png"'));
        expect(request.body, contains('Mi análisis'));
        return http.Response(
          jsonEncode(_result('an_1')),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final source = _source(client);
      addTearDown(source.close);
      final result = await source.analyze(
        _image(),
        displayName: ' Mi análisis ',
        idempotencyKey: 'operation-1',
      );
      expect(result.id, 'an_1');
      expect(result.displayName, 'Mi análisis');
      expect(result.probability, 0.8);
      expect(result.createdAt, DateTime.utc(2026, 10, 9, 12, 30).toLocal());
    },
  );

  test(
    'Recorre todas las páginas del historial sin exponer JSON a las vistas',
    () async {
      var calls = 0;
      final source = _source(
        MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer test-access-token');
          expect(request.url.queryParameters['limit'], '100');
          // El backend usa newest por defecto; tampoco exigir sort a versiones anteriores.
          expect(request.url.queryParameters.containsKey('sort'), isFalse);
          expect(request.url.queryParameters['offset'], '$calls');
          calls++;
          return http.Response(
            jsonEncode({
              'items': [_result('an_$calls')],
              'total': 2,
              'limit': 100,
              'offset': calls - 1,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(source.close);
      expect((await source.history()).map((r) => r.id), ['an_1', 'an_2']);
      expect(calls, 2);
    },
  );

  for (final code in [401, 409, 413, 503]) {
    test('Traduce HTTP $code a un fallo de dominio', () async {
      final source = _source(
        MockClient((_) async => http.Response('{}', code)),
      );
      addTearDown(source.close);
      await expectLater(
        source.analyze(_image(), idempotencyKey: 'operation-1'),
        throwsA(
          code == 503 ? isA<AnalysisUnavailable>() : isA<AnalysisFailure>(),
        ),
      );
    });
  }

  test('No envía solicitudes sin una sesión de usuario', () async {
    var called = false;
    final source = _source(
      MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
      token: () async => null,
    );
    addTearDown(source.close);
    await expectLater(source.history(), throwsA(isA<AnalysisFailure>()));
    expect(called, isFalse);
  });

  test(
    'Consulta por preview_id antes de repetir un guardado incierto',
    () async {
      var calls = 0;
      final source = _source(
        MockClient((request) async {
          calls++;
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/analyses/an_123abc');
          expect(request.headers['Authorization'], 'Bearer test-access-token');
          return calls == 1
              ? http.Response('{}', 404)
              : http.Response(
                  jsonEncode(_result('an_123abc')),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                );
        }),
      );
      addTearDown(source.close);
      expect(await source.findById('an_123abc'), isNull);
      expect((await source.findById('an_123abc'))?.id, 'an_123abc');
      expect(calls, 2);
    },
  );

  test(
    'Previsualización no guarda y el POST de guardado usa prueba firmada',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        expect(request.headers['Authorization'], 'Bearer test-access-token');
        if (request.url.path.endsWith('/preview')) {
          expect(request.method, 'POST');
          expect(request.body, contains('name="file"; filename="mri.png"'));
          return http.Response(
            jsonEncode({
              ..._result('an_123'),
              'preview_id': 'an_123',
              'save_proof': 'signed-test-proof',
              'expires_at': '2026-10-09T13:00:00Z',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'save_proof': 'signed-test-proof',
          'display_name': 'Control',
        });
        return http.Response(
          jsonEncode({..._result('an_123'), 'display_name': 'Control'}),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final source = _source(client);
      addTearDown(source.close);
      final preview = await source.preview(_image());
      expect(preview.result.category, 'NonDemented');
      final saved = await source.savePreview(preview, displayName: ' Control ');
      expect(saved.id, preview.result.id);
      expect(saved.displayName, 'Control');
      expect(paths, ['/api/v1/analyses/preview', '/api/v1/analyses/save']);
    },
  );

  test('Informa fallos de red y respuestas malformadas', () async {
    final network = _source(
      MockClient((_) async => throw http.ClientException('offline')),
    );
    final invalid = _source(
      MockClient((_) async => http.Response('not-json', 200)),
    );
    addTearDown(network.close);
    addTearDown(invalid.close);
    await expectLater(network.history(), throwsA(isA<AnalysisFailure>()));
    await expectLater(invalid.history(), throwsA(isA<AnalysisFailure>()));
  });

  test('Timeout informa que se puede reintentar', () async {
    final pending = Completer<http.Response>();
    final source = _source(
      MockClient((_) => pending.future),
      timeout: const Duration(milliseconds: 10),
    );
    addTearDown(source.close);
    await expectLater(
      source.analyze(_image(), idempotencyKey: 'operation-1'),
      throwsA(
        isA<AnalysisFailure>().having(
          (f) => f.message,
          'mensaje',
          contains('reintentar'),
        ),
      ),
    );
    pending.complete(http.Response('{}', 503));
  });
}
