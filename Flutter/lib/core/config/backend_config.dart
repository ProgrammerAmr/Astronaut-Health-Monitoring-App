import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../cognitive_state/services/csm_http_transport.dart';
import 'api_config.dart';

/// Persistence boundary for the user-selected backend URL.
///
/// Kept tiny and dependency-free so it can be swapped for an in-memory
/// implementation in tests.
abstract class BackendUrlStore {
  Future<String?> read();
  Future<void> write(String url);
  Future<void> clear();
}

/// Default store backed by `flutter_secure_storage`, with an in-memory
/// fallback so a URL change still works on platforms/environments where the
/// native plugin is unavailable (headless tests, some Linux desktops, ...).
class SecureBackendUrlStore implements BackendUrlStore {
  static const String _key = 'orbitcare_backend_base_url';

  SecureBackendUrlStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  String? _memoryFallback;

  @override
  Future<String?> read() async {
    try {
      final value = await _storage.read(key: _key);
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
      return _memoryFallback;
    } catch (_) {
      return _memoryFallback;
    }
  }

  @override
  Future<void> write(String url) async {
    _memoryFallback = url;
    try {
      await _storage.write(key: _key, value: url);
    } catch (_) {
      // In-memory fallback already holds the value for this session.
    }
  }

  @override
  Future<void> clear() async {
    _memoryFallback = null;
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing else to do.
    }
  }
}

/// Deterministic store for tests and for platforms without secure storage.
class InMemoryBackendUrlStore implements BackendUrlStore {
  InMemoryBackendUrlStore({String? initialUrl}) : _url = initialUrl;

  String? _url;

  @override
  Future<String?> read() async => _url;

  @override
  Future<void> write(String url) async {
    _url = url;
  }

  @override
  Future<void> clear() async {
    _url = null;
  }
}

/// Result of a `GET /api/health` probe with actionable, human readable hints.
class BackendProbeResult {
  final String probedUrl;
  final bool reachable;
  final int? statusCode;
  final String message;
  final List<String> hints;
  final Duration elapsed;

  const BackendProbeResult({
    required this.probedUrl,
    required this.reachable,
    required this.message,
    this.statusCode,
    this.hints = const <String>[],
    this.elapsed = Duration.zero,
  });
}

/// Single source of truth for "which backend does this app talk to?".
///
/// The API clients read [effectiveBaseUrl] on every request, so changing the
/// URL from the in-app connection settings screen takes effect immediately —
/// no rebuild and no app restart required.
class BackendConfig extends ChangeNotifier {
  BackendConfig({
    required BackendUrlStore store,
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
    Duration probeTimeout = const Duration(seconds: 6),
    bool registerGlobalProvider = false,
  })  : _store = store,
        _isWeb = isWeb,
        _platform = platform,
        _probeTimeout = probeTimeout {
    if (registerGlobalProvider) {
      runtimeApiBaseUrlProvider = () => _override;
    }
  }

  static BackendConfig? _instance;

  /// App-wide instance. It also installs the global override hook so the
  /// pure-Dart API clients can see a saved URL.
  static BackendConfig get instance => _instance ??= BackendConfig(
        store: SecureBackendUrlStore(),
        registerGlobalProvider: true,
      );

  /// Replaces the app-wide instance (used by tests / storybook-style previews).
  @visibleForTesting
  static void setInstanceForTesting(BackendConfig? config) {
    _instance = config;
    if (config == null) {
      runtimeApiBaseUrlProvider = null;
    }
  }

  final BackendUrlStore _store;
  final bool _isWeb;
  final TargetPlatform? _platform;
  final Duration _probeTimeout;

  String? _override;
  bool _loaded = false;
  bool _isLoading = false;

  bool get isLoaded => _loaded;
  bool get isLoading => _isLoading;
  String? get runtimeOverride => _override;
  bool get isUsingRuntimeOverride =>
      _override != null && _override!.trim().isNotEmpty;

  String get effectiveBaseUrl => resolveApiBaseUrl(
        runtimeOverride: _override,
        isWeb: _isWeb,
        platform: _platform,
      );

