import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';

/// Calls the Cloudflare Worker with the user's Supabase access token. The
/// Worker verifies the JWT itself, so it scales to zero with no session state.
class EdgeClient {
  EdgeClient(this._db, {http.Client? client, String? baseUrl})
      : _http = client ?? http.Client(),
        baseUrl = baseUrl ?? Env.edgeBaseUrl;

  final SupabaseClient _db;
  final http.Client _http;
  final String baseUrl;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (_db.auth.currentSession?.accessToken != null)
          'authorization': 'Bearer ${_db.auth.currentSession!.accessToken}',
      };

  void _requireConfigured() {
    if (baseUrl.isEmpty) throw EdgeException(0, 'edge_not_configured');
  }

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? query]) async {
    _requireConfigured();
    final res = await _http
        .get(Uri.parse('$baseUrl$path').replace(queryParameters: query), headers: _headers)
        .timeout(const Duration(seconds: 20));
    return _decode(res);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    _requireConfigured();
    final res = await _http
        .post(Uri.parse('$baseUrl$path'), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) throw EdgeException(res.statusCode, body['error']?.toString() ?? 'error');
    return body;
  }
}

class EdgeException implements Exception {
  EdgeException(this.status, this.code);
  final int status;
  final String code;
  @override
  String toString() => code == 'edge_not_configured'
      ? 'This feature needs the Convoy Worker (set EDGE_BASE_URL in env.json).'
      : 'EdgeException($status, $code)';
}
