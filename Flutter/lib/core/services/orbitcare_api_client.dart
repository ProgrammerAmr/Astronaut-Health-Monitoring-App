import 'dart:async';
import 'dart:convert';

import '../../cognitive_state/services/cognitive_state_api_client.dart';
import '../../cognitive_state/services/csm_http_transport.dart';
import '../config/api_config.dart';
import '../models/orbitcare_models.dart';

class OrbitCareApiClient {
  final Duration timeout;
  final CsmHttpTransport _transport;

  /// Explicitly requested base URL. `null` means "resolve dynamically".
  final String? _baseUrlOverride;

  OrbitCareApiClient({
    String? baseUrl,
    this.timeout = const Duration(seconds: 10),
    CsmHttpTransport? transport,
  })  : _baseUrlOverride = baseUrl == null ? null : normalizeApiBaseUrl(baseUrl),
        _transport = transport ?? createDefaultCsmTransport();

  /// Effective backend URL.
  ///
  /// Re-resolved on every request through [resolveApiBaseUrl] so a URL saved
  /// from the in-app "Backend Connection" screen (or a `--dart-define` flag)
  /// is picked up immediately, without rebuilding or restarting the app.
  String get baseUrl => _baseUrlOverride ?? resolveApiBaseUrl();

  bool get isConfigured => isValidApiBaseUrl(baseUrl);

  CognitiveStateApiClient createCognitiveStateClient() {
    return CognitiveStateApiClient(
      // Passing null keeps the CSM client dynamically resolved as well.
      baseUrl: _baseUrlOverride,
      timeout: const Duration(seconds: 6),
      transport: _transport,
    );
  }

  Uri _endpoint(String path, [Map<String, String>? queryParams]) {
    final base = Uri.parse('$baseUrl$path');
    if (queryParams == null || queryParams.isEmpty) {
      return base;
    }
    return base.replace(queryParameters: queryParams);
  }

