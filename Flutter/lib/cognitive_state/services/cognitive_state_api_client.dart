import 'dart:async';
import 'dart:convert';

import '../models/cognitive_state_models.dart';
import 'csm_http_transport.dart';

const String kDefaultOrbitCareApiBaseUrl = String.fromEnvironment(
  'ORBITCARE_API_BASE_URL',
  defaultValue: '',
);

class CognitiveStateApiClient {
  final String baseUrl;
  final Duration timeout;
  final CsmHttpTransport _transport;

  CognitiveStateApiClient({
    String? baseUrl,
    this.timeout = const Duration(seconds: 6),
    CsmHttpTransport? transport,
  })  : baseUrl = (baseUrl ?? kDefaultOrbitCareApiBaseUrl).trim(),
        _transport = transport ?? createDefaultCsmTransport();

  bool get isConfigured => _parsedBaseUri != null;

  Uri? get _parsedBaseUri {
    if (baseUrl.isEmpty) return null;
    final parsed = Uri.tryParse(baseUrl);
    if (parsed == null ||
        !(parsed.scheme == 'http' || parsed.scheme == 'https') ||
        parsed.host.isEmpty) {
      return null;
    }
    return parsed;
  }

  Uri _endpoint(String path) {
    final normalizedBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$normalizedBase$path');
  }

