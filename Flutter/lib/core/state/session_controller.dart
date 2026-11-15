import 'package:flutter/widgets.dart';

import '../../cognitive_state/services/cognitive_state_api_client.dart';
import '../config/api_config.dart';
import '../models/orbitcare_models.dart';
import '../services/orbitcare_api_client.dart';
import '../storage/session_storage.dart';

/// Holds authenticated OrbitCare user state, persists JWT and runtime backend
/// server URL via [SessionStorage], and exposes shared [OrbitCareApiClient]
/// and [CognitiveStateApiClient].
class SessionController extends ChangeNotifier {
  OrbitCareApiClient _apiClient;
  CognitiveStateApiClient _csmApiClient;
  final SessionStorage _storage;
  final String _buildDefaultBaseUrl;

  ApiUrlSource _urlSource;
  bool _configLoaded = false;
  Future<void>? _configLoadInFlight;

  AuthSession? _session;
  bool _isRestoring = false;
  bool _isInitialized = false;
  String? _sessionNotice;

  factory SessionController({
    OrbitCareApiClient? apiClient,
    CognitiveStateApiClient? csmApiClient,
    SessionStorage? storage,
    String? buildDefaultBaseUrl,
  }) {
    final effectiveBuildDefault = normalizeApiBaseUrl(
      buildDefaultBaseUrl ?? apiClient?.baseUrl ?? kOrbitCareApiBaseUrl,
    );
    final effectiveApiClient =
        apiClient ?? OrbitCareApiClient(baseUrl: effectiveBuildDefault);
    final resolved = resolveEffectiveApiBaseUrl(
      buildDefaultUrl: effectiveApiClient.baseUrl,
    );
    return SessionController._(
      apiClient: effectiveApiClient,
      csmApiClient:
          csmApiClient ?? effectiveApiClient.createCognitiveStateClient(),
      storage: storage ?? SecureSessionStorage(),
      buildDefaultBaseUrl: effectiveBuildDefault,
      initialSource: resolved.source,
    );
  }

  SessionController._({
    required OrbitCareApiClient apiClient,
    required CognitiveStateApiClient csmApiClient,
    required SessionStorage storage,
    required String buildDefaultBaseUrl,
    required ApiUrlSource initialSource,
  })  : _apiClient = apiClient,
        _csmApiClient = csmApiClient,
        _storage = storage,
        _buildDefaultBaseUrl = buildDefaultBaseUrl,
        _urlSource = initialSource;

  OrbitCareApiClient get apiClient => _apiClient;
  CognitiveStateApiClient get csmApiClient => _csmApiClient;
  String get apiBaseUrl => _apiClient.baseUrl;
  String get buildDefaultBaseUrl => _buildDefaultBaseUrl;
  bool get hasBuildDefault => isValidApiBaseUrl(_buildDefaultBaseUrl);
  ApiUrlSource get urlSource => _urlSource;
  bool get isConfigLoaded => _configLoaded;
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

  void _applyResolvedConfig(ResolvedApiConfig resolved) {
    _urlSource = resolved.source;
    if (_apiClient.baseUrl != resolved.baseUrl) {
      _apiClient = _apiClient.withBaseUrl(resolved.baseUrl);
      _csmApiClient = _apiClient.createCognitiveStateClient();
    }
  }

  /// Hydrates any persisted runtime server URL before auth requests run.
  ///
  /// Precedence: saved runtime URL > valid build-time default > unconfigured.
  Future<void> ensureConfigLoaded() {
    if (_configLoaded) return Future<void>.value();
    _configLoadInFlight ??= _loadSavedConfig().whenComplete(() {
      _configLoadInFlight = null;
    });
    return _configLoadInFlight!;
  }

  Future<void> _loadSavedConfig() async {
    try {
      final storedApiUrl = await _storage.readApiBaseUrl();
      final resolved = resolveEffectiveApiBaseUrl(
        savedUrl: storedApiUrl,
        buildDefaultUrl: _buildDefaultBaseUrl,
      );
      _applyResolvedConfig(resolved);
    } finally {
      _configLoaded = true;
      notifyListeners();
    }
  }

  /// Tests real connectivity against `GET /api/health` for [candidateUrl]
  /// (or the currently active URL when omitted).
  Future<ConnectionCheckResult> testConnection({String? candidateUrl}) async {
    await ensureConfigLoaded();
    return _apiClient.checkHealth(baseUrlOverride: candidateUrl);
  }

  /// Validates, normalizes, and persists the OrbitCare backend base URL at
  /// runtime so it survives app restarts and overrides any build-time default.
  Future<void> updateApiBaseUrl(String rawUrl) async {
    final validationError = validateApiBaseUrl(rawUrl);
    if (validationError != null) {
      throw OrbitCareApiException(
        code: 'INVALID_API_BASE_URL',
        message: validationError,
      );
    }
    final normalized = normalizeApiBaseUrl(rawUrl);
    await _storage.writeApiBaseUrl(normalized);
    _configLoaded = true;
    _applyResolvedConfig(
      ResolvedApiConfig(baseUrl: normalized, source: ApiUrlSource.saved),
    );
    notifyListeners();
  }

  /// Clears any user-saved runtime Server URL, falling back to the optional
  /// build-time `ORBITCARE_API_BASE_URL` default (or unconfigured if none).
  Future<void> resetApiBaseUrlToDefault() async {
    await _storage.writeApiBaseUrl(null);
    _configLoaded = true;
    final resolved = resolveEffectiveApiBaseUrl(
      savedUrl: null,
      buildDefaultUrl: _buildDefaultBaseUrl,
    );
    _applyResolvedConfig(resolved);
    notifyListeners();
  }

  /// Restores persisted backend configuration and any previously stored JWT on
  /// app startup, validating the JWT against GET /api/users/me.
  Future<bool> restoreSession() async {
    _isRestoring = true;
    notifyListeners();

    try {
      await ensureConfigLoaded();

      final storedToken = await _storage.readToken();
      if (storedToken == null || storedToken.isEmpty) {
        _session = null;
        return false;
      }

      if (!_apiClient.isConfigured) {
        _session = null;
        _sessionNotice =
            'Backend server URL is not configured. Open Configure Server URL to connect to your OrbitCare backend.';
        return false;
      }

      final freshUser = await _apiClient.getMe(token: storedToken);
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
    await ensureConfigLoaded();
    final createdSession = await _apiClient.login(
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
        _apiClient.isConfigured) {
      try {
        await _apiClient.logout(token: currentToken);
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