  Map<String, String> _headers({String? token}) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    final cleanToken = token?.trim() ?? '';
    if (cleanToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $cleanToken';
    }
    return headers;
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    String? token,
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  }) async {
    if (!isConfigured) {
      throw const OrbitCareApiException(
        code: 'API_BASE_URL_UNCONFIGURED',
        message:
            'OrbitCare backend URL is not configured. Open Settings -> Backend '
            'Connection in the app, or launch with '
            '--dart-define=ORBITCARE_API_BASE_URL=<backend-url>.',
      );
    }

    try {
      final response = await _transport.send(
        method: method,
        uri: _endpoint(path, queryParams),
        headers: _headers(token: token),
        body: body != null ? jsonEncode(body) : null,
        timeout: timeout,
      );

      final parsed = _tryDecodeMap(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return parsed ?? <String, dynamic>{};
      }

      final message = (parsed?['message'] ??
              'Request failed with HTTP ${response.statusCode}.')
          .toString();

      String code = 'HTTP_${response.statusCode}';
      if (response.statusCode == 401) {
        code = 'UNAUTHORIZED';
      } else if (response.statusCode == 403 &&
          message.toLowerCase().contains('verify')) {
        code = 'EMAIL_UNVERIFIED';
      } else if (response.statusCode == 403) {
        code = 'FORBIDDEN';
      }

      throw OrbitCareApiException(
        statusCode: response.statusCode,
        code: code,
        message: message,
      );
    } on OrbitCareApiException {
      rethrow;
    } on TimeoutException {
      throw OrbitCareApiException(
        code: 'TIMEOUT',
        message:
            'Request to $baseUrl timed out. The backend may be blocked by a '
            'firewall or on a different network. Check Settings -> Backend Connection.',
      );
    } catch (error) {
      throw OrbitCareApiException(
        code: 'NETWORK_ERROR',
        message: _networkErrorMessage(error),
      );
    }
  }

  /// Turns low level socket/browser failures into a message that tells the
  /// developer exactly what to check next.
  String _networkErrorMessage(Object error) {
    final text = error.toString().toLowerCase();
    final target = baseUrl.isEmpty ? 'the backend' : baseUrl;

    if (text.contains('cleartext') || text.contains('network security policy')) {
      return 'Android blocked the plain HTTP connection to $target. Rebuild the '
          'app with the latest AndroidManifest.xml (usesCleartextTraffic="true").';
    }
    if (text.contains('failed host lookup') ||
        text.contains('name or service not known') ||
        text.contains('nodename nor servname')) {
      return 'Could not resolve the host in $target. Fix the backend URL in '
          'Settings -> Backend Connection.';
    }
    if (text.contains('certificate') || text.contains('handshake')) {
      return 'Secure connection to $target failed. For local development use '
          'http:// instead of https://.';
    }
    return 'Unable to reach the OrbitCare backend at $target. Start it with '
        '"cd backend && npm run dev", then verify the address in '
        'Settings -> Backend Connection.';
  }

  Map<String, dynamic>? _tryDecodeMap(String body) {
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

  // -------------------- AUTHENTICATION --------------------

  Future<String> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/auth/register',
      body: <String, dynamic>{
        'fullName': fullName.trim(),
        'email': email.trim(),
        'password': password,
      },
    );
    return (json['message'] ?? 'Verification code sent to your email.')
        .toString();
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/auth/login',
      body: <String, dynamic>{
        'email': email.trim(),
        'password': password,
      },
    );

    final token = (json['token'] ?? '').toString().trim();
    final userRaw = json['user'];
    if (token.isEmpty || userRaw is! Map) {
      throw const OrbitCareApiException(
        code: 'INVALID_RESPONSE',
        message: 'Backend returned an invalid login session payload.',
      );
    }

    return AuthSession(
      token: token,
      user: AuthUser.fromJson(Map<String, dynamic>.from(userRaw)),
    );
  }

  Future<String> sendOtp({
    required String email,
    required String purpose,
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/auth/send-otp',
      body: <String, dynamic>{
        'email': email.trim(),
        'purpose': purpose,
      },
    );
    return (json['message'] ?? 'OTP sent successfully.').toString();
  }

  Future<AuthSession?> verifyOtp({
    required String email,
    required String otp,
    required String purpose,
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/auth/verify-otp',
      body: <String, dynamic>{
        'email': email.trim(),
        'otp': otp.trim(),
        'purpose': purpose,
      },
    );

    if (purpose == 'signup') {
      final token = (json['token'] ?? '').toString().trim();
      final userRaw = json['user'];
      if (token.isEmpty || userRaw is! Map) {
        throw const OrbitCareApiException(
          code: 'INVALID_RESPONSE',
          message: 'Account verified, but session token was missing.',
        );
      }
      return AuthSession(
        token: token,
        user: AuthUser.fromJson(Map<String, dynamic>.from(userRaw)),
      );
    }

    return null;
  }

  Future<String> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/auth/reset-password',
      body: <String, dynamic>{
        'email': email.trim(),
        'otp': otp.trim(),
        'newPassword': newPassword,
      },
    );
    return (json['message'] ?? 'Password reset successfully.').toString();
  }

  Future<void> logout({required String token}) async {
    await _requestJson(
      method: 'POST',
      path: '/api/auth/logout',
      token: token,
    );
  }

  // -------------------- USER PROFILE --------------------

  Future<AuthUser> getMe({required String token}) async {
    final json = await _requestJson(
      method: 'GET',
      path: '/api/users/me',
      token: token,
    );
    final data = json['data'];
    if (data is! Map) {
      throw const OrbitCareApiException(
        code: 'INVALID_RESPONSE',
        message: 'Unexpected profile response from backend.',
      );
    }

    // GET /api/users/me returns `{ "data": { "user": { ... } } }`.
    // Accept the flat shape too so both documented variants keep working
    // (previously the wrapper was parsed as the profile, which restored a
    // session with an empty id/email and the name "Astronaut").
    final profile = data['user'] is Map
        ? Map<String, dynamic>.from(data['user'] as Map)
        : Map<String, dynamic>.from(data);

    final user = AuthUser.fromJson(profile);
    if (user.id.isEmpty) {
      throw const OrbitCareApiException(
        code: 'INVALID_RESPONSE',
        message: 'Backend returned a profile without a user id.',
      );
    }
    return user;
  }

  // -------------------- HEALTH DASHBOARD & DATA --------------------

  Future<DashboardSummary> getDashboard({required String token}) async {
    final json = await _requestJson(
      method: 'GET',
      path: '/api/dashboard',
      token: token,
    );
    final data = json['data'];
    if (data is! Map) {
      throw const OrbitCareApiException(
        code: 'INVALID_RESPONSE',
        message: 'Unexpected dashboard response from backend.',
      );
    }
    return DashboardSummary.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<HealthMeasurement>> getMeasurements({
    required String token,
    int page = 1,
    int limit = 25,
  }) async {
    final json = await _requestJson(
      method: 'GET',
      path: '/api/measurements',
      token: token,
      queryParams: <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      },
    );
    final rawList = json['data'];
    if (rawList is! List) return const <HealthMeasurement>[];
    return rawList
        .whereType<Map>()
        .map((item) => HealthMeasurement.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<HealthMeasurement> createMeasurement({
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    final json = await _requestJson(
      method: 'POST',
      path: '/api/measurements',
      token: token,
      body: payload,
    );
    final data = json['data'];
    if (data is! Map) {
      throw const OrbitCareApiException(
        code: 'INVALID_RESPONSE',
        message: 'Unexpected measurement creation response.',
      );
    }
    return HealthMeasurement.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<HealthAlert>> getAlerts({
    required String token,
    bool? isRead,
  }) async {
    final query = <String, String>{};
    if (isRead != null) {
      query['isRead'] = isRead.toString();
    }
    final json = await _requestJson(
      method: 'GET',
      path: '/api/alerts',
      token: token,
      queryParams: query.isEmpty ? null : query,
    );
    final rawList = json['data'];
    if (rawList is! List) return const <HealthAlert>[];
    return rawList
        .whereType<Map>()
        .map((item) => HealthAlert.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<HealthAlert> markAlertRead({
    required String token,
    required String alertId,
  }) async {
    final json = await _requestJson(
      method: 'PATCH',
      path: '/api/alerts/$alertId/read',
      token: token,
    );
    final data = json['data'];
    if (data is! Map) {
      throw const OrbitCareApiException(
        code: 'INVALID_RESPONSE',
        message: 'Unexpected alert update response.',
      );
    }
    return HealthAlert.fromJson(Map<String, dynamic>.from(data));
  }

  Future<HealthReport> getReport({
    required String token,
    String period = 'weekly',
  }) async {
    final json = await _requestJson(
      method: 'GET',
      path: '/api/reports',
      token: token,
      queryParams: <String, String>{'period': period},
    );
    final data = json['data'];
    if (data is! Map) {
      throw const OrbitCareApiException(
        code: 'INVALID_RESPONSE',
        message: 'Unexpected report response from backend.',
      );
    }
    return HealthReport.fromJson(Map<String, dynamic>.from(data));
  }
}
