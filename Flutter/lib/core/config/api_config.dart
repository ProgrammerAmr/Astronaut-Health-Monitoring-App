/// Backend connection configuration for the OrbitCare Flutter client.
///
/// Resolution order (highest priority first):
///   1. A runtime override picked by the user inside the app
///      (Settings -> "Backend Connection"), persisted on the device.
///   2. The build flag `--dart-define=ORBITCARE_API_BASE_URL=http://host:port`.
///   3. A platform-appropriate **local development default**, so a plain
///      `flutter run` can already reach a backend started on the same machine:
///        * Android (emulator reaches the host PC through the 10.0.2.2 alias)
///        * everything else (iOS simulator, web, Windows/macOS/Linux) -> localhost
///
/// Only loopback / emulator-alias development defaults live here. A deployed
/// (staging/production) hostname must still be supplied with
/// `--dart-define=ORBITCARE_API_BASE_URL=...` and never committed to source.
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

/// Hook used by the pure-Dart API clients to read a persisted runtime
/// override without depending on Flutter plugins or secure storage.
/// It is installed by `BackendConfig` (see core/config/backend_config.dart).
typedef RuntimeApiBaseUrlProvider = String? Function();

/// Currently installed runtime override provider (may be null in tests).
RuntimeApiBaseUrlProvider? runtimeApiBaseUrlProvider;

String normalizeApiBaseUrl(String raw) {
  var trimmed = raw.trim();
  while (trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  if (trimmed.endsWith('/api')) {
    trimmed = trimmed.substring(0, trimmed.length - 4);
  }
  return trimmed;
}

bool isValidApiBaseUrl(String raw) {
  final normalized = normalizeApiBaseUrl(raw);
  if (normalized.isEmpty) return false;
  final uri = Uri.tryParse(normalized);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
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
  /// Chosen by the user at runtime and persisted on the device.
  runtimeOverride,

  /// Provided through `--dart-define=ORBITCARE_API_BASE_URL=...`.
  buildFlag,

  /// Local development default for the current platform.
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
