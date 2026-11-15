/// Build-time backend configuration for OrbitCare Flutter client.
///
/// Provide the API host at build/run time (never hardcode private hosts):
///   flutter run --dart-define=ORBITCARE_API_BASE_URL=http://10.0.2.2:5000
const String kOrbitCareApiBaseUrl = String.fromEnvironment(
  'ORBITCARE_API_BASE_URL',
  defaultValue: '',
);

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
