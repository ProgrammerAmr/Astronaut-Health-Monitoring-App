import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'csm_http_transport.dart';

/// Universal HTTP transport built on `package:http`.
///
/// `package:http` picks the right engine per platform (`IOClient` on
/// Android/iOS/desktop, `BrowserClient` on web), so the OrbitCare app can talk
/// to the backend from **every** supported target — including Flutter Web,
/// where a `dart:io` based transport is unavailable.
class PackageHttpCsmTransport implements CsmHttpTransport {
  PackageHttpCsmTransport({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<CsmHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    final request = http.Request(method, uri);
    headers.forEach((key, value) {
      request.headers[key] = value;
    });
    if (body != null) {
      request.bodyBytes = utf8.encode(body);
    }

    final streamed = await _client.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed).timeout(timeout);
    return CsmHttpResponse(
      statusCode: response.statusCode,
      body: response.body,
    );
  }

  void close() => _client.close();
}

CsmHttpTransport createPlatformCsmTransport() => PackageHttpCsmTransport();