  Map<String, String> _headers(String authToken) {
    return <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $authToken',
    };
  }

  Map<String, dynamic>? _tryDecodeJsonMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<CognitiveStateUiSnapshot> fetchStatus({String? authToken}) async {
    if (!isConfigured) {
      return const CognitiveStateUiSnapshot(
        uiStatus: CognitiveStateUiStatus.unavailable,
        errorCode: 'API_BASE_URL_UNCONFIGURED',
        message:
            'OrbitCare backend URL is not configured. Launch with --dart-define=ORBITCARE_API_BASE_URL=<url> to connect.',
      );
    }

    final token = (authToken ?? '').trim();
    if (token.isEmpty) {
      return const CognitiveStateUiSnapshot(
        uiStatus: CognitiveStateUiStatus.unavailable,
        errorCode: 'AUTH_SESSION_REQUIRED',
        message:
            'An authenticated OrbitCare session token is required to query the Cognitive State service.',
      );
    }

    try {
      final response = await _transport.send(
        method: 'GET',
        uri: _endpoint('/api/cognitive-state/status'),
        headers: _headers(token),
        timeout: timeout,
      );

      final json = _tryDecodeJsonMap(response.body);

      if (response.statusCode == 503 || response.statusCode == 504) {
        final statusObj =
            json != null ? CognitiveStateServiceStatus.fromJson(json) : null;
        final err = statusObj != null && statusObj.errors.isNotEmpty
            ? statusObj.errors.first
            : null;
        return CognitiveStateUiSnapshot(
          uiStatus: CognitiveStateUiStatus.unavailable,
          serviceStatus: statusObj,
          errorCode: err?.code ?? 'SERVICE_UNAVAILABLE',
          message: err?.message ??
              'Cognitive state research service is currently unavailable.',
        );
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        return CognitiveStateUiSnapshot(
          uiStatus: CognitiveStateUiStatus.error,
          errorCode: response.statusCode == 401 ? 'UNAUTHORIZED' : 'FORBIDDEN',
          message: (json?['message'] ??
                  'Authentication or authorization failed for cognitive state service.')
              .toString(),
        );
      }

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          json != null) {
        final serviceStatus = CognitiveStateServiceStatus.fromJson(json);
        if (!serviceStatus.serviceAvailable) {
          return CognitiveStateUiSnapshot(
            uiStatus: CognitiveStateUiStatus.unavailable,
            serviceStatus: serviceStatus,
            errorCode: 'SERVICE_UNAVAILABLE',
            message: 'Cognitive state research service reported unavailable.',
          );
        }
        return CognitiveStateUiSnapshot(
          uiStatus: CognitiveStateUiStatus.insufficientData,
          serviceStatus: serviceStatus,
          message: serviceStatus.registeredModelAvailable
              ? 'Research service connected. Select an explicit mode to request evaluation.'
              : 'Research service connected, but no trained or validated CSM model artifact is registered (safe INSUFFICIENT_DATA abstention active).',
        );
      }

      return CognitiveStateUiSnapshot(
        uiStatus: CognitiveStateUiStatus.error,
        errorCode: 'UNEXPECTED_HTTP_${response.statusCode}',
        message:
            'Cognitive state status endpoint returned unexpected HTTP ${response.statusCode}.',
      );
    } on TimeoutException {
      return const CognitiveStateUiSnapshot(
        uiStatus: CognitiveStateUiStatus.unavailable,
        errorCode: 'CLIENT_TIMEOUT',
        message: 'Timed out waiting for the cognitive state research service.',
      );
    } catch (_) {
      return const CognitiveStateUiSnapshot(
        uiStatus: CognitiveStateUiStatus.unavailable,
        errorCode: 'NETWORK_UNAVAILABLE',
        message: 'Unable to reach the OrbitCare cognitive state service.',
      );
    }
  }

  Future<CognitiveStateUiSnapshot> analyze({
    required CognitiveStateMode mode,
    String? authToken,
    String? sessionId,
    double? windowEndSec,
    SignalQualityInfo? signalQuality,
    String? dataProvenance,
  }) async {
    if (!isConfigured) {
      return const CognitiveStateUiSnapshot(
        uiStatus: CognitiveStateUiStatus.unavailable,
        errorCode: 'API_BASE_URL_UNCONFIGURED',
        message:
            'OrbitCare backend URL is not configured. Launch with --dart-define=ORBITCARE_API_BASE_URL=<url> to connect.',
      );
    }

    final token = (authToken ?? '').trim();
    if (token.isEmpty) {
      return const CognitiveStateUiSnapshot(
        uiStatus: CognitiveStateUiStatus.unavailable,
        errorCode: 'AUTH_SESSION_REQUIRED',
        message:
            'An authenticated OrbitCare session token is required to call cognitive state analysis.',
      );
    }

    final requestBody = <String, dynamic>{
      'mode': mode.apiValue,
    };
    if (sessionId != null && sessionId.trim().isNotEmpty) {
      requestBody['sessionId'] = sessionId.trim();
    }
    if (windowEndSec != null) {
      requestBody['windowEndSec'] = windowEndSec;
    }
    if (dataProvenance != null && dataProvenance.trim().isNotEmpty) {
      requestBody['dataProvenance'] = dataProvenance.trim();
    }
    if (signalQuality != null) {
      requestBody['signalQuality'] = signalQuality.toJson();
    }

    try {
      final response = await _transport.send(
        method: 'POST',
        uri: _endpoint('/api/cognitive-state/analyze'),
        headers: _headers(token),
        body: jsonEncode(requestBody),
        timeout: timeout,
      );

      final json = _tryDecodeJsonMap(response.body);

      if (response.statusCode == 503 || response.statusCode == 504) {
        final analysis = json != null
            ? CognitiveStateAnalysisResponse.fromJson(json)
            : null;
        final err = analysis != null && analysis.errors.isNotEmpty
            ? analysis.errors.first
            : null;
        return CognitiveStateUiSnapshot(
          uiStatus: CognitiveStateUiStatus.unavailable,
          analysis: analysis,
          errorCode: err?.code ?? 'SERVICE_UNAVAILABLE',
          message: err?.message ??
              'Cognitive state research service is unavailable. No prediction was substituted.',
        );
      }

      if (json != null &&
          (json.containsKey('status') && json.containsKey('prediction'))) {
        final analysis = CognitiveStateAnalysisResponse.fromJson(json);
        final resolvedStatus = analysis.resolveUiStatus();
        final err =
            analysis.errors.isNotEmpty ? analysis.errors.first : null;
        return CognitiveStateUiSnapshot(
          uiStatus: resolvedStatus,
          analysis: analysis,
          errorCode: err?.code,
          message: err?.message,
        );
      }

      return CognitiveStateUiSnapshot(
        uiStatus: CognitiveStateUiStatus.error,
        errorCode: 'HTTP_${response.statusCode}',
        message: (json?['message'] ??
                'Cognitive state analysis failed with HTTP ${response.statusCode}. No prediction was substituted.')
            .toString(),
      );
    } on TimeoutException {
      return const CognitiveStateUiSnapshot(
        uiStatus: CognitiveStateUiStatus.unavailable,
        errorCode: 'CLIENT_TIMEOUT',
        message:
            'Cognitive state request timed out. No prediction was substituted.',
      );
    } catch (_) {
      return const CognitiveStateUiSnapshot(
        uiStatus: CognitiveStateUiStatus.unavailable,
        errorCode: 'NETWORK_UNAVAILABLE',
        message:
            'Unable to reach the OrbitCare cognitive state service. No prediction was substituted.',
      );
    }
  }
}
