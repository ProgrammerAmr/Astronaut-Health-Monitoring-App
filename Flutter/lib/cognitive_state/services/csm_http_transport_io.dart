import 'dart:convert';
import 'dart:io';

import 'csm_http_transport.dart';

class _IoCsmHttpTransport implements CsmHttpTransport {
  @override
  Future<CsmHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });
      if (body != null) {
        request.add(utf8.encode(body));
      }
      final response = await request.close().timeout(timeout);
      final responseBody =
          await response.transform(utf8.decoder).join().timeout(timeout);
      return CsmHttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
      );
    } finally {
      client.close(force: true);
    }
  }
}

CsmHttpTransport createPlatformCsmTransport() => _IoCsmHttpTransport();
