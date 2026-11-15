import 'dart:async';
import 'dart:convert';

import '../../cognitive_state/services/cognitive_state_api_client.dart';
import '../../cognitive_state/services/csm_http_transport.dart';
import '../config/api_config.dart';
import '../models/orbitcare_models.dart';

class OrbitCareApiClient {
  final String baseUrl;
  final Duration timeout;
  final CsmHttpTransport _transport;

  OrbitCareApiClient({
    String? baseUrl,
    this.timeout = const Duration(seconds: 10),
    CsmHttpTransport? transport,
  })  : baseUrl = normalizeApiBaseUrl(baseUrl ?? kOrbitCareApiBaseUrl),
        _transport = transport ?? createDefaultCsmTransport();

  bool get isConfigured => isValidApiBaseUrl(baseUrl);

  OrbitCareApiClient withBaseUrl(String newBaseUrl) {
    return OrbitCareApiClient(
      baseUrl: newBaseUrl,
      timeout: timeout,
      transport: _transport,
    );
  }

  CognitiveStateApiClient createCognitiveStateClient() {
    return CognitiveStateApiClient(
      baseUrl: baseUrl,
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
            'Backend server URL is not configured yet. Open Configure Server URL to set and test your OrbitCare backend address.',
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
      throw const OrbitCareApiException(
        code: 'TIMEOUT',
        message:
            'Request timed out while contacting the OrbitCare backend. Check your connection and try again.',
      );
    } catch (_) {
      throw const OrbitCareApiException(
        code: 'NETWORK_ERROR',
        message:
            'Unable to reach the OrbitCare backend server. Verify the server is running and reachable.',
      );
    }
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

  // -------------------- CONNECTION VALIDATION --------------------

  /// Probes `GET /api/health` against [baseUrlOverride] (or the active baseUrl)
  /// to verify real backend reachability. Never reports success based only on
  /// URL syntax validation.
  Future<ConnectionCheckResult> checkHealth({String? baseUrlOverride}) async {
    final rawCandidate = (baseUrlOverride ?? baseUrl).trim();
    if (rawCandidate.isEmpty) {
      return const ConnectionCheckResult(
        status: ConnectionCheckStatus.missingConfig,
        message:
            'No backend server URL is configured. Enter your OrbitCare backend URL to test the connection.',
      );
    }

    final validationError = validateApiBaseUrl(rawCandidate);
    if (validationError != null) {
      return ConnectionCheckResult(
        status: ConnectionCheckStatus.invalidUrl,
        message: validationError,
      );
    }

    final normalized = normalizeApiBaseUrl(rawCandidate);
    final healthUri = Uri.parse('$normalized/api/health');
    final stopwatch = Stopwatch()..start();

    try {
      final response = await _transport.send(
        method: 'GET',
        uri: healthUri,
        headers: const <String, String>{'Accept': 'application/json'},
        timeout: timeout,
      );
      stopwatch.stop();
      final parsed = _tryDecodeMap(response.body);

      if (response.statusCode == 200 && parsed != null && parsed['success'] == true) {
        final backendMsg =
            (parsed['message'] ?? 'OrbitCare API is running').toString();
        final dbStatus = parsed['database']?.toString();
        final emailConfigured = parsed['emailConfigured'] is bool
            ? parsed['emailConfigured'] as bool
            : null;
        return ConnectionCheckResult(
          status: ConnectionCheckStatus.connected,
          normalizedUrl: normalized,
          statusCode: response.statusCode,
          latencyMs: stopwatch.elapsedMilliseconds,
          databaseStatus: dbStatus,
          emailConfigured: emailConfigured,
          message: backendMsg,
        );
      }

      final errMsg = parsed?['message']?.toString();
      return ConnectionCheckResult(
        status: ConnectionCheckStatus.serverError,
        normalizedUrl: normalized,
        statusCode: response.statusCode,
        latencyMs: stopwatch.elapsedMilliseconds,
        message: errMsg != null && errMsg.isNotEmpty
            ? 'Server responded with HTTP ${response.statusCode}: $errMsg'
            : 'Server responded with HTTP ${response.statusCode} and did not return a valid OrbitCare /api/health payload.',
      );
    } on TimeoutException {
      stopwatch.stop();
      return ConnectionCheckResult(
        status: ConnectionCheckStatus.timeout,
        normalizedUrl: normalized,
        latencyMs: stopwatch.elapsedMilliseconds,
        message:
            'Connection timed out reaching $normalized/api/health. Confirm the backend is running and reachable from this device.',
      );
    } catch (_) {
      stopwatch.stop();
      return ConnectionCheckResult(
        status: ConnectionCheckStatus.unreachable,
        normalizedUrl: normalized,
        latencyMs: stopwatch.elapsedMilliseconds,
        message:
            'Could not reach $normalized/api/health. Verify the host, HTTPS/HTTP scheme, network access, and that the server is not localhost on a physical phone.',
      );
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
    final dataMap = Map<String, dynamic>.from(data);
    final userRaw = dataMap['user'];
    final effectiveUserMap =
        userRaw is Map ? Map<String, dynamic>.from(userRaw) : dataMap;
    return AuthUser.fromJson(effectiveUserMap);
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
