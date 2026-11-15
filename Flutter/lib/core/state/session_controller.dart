import 'package:flutter/widgets.dart';

import '../../cognitive_state/services/cognitive_state_api_client.dart';
import '../models/orbitcare_models.dart';
import '../services/orbitcare_api_client.dart';
import '../storage/session_storage.dart';

/// Holds authenticated OrbitCare user state, persists JWT via [SessionStorage],
/// and exposes shared [OrbitCareApiClient] and [CognitiveStateApiClient].
class SessionController extends ChangeNotifier {
  final OrbitCareApiClient apiClient;
  final CognitiveStateApiClient csmApiClient;
  final SessionStorage _storage;

  AuthSession? _session;
  bool _isRestoring = false;
  bool _isInitialized = false;
  String? _sessionNotice;

  factory SessionController({
    OrbitCareApiClient? apiClient,
    CognitiveStateApiClient? csmApiClient,
    SessionStorage? storage,
  }) {
    final effectiveApiClient = apiClient ?? OrbitCareApiClient();
    return SessionController._(
      apiClient: effectiveApiClient,
      csmApiClient:
          csmApiClient ?? effectiveApiClient.createCognitiveStateClient(),
      storage: storage ?? SecureSessionStorage(),
    );
  }

  SessionController._({
    required this.apiClient,
    required this.csmApiClient,
    required SessionStorage storage,
  }) : _storage = storage;

  AuthSession? get session => _session;
  AuthUser? get user => _session?.user;
  String? get token => _session?.token;
  bool get isAuthenticated => _session != null && _session!.token.isNotEmpty;
  bool get isRestoring => _isRestoring;
  bool get isInitialized => _isInitialized;
  String? get sessionNotice => _sessionNotice;

  String? consumeNotice() {
    final current = _sessionNotice;
    _sessionNotice = null;
    return current;
  }

  /// Restores a previously persisted JWT on app startup and validates it
  /// against GET /api/users/me so expired or revoked tokens are never trusted.
  Future<bool> restoreSession() async {
    _isRestoring = true;
    notifyListeners();

    try {
      final storedToken = await _storage.readToken();
      if (storedToken == null || storedToken.isEmpty) {
        _session = null;
        return false;
      }

      if (!apiClient.isConfigured) {
        _session = null;
        _sessionNotice =
            'Backend URL is not configured. Launch with --dart-define=ORBITCARE_API_BASE_URL=<url>.';
        return false;
      }

      final freshUser = await apiClient.getMe(token: storedToken);
      _session = AuthSession(token: storedToken, user: freshUser);
      await _storage.writeUserJson(freshUser.toJsonString());
      _sessionNotice = null;
      return true;
    } on OrbitCareApiException catch (e) {
      if (e.isUnauthorized) {
        await _storage.clear();
        _session = null;
        _sessionNotice = 'Your session expired. Please sign in again.';
      } else {
        _session = null;
        _sessionNotice = e.message;
      }
      return false;
    } catch (_) {
      _session = null;
      _sessionNotice = 'Unable to restore session. Please sign in again.';
      return false;
    } finally {
      _isRestoring = false;
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final createdSession = await apiClient.login(
      email: email,
      password: password,
    );
    await establishSession(createdSession);
    return createdSession;
  }

  Future<void> establishSession(AuthSession newSession) async {
    _session = newSession;
    _sessionNotice = null;
    await _storage.writeToken(newSession.token);
    await _storage.writeUserJson(newSession.user.toJsonString());
    notifyListeners();
  }

  Future<void> logout({String? notice}) async {
    final currentToken = _session?.token;
    if (currentToken != null &&
        currentToken.isNotEmpty &&
        apiClient.isConfigured) {
      try {
        await apiClient.logout(token: currentToken);
      } catch (_) {
        // Always clear local session even if backend logout call fails.
      }
    }
    await _storage.clear();
    _session = null;
    _sessionNotice = notice ?? 'You have been signed out.';
    notifyListeners();
  }

  Future<void> handleUnauthorized() async {
    await _storage.clear();
    _session = null;
    _sessionNotice = 'Your session expired. Please sign in again.';
    notifyListeners();
  }
}

class SessionScope extends InheritedNotifier<SessionController> {
  const SessionScope({
    super.key,
    required SessionController controller,
    required super.child,
  }) : super(notifier: controller);

  static SessionController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'SessionScope not found in widget tree');
    return scope!.notifier!;
  }

  static SessionController? maybeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    return scope?.notifier;
  }
}
