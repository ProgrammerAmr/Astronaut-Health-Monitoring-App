import 'package:flutter/widgets.dart';

import '../../cognitive_state/services/cognitive_state_api_client.dart';
import '../config/api_config.dart';
import '../demo/demo_cognitive_state_api_client.dart';
import '../demo/demo_health_repository.dart';
import '../demo/demo_orbitcare_api_client.dart';
import '../models/orbitcare_models.dart';
import '../services/orbitcare_api_client.dart';
import '../storage/session_storage.dart';

/// Explicit separation between production backend sessions and offline Demo Mode.
enum AppSessionMode {
  production,
  demo,
}

/// Holds authenticated OrbitCare user state, persists JWT and runtime backend
/// server URL via [SessionStorage], and manages clean separation between
/// production API clients and the offline [DemoHealthRepository].
class SessionController extends ChangeNotifier {
  OrbitCareApiClient _productionApiClient;
  CognitiveStateApiClient _productionCsmApiClient;
  final SessionStorage _storage;
  final String _buildDefaultBaseUrl;

  final DemoHealthRepository _demoRepository;
  late final DemoOrbitCareApiClient _demoApiClient;
  final DemoCognitiveStateApiClient _demoCsmApiClient =
      DemoCognitiveStateApiClient();

  AppSessionMode _mode = AppSessionMode.production;
  ApiUrlSource _urlSource;
  bool _configLoaded = false;
  Future<void>? _configLoadInFlight;

  AuthSession? _session;
  bool _isRestoring = false;
  bool _isInitialized = false;
  String? _sessionNotice;
  int _demoDataRevision = 0;

  factory SessionController({
    OrbitCareApiClient? apiClient,
    CognitiveStateApiClient? csmApiClient,
    SessionStorage? storage,
    String? buildDefaultBaseUrl,
    DemoHealthRepository? demoRepository,
  }) {
    final effectiveStorage = storage ?? SecureSessionStorage();
    final effectiveBuildDefault = normalizeApiBaseUrl(
      buildDefaultBaseUrl ?? apiClient?.baseUrl ?? kOrbitCareApiBaseUrl,
    );
    final effectiveApiClient =
        apiClient ?? OrbitCareApiClient(baseUrl: effectiveBuildDefault);
    final resolved = resolveEffectiveApiBaseUrl(
      buildDefaultUrl: effectiveApiClient.baseUrl,
    );
    return SessionController._(
      productionApiClient: effectiveApiClient,
      productionCsmApiClient:
          csmApiClient ?? effectiveApiClient.createCognitiveStateClient(),
      storage: effectiveStorage,
      buildDefaultBaseUrl: effectiveBuildDefault,
      initialSource: resolved.source,
      demoRepository:
          demoRepository ?? DemoHealthRepository(storage: effectiveStorage),
    );
  }

  SessionController._({
    required OrbitCareApiClient productionApiClient,
    required CognitiveStateApiClient productionCsmApiClient,
    required SessionStorage storage,
    required String buildDefaultBaseUrl,
    required ApiUrlSource initialSource,
    required DemoHealthRepository demoRepository,
  })  : _productionApiClient = productionApiClient,
        _productionCsmApiClient = productionCsmApiClient,
        _storage = storage,
        _buildDefaultBaseUrl = buildDefaultBaseUrl,
        _urlSource = initialSource,
        _demoRepository = demoRepository {
    _demoApiClient = DemoOrbitCareApiClient(repository: _demoRepository);
  }

  AppSessionMode get mode => _mode;
  bool get isDemoMode => _mode == AppSessionMode.demo;

  /// Active API client for the current session mode.
  OrbitCareApiClient get apiClient =>
      isDemoMode ? _demoApiClient : _productionApiClient;

  /// Active DEC-001 Cognitive State client for the current session mode.
  CognitiveStateApiClient get csmApiClient =>
      isDemoMode ? _demoCsmApiClient : _productionCsmApiClient;

  /// Direct reference to the production API client (used by Server Settings & auth screens).
  OrbitCareApiClient get productionApiClient => _productionApiClient;

  bool get isProductionApiConfigured => _productionApiClient.isConfigured;

  String get apiBaseUrl => _productionApiClient.baseUrl;
  String get buildDefaultBaseUrl => _buildDefaultBaseUrl;
  bool get hasBuildDefault => isValidApiBaseUrl(_buildDefaultBaseUrl);
  ApiUrlSource get urlSource => _urlSource;
  bool get isConfigLoaded => _configLoaded;