  ApiBaseUrlSource get source => resolveApiBaseUrlDetails(
        runtimeOverride: _override,
        isWeb: _isWeb,
        platform: _platform,
      ).source;

  bool get isConfigured => isValidApiBaseUrl(effectiveBaseUrl);

  /// URL the app would use if no runtime override was saved. Handy for the
  /// "reset to default" action in the settings screen.
  String get defaultBaseUrl => defaultApiBaseUrlFor(
        isWeb: _isWeb,
        platform: _platform,
      );

  Future<void> load() async {
    if (_loaded || _isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      final stored = await _store.read();
      if (stored != null && isValidApiBaseUrl(stored)) {
        _override = normalizeApiBaseUrl(stored);
      }
      _loaded = true;
    } catch (_) {
      _loaded = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Validates, normalizes and persists a user supplied backend URL.
  ///
  /// Throws [ArgumentError] with a developer friendly message when the value
  /// cannot possibly work, so the UI never saves a broken URL.
  Future<String> setOverride(String rawUrl) async {
    var candidate = rawUrl.trim();
    if (candidate.isEmpty) {
      throw ArgumentError('Enter a backend URL, for example http://192.168.1.10:5000');
    }

    // Be forgiving about the two most common typos.
    if (!candidate.contains('://')) {
      candidate = 'http://$candidate';
    }
    candidate = normalizeApiBaseUrl(candidate);

    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.isEmpty) {
      throw ArgumentError(
        '"$rawUrl" is not a valid URL. Use http://<host-or-ip>:<port>, for example http://192.168.1.10:5000',
      );
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ArgumentError('The URL must start with http:// or https://');
    }

    // Nobody types ":80" by accident: assume the local backend port instead.
    if (!uri.hasPort) {
      candidate = normalizeApiBaseUrl('$candidate:$kOrbitCareApiPort');
    }

    _override = candidate;
    _loaded = true;
    await _store.write(candidate);
    notifyListeners();
    return candidate;
  }

  Future<void> clearOverride() async {
    _override = null;
    await _store.clear();
    notifyListeners();
  }

  /// Calls `GET /api/health` on [url] (defaults to [effectiveBaseUrl]) and
  /// translates low level network failures into concrete next steps.
  Future<BackendProbeResult> probeHealth({
    String? url,
    CsmHttpTransport? transport,
  }) async {
    final target = normalizeApiBaseUrl(url ?? effectiveBaseUrl);
    if (!isValidApiBaseUrl(target)) {
      return BackendProbeResult(
        probedUrl: target,
        reachable: false,
        message: 'That does not look like a usable backend URL.',
        hints: const <String>[
          'Use the full form http://<host-or-ip>:<port>, for example http://192.168.1.10:5000',
        ],
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      final response = await (transport ?? createDefaultCsmTransport()).send(
        method: 'GET',
        uri: Uri.parse('$target/api/health'),
        headers: const <String, String>{'Accept': 'application/json'},
        timeout: _probeTimeout,
      );
      stopwatch.stop();

      final body = _decodeMap(response.body);
      final serverMessage = (body?['message'] ?? '').toString();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return BackendProbeResult(
          probedUrl: target,
          reachable: true,
          statusCode: response.statusCode,
          elapsed: stopwatch.elapsed,
          message: serverMessage.isEmpty
              ? 'Backend reached successfully.'
              : serverMessage,
        );
      }

      return BackendProbeResult(
        probedUrl: target,
        reachable: false,
        statusCode: response.statusCode,
        elapsed: stopwatch.elapsed,
        message: 'Server answered with HTTP ${response.statusCode}'
            '${serverMessage.isEmpty ? '' : ': $serverMessage'}',
        hints: _hintsForStatusCode(response.statusCode, target),
      );
    } on TimeoutException {
      stopwatch.stop();
      return BackendProbeResult(
        probedUrl: target,
        reachable: false,
        elapsed: stopwatch.elapsed,
        message: 'No answer within ${_probeTimeout.inSeconds}s (timeout).',
        hints: _hintsForTimeout(target),
      );
    } catch (error) {
      stopwatch.stop();
      return BackendProbeResult(
        probedUrl: target,
        reachable: false,
        elapsed: stopwatch.elapsed,
        message: _shortError(error),
        hints: _hintsForError(error, target),
      );
    }
  }

  Map<String, dynamic>? _decodeMap(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  String _shortError(Object error) {
    final text = error.toString();
    if (text.length <= 220) return text;
    return '${text.substring(0, 220)}...';
  }

  List<String> _deviceHints(String target) {
    final hints = <String>[];
    final host = Uri.tryParse(target)?.host ?? '';
    final isLoopback = host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '[::1]';
    if (isLoopback && !_isWeb) {
      hints.add(
        'A physical phone cannot use localhost/127.0.0.1 — that is the phone '
        'itself. Use the PC LAN IP (ipconfig / ifconfig), e.g. http://192.168.1.10:5000.',
      );
    }
    if (host == kAndroidEmulatorHostAlias) {
      hints.add(
        '10.0.2.2 only works inside an Android emulator, never on a real device.',
      );
    }
    return hints;
  }

  List<String> _hintsForStatusCode(int statusCode, String target) {
    final hints = <String>[];
    if (statusCode == 404) {
      hints.add(
        'Something answered on that port but has no /api/health route — '
        'check the port, or that the OrbitCare backend (backend/server.js) is what is running there.',
      );
    } else if (statusCode >= 500) {
      hints.add(
        'The backend is reachable but unhealthy. Check its terminal output '
        '(MongoDB connection, missing .env values) and run `npm run doctor` inside backend/.',
      );
    }
    hints.addAll(_deviceHints(target));
    return hints;
  }

  List<String> _hintsForTimeout(String target) {
    return <String>[
      'A timeout usually means a firewall dropped the packets. On Windows allow '
      'Node.js through the firewall or run: netsh advfirewall firewall add rule '
      'name="OrbitCare API" dir=in action=allow protocol=TCP localport=5000',
      'Confirm the backend is listening on 0.0.0.0 (backend/server.js already does).',
      ..._deviceHints(target),
    ];
  }

  List<String> _hintsForError(Object error, String target) {
    final text = error.toString().toLowerCase();
    final hints = <String>[];

    if (text.contains('cleartext') || text.contains('network security policy')) {
      hints.add(
        'Android blocked plain HTTP. Rebuild the app after pulling the latest '
        'android/app/src/main/AndroidManifest.xml (android:usesCleartextTraffic="true").',
      );
    } else if (text.contains('failed host lookup') ||
        text.contains('name or service not known') ||
        text.contains('nodename nor servname')) {
      hints.add('The hostname could not be resolved — check for typos in the host.');
    } else if (text.contains('certificate') ||
        text.contains('handshake') ||
        text.contains('ssl')) {
      hints.add(
        'TLS handshake failed. Local development should use http:// (not https://) '
        'unless the backend really has a valid certificate.',
      );
    } else if (text.contains('connection refused') ||
        text.contains('socketexception') ||
        text.contains('network is unreachable') ||
        text.contains('no route to host') ||
        text.contains('connection was not established') ||
        text.contains('unsupportedoperationerror')) {
      hints.add(
        'Nothing accepted the connection. Start the backend first: cd backend && npm run dev, '
        'then verify on the PC with: curl http://127.0.0.1:5000/api/health',
      );
    } else if (_isWeb ||
        text.contains('clientexception') ||
        text.contains('xmlhttprequest') ||
        text.contains('failed to fetch')) {
      hints.add(
        'In a browser the underlying reason is hidden: either the backend is not '
        'running, or the request was blocked (CORS / mixed content). Check the '
        'browser DevTools console and network tab.',
      );
    }

    hints.add(
      'Make sure the device and the PC running the backend are on the same Wi-Fi network.',
    );
    hints.addAll(_deviceHints(target));
    return hints;
  }
}
