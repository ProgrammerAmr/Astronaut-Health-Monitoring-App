import 'csm_http_transport.dart';

class _StubCsmHttpTransport implements CsmHttpTransport {
  @override
  Future<CsmHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    throw UnsupportedError(
      'Default HTTP transport requires dart:io; inject a custom CsmHttpTransport for this platform.',
    );
  }
}

CsmHttpTransport createPlatformCsmTransport() => _StubCsmHttpTransport();
