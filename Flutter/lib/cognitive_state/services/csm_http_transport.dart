import 'csm_http_transport_stub.dart'
    if (dart.library.io) 'csm_http_transport_io.dart' as platform_transport;

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

CsmHttpTransport createDefaultCsmTransport() =>
    platform_transport.createPlatformCsmTransport();
