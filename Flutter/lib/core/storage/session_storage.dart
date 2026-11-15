import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence boundary for OrbitCare JWT tokens and cached user profile metadata.
abstract class SessionStorage {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> deleteToken();

  Future<String?> readUserJson();
  Future<void> writeUserJson(String userJson);

  Future<String?> readApiBaseUrl();
  Future<void> writeApiBaseUrl(String? url);

  Future<void> clear();
}

/// Hardware-backed secure storage implementation using flutter_secure_storage
/// (Android EncryptedSharedPreferences / Keystore, iOS Keychain).
class SecureSessionStorage implements SessionStorage {
  static const String _tokenKey = 'orbitcare_auth_jwt';
  static const String _userKey = 'orbitcare_auth_user_json';
  static const String _apiBaseUrlKey = 'orbitcare_api_base_url';

  final FlutterSecureStorage _storage;

  SecureSessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> readToken() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token == null || token.trim().isEmpty) return null;
      return token.trim();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> writeToken(String token) async {
    try {
      await _storage.write(key: _tokenKey, value: token);
    } on MissingPluginException {
      // No native storage plugin in headless/test environment.
    } on PlatformException {
      // Ignore platform storage failures gracefully.
    }
  }

  @override
  Future<void> deleteToken() async {
    try {
      await _storage.delete(key: _tokenKey);
    } on MissingPluginException {
      // Ignore in headless environment.
    } on PlatformException {
      // Ignore platform storage failures gracefully.
    }
  }

  @override
  Future<String?> readUserJson() async {
    try {
      return await _storage.read(key: _userKey);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> writeUserJson(String userJson) async {
    try {
      await _storage.write(key: _userKey, value: userJson);
    } on MissingPluginException {
      // Ignore in headless environment.
    } on PlatformException {
      // Ignore platform storage failures gracefully.
    }
  }

  @override
  Future<String?> readApiBaseUrl() async {
    try {
      final url = await _storage.read(key: _apiBaseUrlKey);
      if (url == null || url.trim().isEmpty) return null;
      return url.trim();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> writeApiBaseUrl(String? url) async {
    try {
      final trimmed = url?.trim() ?? '';
      if (trimmed.isEmpty) {
        await _storage.delete(key: _apiBaseUrlKey);
      } else {
        await _storage.write(key: _apiBaseUrlKey, value: trimmed);
      }
    } on MissingPluginException {
      // Ignore in headless environment.
    } on PlatformException {
      // Ignore platform storage failures gracefully.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
    } on MissingPluginException {
      // Ignore in headless environment.
    } on PlatformException {
      // Ignore platform storage failures gracefully.
    }
  }
}

/// Deterministic in-memory session storage for unit and widget tests.
class InMemorySessionStorage implements SessionStorage {
  String? _token;
  String? _userJson;
  String? _apiBaseUrl;

  InMemorySessionStorage({
    String? initialToken,
    String? initialUserJson,
    String? initialApiBaseUrl,
  })  : _token = initialToken,
        _userJson = initialUserJson,
        _apiBaseUrl = initialApiBaseUrl;

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
  Future<void> clear() async {
    _token = null;
    _userJson = null;
  }
}
