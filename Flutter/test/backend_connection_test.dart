import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasa/cognitive_state/services/csm_http_transport.dart';
import 'package:nasa/core/config/api_config.dart';
import 'package:nasa/core/config/backend_config.dart';
import 'package:nasa/core/services/orbitcare_api_client.dart';

typedef _Responder = Future<CsmHttpResponse> Function(Uri uri);

class _FakeTransport implements CsmHttpTransport {
  _FakeTransport(this._responder);

  final _Responder _responder;
  final List<Uri> requested = <Uri>[];

  @override
  Future<CsmHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    requested.add(uri);
    return _responder(uri);
  }
}

CsmHttpResponse _json(int statusCode, Map<String, dynamic> payload) {
  return CsmHttpResponse(statusCode: statusCode, body: jsonEncode(payload));
}

void main() {
  group('Backend URL resolution', () {
    test('Android falls back to the emulator host alias', () {
      expect(
        defaultApiBaseUrlFor(isWeb: false, platform: TargetPlatform.android),
        'http://10.0.2.2:5000',
      );
    });

    test('other platforms fall back to localhost', () {
      for (final platform in <TargetPlatform>[
        TargetPlatform.iOS,
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        expect(
          defaultApiBaseUrlFor(isWeb: false, platform: platform),
          'http://localhost:5000',
          reason: 'unexpected default for $platform',
        );
      }
    });

    test('web never uses the Android emulator alias', () {
      expect(
        defaultApiBaseUrlFor(isWeb: true, platform: TargetPlatform.android),
        'http://localhost:5000',
      );
    });

    test('a port build flag is honoured by the defaults', () {
      expect(
        defaultApiBaseUrlFor(
          isWeb: false,
          platform: TargetPlatform.android,
          port: '5050',
        ),
        'http://10.0.2.2:5050',
      );
    });

    test('resolution is never empty (the old root cause of login failures)', () {
      final resolved = resolveApiBaseUrlDetails(platform: TargetPlatform.android);
      expect(resolved.url, isNotEmpty);
      expect(isValidApiBaseUrl(resolved.url), isTrue);
    });
  });

  group('BackendConfig runtime override', () {
    test('persists a normalized override and clears it again', () async {
      final store = InMemoryBackendUrlStore();
      final config = BackendConfig(
        store: store,
        isWeb: false,
        platform: TargetPlatform.android,
      );

      // Most common developer input: no scheme, trailing slash.
      final saved = await config.setOverride('192.168.1.42:5000/');
      expect(saved, 'http://192.168.1.42:5000');
      expect(config.effectiveBaseUrl, 'http://192.168.1.42:5000');
      expect(config.source, ApiBaseUrlSource.runtimeOverride);
      expect(await store.read(), 'http://192.168.1.42:5000');

      await config.clearOverride();
      expect(config.effectiveBaseUrl, 'http://10.0.2.2:5000');
      expect(config.source, ApiBaseUrlSource.platformDefault);
      expect(await store.read(), isNull);
    });

    test('restores a previously saved override on load', () async {
      final config = BackendConfig(
        store: InMemoryBackendUrlStore(initialUrl: 'http://10.0.0.7:5000'),
        isWeb: false,
        platform: TargetPlatform.iOS,
      );

      expect(config.isLoaded, isFalse);
      await config.load();
      expect(config.isLoaded, isTrue);
      expect(config.effectiveBaseUrl, 'http://10.0.0.7:5000');
    });

    test('adds the default port when the developer forgets it', () async {
      final config = BackendConfig(store: InMemoryBackendUrlStore());
      expect(await config.setOverride('192.168.1.42'), 'http://192.168.1.42:5000');
      expect(await config.setOverride('http://localhost'), 'http://localhost:5000');
    });

    test('rejects unusable URLs instead of saving them', () async {
      final config = BackendConfig(store: InMemoryBackendUrlStore());

      await expectLater(config.setOverride(''), throwsArgumentError);
      await expectLater(config.setOverride('ftp://host:5000'), throwsArgumentError);
      expect(config.effectiveBaseUrl, isNotEmpty);
    });
  });

  group('BackendConfig.probeHealth', () {
    test('reports a healthy backend', () async {
      final transport = _FakeTransport((uri) async {
        return _json(200, <String, dynamic>{
          'success': true,
          'message': 'OrbitCare API is running',
          'database': 'connected',
        });
      });
      final config = BackendConfig(store: InMemoryBackendUrlStore());

      final result = await config.probeHealth(
        url: 'http://localhost:5000',
        transport: transport,
      );

      expect(result.reachable, isTrue);
      expect(result.statusCode, 200);
      expect(result.message, 'OrbitCare API is running');
      expect(transport.requested.single.toString(),
          'http://localhost:5000/api/health');
    });

    test('explains a refused connection', () async {
      final transport = _FakeTransport((uri) async {
        throw Exception(
          'SocketException: Connection refused (OS Error: No connection could be made)',
        );
      });
      final config = BackendConfig(store: InMemoryBackendUrlStore());

      final result = await config.probeHealth(
        url: 'http://192.168.1.42:5000',
        transport: transport,
      );

      expect(result.reachable, isFalse);
      expect(result.hints, isNotEmpty);
      expect(result.hints.join(' '), contains('npm run dev'));
    });

    test('warns that a physical device cannot use localhost', () async {
      final transport = _FakeTransport((uri) async {
        throw Exception('SocketException: Connection refused');
      });
      final config = BackendConfig(
        store: InMemoryBackendUrlStore(),
        isWeb: false,
        platform: TargetPlatform.android,
      );

      final result = await config.probeHealth(
        url: 'http://localhost:5000',
        transport: transport,
      );

      expect(result.reachable, isFalse);
      expect(result.hints.join(' '), contains('LAN IP'));
    });

    test('flags a wrong port / foreign server (404 on /api/health)', () async {
      final transport = _FakeTransport(
        (uri) async => _json(404, <String, dynamic>{'message': 'Not found'}),
      );
      final config = BackendConfig(store: InMemoryBackendUrlStore());

      final result = await config.probeHealth(
        url: 'http://localhost:3000',
        transport: transport,
      );

      expect(result.reachable, isFalse);
      expect(result.statusCode, 404);
      expect(result.hints.join(' '), contains('/api/health'));
    });
  });

  group('OrbitCareApiClient wiring', () {
    test('keeps an explicitly provided base URL', () {
      final client = OrbitCareApiClient(
        baseUrl: 'https://api.orbitcare.test',
        transport: _FakeTransport((uri) async => _json(200, <String, dynamic>{})),
      );

      expect(client.baseUrl, 'https://api.orbitcare.test');
      expect(client.isConfigured, isTrue);
      expect(client.createCognitiveStateClient().baseUrl,
          'https://api.orbitcare.test');
    });

    test('follows a runtime backend change without a rebuild', () async {
      final config = BackendConfig(
        store: InMemoryBackendUrlStore(),
        isWeb: false,
        platform: TargetPlatform.android,
        registerGlobalProvider: true,
      );
      addTearDown(() {
        BackendConfig.setInstanceForTesting(null);
        runtimeApiBaseUrlProvider = null;
      });

      final requested = <String>[];
      final client = OrbitCareApiClient(
        transport: _FakeTransport((uri) async {
          requested.add(uri.toString());
          return _json(200, <String, dynamic>{
            'status': 'success',
            'data': <String, dynamic>{
              'user': <String, dynamic>{
                '_id': 'u1',
                'name': 'Nova Lin',
                'email': 'nova@example.test',
                'role': 'astronaut',
              },
            },
          });
        }),
      );

      await config.setOverride('http://10.0.2.2:5000');
      expect(client.baseUrl, 'http://10.0.2.2:5000');

      await config.setOverride('http://192.168.1.42:5000');
      expect(client.baseUrl, 'http://192.168.1.42:5000');

      final profile = await client.getMe(token: 'jwt-token');
      expect(profile.id, 'u1');
      expect(profile.name, 'Nova Lin');
      expect(profile.email, 'nova@example.test');
      expect(requested.single, 'http://192.168.1.42:5000/api/users/me');
    });

    test('getMe also accepts a flat data payload', () async {
      final client = OrbitCareApiClient(
        baseUrl: 'https://api.orbitcare.test',
        transport: _FakeTransport(
          (uri) async => _json(200, <String, dynamic>{
            'status': 'success',
            'data': <String, dynamic>{
              '_id': 'u2',
              'name': 'Alex Vance',
              'email': 'alex@example.test',
              'role': 'astronaut',
            },
          }),
        ),
      );

      final profile = await client.getMe(token: 'jwt-token');
      expect(profile.id, 'u2');
      expect(profile.name, 'Alex Vance');
    });
  });
}
