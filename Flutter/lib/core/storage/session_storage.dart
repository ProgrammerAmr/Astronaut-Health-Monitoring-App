import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence boundary for OrbitCare JWT tokens, cached user profile metadata,
/// runtime server URL, and isolated offline Demo Mode state.
abstract class SessionStorage {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> deleteToken();

  Future<String?> readUserJson();
  Future<void> writeUserJson(String userJson);

  Future<String?> readApiBaseUrl();
  Future<void> writeApiBaseUrl(String? url);

  // Isolated Demo Mode persistence (never mixed with production auth keys)
  Future<bool> readDemoModeActive();
  Future<void> writeDemoModeActive(bool active);

  Future<String?> readDemoStateJson();
  Future<void> writeDemoStateJson(String? stateJson);

  Future<String?> readDemoPrefsJson();
  Future<void> writeDemoPrefsJson(String? prefsJson);

  Future<void> clear();
}

/// Hardware-backed secure storage implementation using flutter_secure_storage
/// (Android EncryptedSharedPreferences / Keystore, iOS Keychain).
class SecureSessionStorage implements SessionStorage {
  static const String _tokenKey = 'orbitcare_auth_jwt';
  static const String _userKey = 'orbitcare_auth_user_json';
  static const String _apiBaseUrlKey = 'orbitcare_api_base_url';
  static const String _demoActiveKey = 'orbitcare_demo_active';
  static const String _demoStateKey = 'orbitcare_demo_state_json';
  static const String _demoPrefsKey = 'orbitcare_demo_prefs_json';

  final FlutterSecureStorage _storage;

  SecureSessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> _safeWrite(String key, String? value) async {
    try {
      if (value == null || value.isEmpty) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } on MissingPluginException {
      // No native storage plugin in headless/test environment.
    } on PlatformException {
      // Ignore platform storage failures gracefully.
    }
  }

  @override
  Future<String?> readToken() async {
    final token = await _safeRead(_tokenKey);
    if (token == null || token.trim().isEmpty) return null;
    return token.trim();
  }

  @override
  Future<void> writeToken(String token) => _safeWrite(_tokenKey, token);

  @override
  Future<void> deleteToken() => _safeWrite(_tokenKey, null);

  @override
  Future<String?> readUserJson() => _safeRead(_userKey);

  @override
  Future<void> writeUserJson(String userJson) =>
      _safeWrite(_userKey, userJson);

  @override
  Future<String?> readApiBaseUrl() async {
    final url = await _safeRead(_apiBaseUrlKey);
    if (url == null || url.trim().isEmpty) return null;
    return url.trim();
  }

  @override
  Future<void> writeApiBaseUrl(String? url) =>
      _safeWrite(_apiBaseUrlKey, url?.trim());

  @override
  Future<bool> readDemoModeActive() async {
    final val = await _safeRead(_demoActiveKey);
    return val == 'true';
  }

  @override
  Future<void> writeDemoModeActive(bool active) =>
      _safeWrite(_demoActiveKey, active ? 'true' : null);

  @override
  Future<String?> readDemoStateJson() => _safeRead(_demoStateKey);

  @override
  Future<void> writeDemoStateJson(String? stateJson) =>
      _safeWrite(_demoStateKey, stateJson);

  @override
  Future<String?> readDemoPrefsJson() => _safeRead(_demoPrefsKey);

  @override
  Future<void> writeDemoPrefsJson(String? prefsJson) =>
      _safeWrite(_demoPrefsKey, prefsJson);

  @override
  Future<void> clear() async {
    await _safeWrite(_tokenKey, null);
    await _safeWrite(_userKey, null);
  }
}

/// Deterministic in-memory session storage for unit and widget tests.
class InMemorySessionStorage implements SessionStorage {
  String? _token;
  String? _userJson;
  String? _apiBaseUrl;
  bool _demoModeActive;
  String? _demoStateJson;
  String? _demoPrefsJson;

  InMemorySessionStorage({
    String? initialToken,
    String? initialUserJson,
    String? initialApiBaseUrl,
    bool initialDemoModeActive = false,
    String? initialDemoStateJson,
    String? initialDemoPrefsJson,
  })  : _token = initialToken,
        _userJson = initialUserJson,
        _apiBaseUrl = initialApiBaseUrl,
        _demoModeActive = initialDemoModeActive,
        _demoStateJson = initialDemoStateJson,
        _demoPrefsJson = initialDemoPrefsJson;

  @override
  Future<String?> readToken() async =>
      (_token == null || _token!.trim().isEmpty) ? null : _token!.trim();

  @override
  Future<void> writeToken(String token) async {
    _token = token;
  }

  @override
  Future<void> deleteToken() async {
    _token = null;
  }

  @override
  Future<String?> readUserJson() async => _userJson;

  @override
  Future<void> writeUserJson(String userJson) async {
    _userJson = userJson;
  }

  @override
  Future<String?> readApiBaseUrl() async =>
      (_apiBaseUrl == null || _apiBaseUrl!.trim().isEmpty)
          ? null
          : _apiBaseUrl!.trim();

  @override
  Future<void> writeApiBaseUrl(String? url) async {
    final trimmed = url?.trim() ?? '';
    _apiBaseUrl = trimmed.isEmpty ? null : trimmed;
  }

  @override
  Future<bool> readDemoModeActive() async => _demoModeActive;

  @override
  Future<void> writeDemoModeActive(bool active) async {
    _demoModeActive = active;
  }

  @override
  Future<String?> readDemoStateJson() async => _demoStateJson;

  @override
  Future<void> writeDemoStateJson(String? stateJson) async {
    final trimmed = stateJson?.trim() ?? '';
    _demoStateJson = trimmed.isEmpty ? null : trimmed;
  }

  @override
  Future<String?> readDemoPrefsJson() async => _demoPrefsJson;

  @override
  Future<void> writeDemoPrefsJson(String? prefsJson) async {
    final trimmed = prefsJson?.trim() ?? '';
    _demoPrefsJson = trimmed.isEmpty ? null : trimmed;
  }

  @override
  Future<void> clear() async {
    _token = null;
    _userJson = null;
  }
}
