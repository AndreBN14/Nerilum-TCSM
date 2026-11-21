import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:frontend/app/api_configuration.dart';

import 'e2e_config.dart';

class E2EApiClient {
  E2EApiClient(this.config, this.tokenProvider);

  final E2EConfig config;
  final String? Function() tokenProvider;

  Uri get base =>
      ApiConfiguration(baseUrl: config.verificationApiBaseUrl).baseUri;

  Map<String, String> get headers {
    final token = tokenProvider();
    if (token == null || token.isEmpty) {
      throw StateError('La sesión E2E no tiene access token');
    }
    return {'Authorization': 'Bearer $token', 'Accept': 'application/json'};
  }

  Future<http.Response> get(String path, {Map<String, String>? query}) {
    return http.get(
      base.resolve(path).replace(queryParameters: query),
      headers: headers,
    );
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final response = await get(path, query: query);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('GET $path -> ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getRootJson(String path) async {
    final parsed = Uri.parse(config.verificationApiBaseUrl);
    final root = parsed.replace(path: '/', query: '', fragment: '');
    final response = await http.get(
      root.resolve(path.replaceFirst(RegExp(r'^/+'), '')),
      headers: headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('GET $path -> ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
