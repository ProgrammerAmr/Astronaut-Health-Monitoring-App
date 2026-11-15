/// Build-time backend configuration for OrbitCare Flutter client.
///
/// Provide an optional default backend URL at build/run time:
///   flutter build apk --release --dart-define=ORBITCARE_API_BASE_URL=https://your-backend.example.com
///
/// Precedence rule:
///   1. User-saved runtime Server URL persisted on-device (`ApiUrlSource.saved`)
///   2. Optional build-time `ORBITCARE_API_BASE_URL` default (`ApiUrlSource.buildDefault`)
///   3. Unconfigured (`ApiUrlSource.unconfigured`) — user configures via Configure Server URL.
const String kOrbitCareApiBaseUrl = String.fromEnvironment(
  'ORBITCARE_API_BASE_URL',
  defaultValue: '',
);

enum ApiUrlSource {
  saved,
  buildDefault,
  unconfigured,
}

class ResolvedApiConfig {
  final String baseUrl;
  final ApiUrlSource source;

  const ResolvedApiConfig({
    required this.baseUrl,
    required this.source,
  });

  bool get isConfigured => baseUrl.isNotEmpty && source != ApiUrlSource.unconfigured;
}

/// Validates a user-entered or build-time backend base URL.
/// Returns `null` if valid, or a clear user-facing error message if invalid.
String? validateApiBaseUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return 'Please enter a backend server URL.';
  }
  if (RegExp(r'\s').hasMatch(trimmed)) {
    return 'Server URL cannot contain spaces.';
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return 'Invalid URL format. Include http:// or https:// and a valid host.';
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return 'Server URL must start with https:// or http://.';
  }
  if (uri.host.isEmpty) {
    return 'Server URL must include a valid host name or IP address.';
  }
  if (uri.userInfo.isNotEmpty) {
    return 'Server URL must not embed credentials.';
  }
  if (uri.hasPort && (uri.port <= 0 || uri.port > 65535)) {
    return 'Server URL port must be between 1 and 65535.';
  }
  return null;
}

/// Normalizes a backend base URL by removing query/fragment parts, collapsing
/// trailing slashes, and stripping repeated trailing `/api` path segments so
/// client calls to `/api/...` never produce duplicate `/api/api/...` paths.
String normalizeApiBaseUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    var fallback = trimmed;
    while (fallback.endsWith('/')) {
      fallback = fallback.substring(0, fallback.length - 1);
    }
    return fallback;
  }

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  while (segments.isNotEmpty && segments.last.toLowerCase() == 'api') {
    segments.removeLast();
  }

  final normalizedPath = segments.isEmpty ? '' : '/${segments.join('/')}';
  final normalizedUri = Uri(
    scheme: uri.scheme.toLowerCase(),
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: normalizedPath,
  );
  return normalizedUri.toString();
}

bool isValidApiBaseUrl(String raw) {
  if (validateApiBaseUrl(raw) != null) return false;
  final normalized = normalizeApiBaseUrl(raw);
  return normalized.isNotEmpty && validateApiBaseUrl(normalized) == null;
}

/// Resolves the effective backend base URL using strict precedence:
/// saved runtime URL > valid build-time default > unconfigured.
ResolvedApiConfig resolveEffectiveApiBaseUrl({
  String? savedUrl,
  String buildDefaultUrl = kOrbitCareApiBaseUrl,
}) {
  if (savedUrl != null && isValidApiBaseUrl(savedUrl)) {
    return ResolvedApiConfig(
      baseUrl: normalizeApiBaseUrl(savedUrl),
      source: ApiUrlSource.saved,
    );
  }
  if (isValidApiBaseUrl(buildDefaultUrl)) {
    return ResolvedApiConfig(
      baseUrl: normalizeApiBaseUrl(buildDefaultUrl),
      source: ApiUrlSource.buildDefault,
    );
  }
  return const ResolvedApiConfig(
    baseUrl: '',
    source: ApiUrlSource.unconfigured,
  );
}