  DemoHealthRepository get demoRepository => _demoRepository;
  DemoPreferences get demoPreferences => _demoRepository.preferences;
  int get demoDataRevision => _demoDataRevision;

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
    if (_productionApiClient.baseUrl != resolved.baseUrl) {
      _productionApiClient = _productionApiClient.withBaseUrl(resolved.baseUrl);
      _productionCsmApiClient =
          _productionApiClient.createCognitiveStateClient();
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

  /// Tests real connectivity against `GET /api/health` on the production client
  /// for [candidateUrl] (or the currently active production URL when omitted).
  Future<ConnectionCheckResult> testConnection({String? candidateUrl}) async {
    await ensureConfigLoaded();
    return _productionApiClient.checkHealth(baseUrlOverride: candidateUrl);
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

  // -------------------- OFFLINE DEMO MODE --------------------

  /// Activates local offline Demo Mode without requiring registration, OTP, or
  /// a live backend server. Production credentials are never modified or mixed.
  Future<void> enterDemoMode() async {
    await _demoRepository.ensureLoaded();
    await _storage.writeDemoModeActive(true);
    _mode = AppSessionMode.demo;
    _session = const AuthSession(
      token: DemoHealthRepository.demoSessionToken,
      user: DemoHealthRepository.demoUser,
    );
    _sessionNotice = null;
    notifyListeners();
  }

  /// Restores baseline synthetic astronaut measurements and alerts in Demo Mode.
  Future<void> resetDemoData() async {
    await _demoRepository.resetToDefaults();
    _demoDataRevision++;
    notifyListeners();
  }

  /// Persists local display and demo preferences (e.g., °C/°F unit).
  Future<void> updateDemoPreferences(DemoPreferences next) async {
    await _demoRepository.ensureLoaded();
    await _demoRepository.updatePreferences(next);
    notifyListeners();
  }

  // -------------------- SESSION RESTORE & PRODUCTION AUTH --------------------

  /// Restores persisted backend configuration and any active production JWT
  /// (or active offline Demo Mode session) on app startup.
  Future<bool> restoreSession() async {
    _isRestoring = true;
    notifyListeners();

    try {
      await ensureConfigLoaded();

      final storedToken = await _storage.readToken();
      if (storedToken != null && storedToken.isNotEmpty) {
        if (!_productionApiClient.isConfigured) {
          _mode = AppSessionMode.production;
          _session = null;
          _sessionNotice =
              'Backend server URL is not configured. Open Configure Server URL to connect to your OrbitCare backend.';
          return false;
        }

        final freshUser = await _productionApiClient.getMe(token: storedToken);
        _mode = AppSessionMode.production;
        _session = AuthSession(token: storedToken, user: freshUser);
        await _storage.writeUserJson(freshUser.toJsonString());
        _sessionNotice = null;
        return true;
      }

      // If no production session is present, restore offline Demo Mode if active.
      final demoActive = await _storage.readDemoModeActive();
      if (demoActive) {
        await _demoRepository.ensureLoaded();
        _mode = AppSessionMode.demo;
        _session = const AuthSession(
          token: DemoHealthRepository.demoSessionToken,
          user: DemoHealthRepository.demoUser,
        );
        _sessionNotice = null;
        return true;
      }

      _mode = AppSessionMode.production;
      _session = null;
      return false;
    } on OrbitCareApiException catch (e) {
      if (e.isUnauthorized) {
        await _storage.clear();
        _mode = AppSessionMode.production;
        _session = null;
        _sessionNotice = 'Your session expired. Please sign in again.';
      } else {
        _mode = AppSessionMode.production;
        _session = null;
        _sessionNotice = e.message;
      }
      return false;
    } catch (_) {
      _mode = AppSessionMode.production;
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
    final createdSession = await _productionApiClient.login(
      email: email,
      password: password,
    );
    await establishSession(createdSession);
    return createdSession;
  }

  Future<void> establishSession(AuthSession newSession) async {
    _mode = AppSessionMode.production;
    _session = newSession;
    _sessionNotice = null;
    await _storage.writeDemoModeActive(false);
    await _storage.writeToken(newSession.token);
    await _storage.writeUserJson(newSession.user.toJsonString());
    notifyListeners();
  }

  Future<void> logout({String? notice}) async {
    if (isDemoMode) {
      await _storage.writeDemoModeActive(false);
      _mode = AppSessionMode.production;
      _session = null;
      _sessionNotice = notice ??
          'Exited Demo Mode. Sign in with a backend account or continue as Demo User anytime.';
      notifyListeners();
      return;
    }

    final currentToken = _session?.token;
    if (currentToken != null &&
        currentToken.isNotEmpty &&
        _productionApiClient.isConfigured) {
      try {
        await _productionApiClient.logout(token: currentToken);
      } catch (_) {
        // Always clear local session even if backend logout call fails.
      }
    }
    await _storage.clear();
    _mode = AppSessionMode.production;
    _session = null;
    _sessionNotice = notice ?? 'You have been signed out.';
    notifyListeners();
  }

  Future<void> handleUnauthorized() async {
    if (isDemoMode) return;
    await _storage.clear();
    _mode = AppSessionMode.production;
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
