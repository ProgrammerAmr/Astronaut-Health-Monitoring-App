// Backend connection configuration for the OrbitCare Flutter client.
//
// Supports both:
// - Explicit saved/build-time/unconfigured resolution (`resolveEffectiveApiBaseUrl`)
//   used by `SessionController` and `ServerConfigScreen`, and
// - Dynamic runtime override / platform-default resolution (`resolveApiBaseUrlDetails`)
//   used by `BackendConfig` and `ConnectionSettingsScreen`.
import 'package:flutter/foundation.dart';

/// Build-time backend URL. Empty unless `--dart-define` provides it.
const String kOrbitCareApiBaseUrl = String.fromEnvironment(
  'ORBITCARE_API_BASE_URL',
  defaultValue: '',
);

/// Build-time backend port used by the local development defaults below.
const String kOrbitCareApiPort = String.fromEnvironment(
  'ORBITCARE_API_PORT',
  defaultValue: '5000',
);

/// Android emulators reach the host machine's loopback through this alias.
const String kAndroidEmulatorHostAlias = '10.0.2.2';

/// Host used by the default URL on iOS simulator / desktop / web.
const String kLocalhostHost = 'localhost';

/// Hook used by pure-Dart API clients to read a persisted runtime override.
typedef RuntimeApiBaseUrlProvider = String? Function();

/// Currently installed runtime override provider (may be null in tests).
RuntimeApiBaseUrlProvider? runtimeApiBaseUrlProvider;

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

  bool get isConfigured =>
      baseUrl.isNotEmpty && source != ApiUrlSource.unconfigured;
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

/// The URL a developer most likely needs on [platform] when nothing else was
/// configured. Never empty, so the app always has something to try.
String defaultApiBaseUrlFor({
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
  String? port,
}) {
  final requestedPort = (port ?? kOrbitCareApiPort).trim();
  final effectivePort = requestedPort.isEmpty ? '5000' : requestedPort;
  final effectivePlatform = platform ?? defaultTargetPlatform;
  if (!isWeb && effectivePlatform == TargetPlatform.android) {
    return 'http://$kAndroidEmulatorHostAlias:$effectivePort';
  }
  return 'http://$kLocalhostHost:$effectivePort';
}

/// Where the effective backend URL came from (shown in the in-app diagnostics).
enum ApiBaseUrlSource {
  runtimeOverride,
  buildFlag,
  platformDefault,
}

class ResolvedApiBaseUrl {
  final String url;
  final ApiBaseUrlSource source;

  const ResolvedApiBaseUrl(this.url, this.source);

  @override
  String toString() => 'ResolvedApiBaseUrl($url, $source)';
}

/// Applies the documented resolution order and always returns a usable URL.
ResolvedApiBaseUrl resolveApiBaseUrlDetails({
  String? runtimeOverride,
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) {
  final override = normalizeApiBaseUrl(
    runtimeOverride ?? runtimeApiBaseUrlProvider?.call() ?? '',
  );
  if (isValidApiBaseUrl(override)) {
    return ResolvedApiBaseUrl(override, ApiBaseUrlSource.runtimeOverride);
  }

  final fromBuildFlag = normalizeApiBaseUrl(kOrbitCareApiBaseUrl);
  if (isValidApiBaseUrl(fromBuildFlag)) {
    return ResolvedApiBaseUrl(fromBuildFlag, ApiBaseUrlSource.buildFlag);
  }

  return ResolvedApiBaseUrl(
    defaultApiBaseUrlFor(isWeb: isWeb, platform: platform),
    ApiBaseUrlSource.platformDefault,
  );
}

/// Convenience wrapper around [resolveApiBaseUrlDetails].
String resolveApiBaseUrl({
  String? runtimeOverride,
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) =>
    resolveApiBaseUrlDetails(
      runtimeOverride: runtimeOverride,
      isWeb: isWeb,
      platform: platform,
    ).url;

/// Human readable explanation of [source] for the connection settings screen.
String describeApiBaseUrlSource(ApiBaseUrlSource source) {
  switch (source) {
    case ApiBaseUrlSource.runtimeOverride:
      return 'Saved in this app (Settings -> Backend Connection)';
    case ApiBaseUrlSource.buildFlag:
      return 'From --dart-define=ORBITCARE_API_BASE_URL';
    case ApiBaseUrlSource.platformDefault:
      return 'Built-in local development default';
  }
}
