import '../../cognitive_state/services/cognitive_state_api_client.dart';
import '../models/orbitcare_models.dart';
import '../services/orbitcare_api_client.dart';
import 'demo_cognitive_state_api_client.dart';
import 'demo_health_repository.dart';

/// Offline Demo Mode adapter implementing [OrbitCareApiClient] against
/// [DemoHealthRepository] with zero network requests.
///
/// Production authentication methods are intentionally disabled on this adapter
/// so Demo Mode can never act as a production auth bypass.
class DemoOrbitCareApiClient extends OrbitCareApiClient {
  final DemoHealthRepository _repository;

  DemoOrbitCareApiClient({required DemoHealthRepository repository})
      : _repository = repository,
        super(baseUrl: '');

  @override
  bool get isConfigured => true;

  @override
  OrbitCareApiClient withBaseUrl(String newBaseUrl) => this;

  @override
  CognitiveStateApiClient createCognitiveStateClient() =>
      DemoCognitiveStateApiClient();

  @override
  Future<String> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    throw const OrbitCareApiException(
      code: 'DEMO_MODE_AUTH_DISABLED',
      message: 'Exit Demo Mode to register a real backend account.',
    );
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    throw const OrbitCareApiException(
      code: 'DEMO_MODE_AUTH_DISABLED',
      message: 'Exit Demo Mode to sign in with a real backend account.',
    );
  }

  @override
  Future<String> sendOtp({
    required String email,
    required String purpose,
  }) async {
    throw const OrbitCareApiException(
      code: 'DEMO_MODE_AUTH_DISABLED',
      message: 'Exit Demo Mode to send verification emails.',
    );
  }

  @override
  Future<AuthSession?> verifyOtp({
    required String email,
    required String otp,
    required String purpose,
  }) async {
    throw const OrbitCareApiException(
      code: 'DEMO_MODE_AUTH_DISABLED',
      message: 'Exit Demo Mode to verify OTP codes.',
    );
  }

  @override
  Future<String> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    throw const OrbitCareApiException(
      code: 'DEMO_MODE_AUTH_DISABLED',
      message: 'Exit Demo Mode to reset backend account passwords.',
    );
  }

  @override
  Future<void> logout({required String token}) async {
    // Offline local demo logout needs no network request.
  }

  @override
  Future<AuthUser> getMe({required String token}) async {
    await _repository.ensureLoaded();
    return DemoHealthRepository.demoUser;
  }

  @override
  Future<DashboardSummary> getDashboard({required String token}) {
    return _repository.getDashboard();
  }

  @override
  Future<List<HealthMeasurement>> getMeasurements({
    required String token,
    int page = 1,
    int limit = 25,
  }) {
    return _repository.getMeasurements(limit: limit);
  }

  @override
  Future<HealthMeasurement> createMeasurement({
    required String token,
    required Map<String, dynamic> payload,
  }) {
    return _repository.createMeasurement(payload);
  }

  @override
  Future<List<HealthAlert>> getAlerts({
    required String token,
    bool? isRead,
  }) {
    return _repository.getAlerts(isRead: isRead);
  }

  @override
  Future<HealthAlert> markAlertRead({
    required String token,
    required String alertId,
  }) {
    return _repository.markAlertRead(alertId);
  }

  @override
  Future<HealthReport> getReport({
    required String token,
    String period = 'weekly',
  }) {
    return _repository.getReport(period);
  }
}
