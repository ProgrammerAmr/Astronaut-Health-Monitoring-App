import 'csm_http_transport_http.dart' as platform_transport;

class CsmHttpResponse {
  final int statusCode;
  final String body;

  const CsmHttpResponse({
    required this.statusCode,
    required this.body,
  });
}

abstract class CsmHttpTransport {
  Future<CsmHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  });
}

/// Default transport for every platform (mobile, desktop **and web**).
///
/// Previously this resolved to a `dart:io` implementation with a stub that
/// threw `UnsupportedError` on Flutter Web, which made every login attempt
/// fail in a browser. The `package:http` based transport works everywhere.
CsmHttpTransport createDefaultCsmTransport() =>
    platform_transport.createPlatformCsmTransport();
