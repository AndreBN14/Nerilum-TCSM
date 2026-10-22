import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/analysis_result.dart';
import '../../domain/models/selected_image.dart';
import '../../domain/repositories/analysis_repository.dart';
import '../dto/analysis_result_dto.dart';

class HttpAnalysisDataSource {
  HttpAnalysisDataSource({
    required this.baseUri,
    required this.accessToken,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  }) : _client = client ?? http.Client();

  final Uri baseUri;
  final Future<String?> Function() accessToken;
  final Duration timeout;
  final http.Client _client;

  Future<Map<String, dynamic>> _send(http.BaseRequest request) async {
    String? token;
    try {
      token = await accessToken();
    } catch (_) {
      throw const AnalysisFailure(
        'No se pudo recuperar la sesión. Vuelve a iniciar sesión.',
      );
    }
    if (token == null || token.isEmpty) {
      throw const AnalysisFailure('Inicia sesión para acceder al backend.');
    }
    request.headers['Authorization'] = 'Bearer $token';
    request.followRedirects = false;
    http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      throw const AnalysisFailure(
        'El servidor tardó demasiado. Puedes reintentar la misma operación.',
      );
    } on http.ClientException {
      throw const AnalysisFailure(
        'No se pudo conectar con el backend. Comprueba la dirección y la red.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 503) {
        throw const AnalysisUnavailable(
          'El backend o el modelo aún no están disponibles. Inténtalo más tarde.',
        );
      }
      throw AnalysisFailure(switch (response.statusCode) {
        401 => 'La sesión no es válida o expiró. Vuelve a iniciar sesión.',
        403 => 'No tienes permiso para realizar esta operación.',
        409 => 'La operación ya se envió con otro contenido. Selecciona de nuevo la imagen para iniciar otra.',
        413 => 'La imagen supera el tamaño permitido por el servidor.',
        400 ||
        415 ||
        422 => 'El servidor rechazó la imagen o los datos del análisis.',
        429 => 'Demasiadas solicitudes. Espera antes de reintentar.',
        _ => 'No se pudo completar la solicitud al backend.',
      });
    }
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map<String, dynamic>) throw const FormatException();
      return json;
    } on FormatException {
      throw const AnalysisFailure(
        'El backend devolvió una respuesta no válida.',
      );
    }
  }

  Future<AnalysisResult> analyze(
    SelectedImage image, {
    String? displayName,
    String? idempotencyKey,
  }) async {
    final request = http.MultipartRequest('POST', baseUri.resolve('analyses'));
    if (idempotencyKey != null) {
      request.headers['Idempotency-Key'] = idempotencyKey;
    }
    if (displayName != null && displayName.trim().isNotEmpty) {
      request.fields['display_name'] = displayName.trim();
    }
    request.files.add(
      http.MultipartFile.fromBytes('file', image.bytes, filename: image.name),
    );
    final json = await _send(request);
    try {
      return AnalysisResultDto.fromJson(json);
    } on FormatException {
      throw const AnalysisFailure(
        'El backend devolvió un resultado no válido.',
      );
    }
  }

  Future<List<AnalysisResult>> history() async {
    // El contrato de dominio actual trabaja con una lista completa. Recorrer
    // todas las páginas evita ordenar solo una fracción del historial en la UI.
    final records = <String, AnalysisResult>{};
    var offset = 0;
    while (true) {
      final uri = baseUri
          .resolve('analyses')
          .replace(
            queryParameters: {
              'limit': '100',
              'offset': '$offset',
              'sort': 'newest',
            },
          );
      final json = await _send(http.Request('GET', uri));
      try {
        final items = json['items'];
        final total = json['total'];
        if (items is! List || total is! int || total < 0) {
          throw const FormatException();
        }
        for (final item in items) {
          if (item is! Map<String, dynamic>) throw const FormatException();
          final result = AnalysisResultDto.fromJson(item);
          records[result.id!] = result;
        }
        offset += items.length;
        if (offset >= total) break;
        if (items.isEmpty) throw const FormatException();
      } on FormatException {
        throw const AnalysisFailure(
          'El backend devolvió un historial no válido.',
        );
      }
    }
    return List.unmodifiable(records.values);
  }

  void close() => _client.close();
}
