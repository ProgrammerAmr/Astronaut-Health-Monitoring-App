import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasa/cognitive_state/services/csm_http_transport.dart';
import 'package:nasa/core/config/api_config.dart';
import 'package:nasa/core/models/orbitcare_models.dart';
import 'package:nasa/core/services/orbitcare_api_client.dart';
import 'package:nasa/core/state/session_controller.dart';
import 'package:nasa/core/storage/session_storage.dart';
import 'package:nasa/main.dart';
import 'package:nasa/routes/app_routes.dart';

class _MockTransport implements CsmHttpTransport {
  final Future<CsmHttpResponse> Function(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) handler;

  _MockTransport(this.handler);

  @override
  Future<CsmHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) {
    return handler(method, uri, headers, body);
  }
}

CsmHttpResponse _jsonResp(int status, Map<String, dynamic> body) {
  return CsmHttpResponse(statusCode: status, body: jsonEncode(body));
}

CsmHttpResponse _defaultHomeHandler(String method, Uri uri) {
  if (uri.path == '/api/dashboard') {
    return _jsonResp(200, {
      'status': 'success',
      'data': {
        'totalMeasurements': 1,
        'unreadAlerts': 0,
        'latestMeasurement': null,
        'averages': null,
      },
    });
  }
  if (uri.path == '/api/measurements') {
    return _jsonResp(200, {'status': 'success', 'data': <dynamic>[]});
  }
  if (uri.path == '/api/alerts') {
    return _jsonResp(200, {'status': 'success', 'data': <dynamic>[]});
  }
  if (uri.path == '/api/reports') {
    return _jsonResp(200, {
      'success': true,
      'data': {
        'period': 'weekly',
        'summary': {'records': 0},
      },
    });
  }
  if (uri.path == '/api/cognitive-state/status') {
    return _jsonResp(200, {
      'service_available': true,
      'registered_model_available': false,
      'limitations': ['Hackathon prototype only.'],
      'errors': <dynamic>[],
    });
  }
  return _jsonResp(404, {'message': 'Not mocked: $method ${uri.path}'});
}

void main() {
  group('SessionController persistence & restoration', () {
    test('persists token on login, restores valid session, and clears on logout',
        () async {
      final storage = InMemorySessionStorage();
      var logoutCalled = false;

      final api = OrbitCareApiClient(
        baseUrl: 'https://api.orbitcare.test',
        transport: _MockTransport((method, uri, headers, body) async {
          if (method == 'POST' && uri.path == '/api/auth/login') {
            return _jsonResp(200, {
              'success': true,
              'token': 'jwt-demo-token',
              'user': {
                'id': 'u1',
                'name': 'Alex Vance',
                'email': 'alex@orbitcare.test',
                'role': 'astronaut',
              },
            });
          }
          if (method == 'GET' && uri.path == '/api/users/me') {
            expect(headers['Authorization'], 'Bearer jwt-demo-token');
            return _jsonResp(200, {
              'status': 'success',
              'data': {
                '_id': 'u1',
                'name': 'Alex Vance',
                'email': 'alex@orbitcare.test',
                'role': 'astronaut',
              },
            });
          }
          if (method == 'POST' && uri.path == '/api/auth/logout') {
            logoutCalled = true;
            return _jsonResp(200, {'success': true, 'message': 'Logged out'});
          }
          return _jsonResp(404, {'message': 'Not found'});
        }),
      );

      final controller = SessionController(apiClient: api, storage: storage);
      await controller.login(
        email: 'alex@orbitcare.test',
        password: 'Password!123',
      );

      expect(controller.isAuthenticated, isTrue);
      expect(await storage.readToken(), 'jwt-demo-token');

      // Simulate fresh app launch restoring from secure storage
      final restoredController =
          SessionController(apiClient: api, storage: storage);
      final restored = await restoredController.restoreSession();
      expect(restored, isTrue);
      expect(restoredController.user?.name, 'Alex Vance');

      // Logout clears storage
      await restoredController.logout();
      expect(logoutCalled, isTrue);
      expect(restoredController.isAuthenticated, isFalse);
      expect(await storage.readToken(), isNull);
    });

    test('clears expired JWT on 401 during session restore', () async {
      final storage = InMemorySessionStorage(initialToken: 'expired-jwt');
      final api = OrbitCareApiClient(
        baseUrl: 'https://api.orbitcare.test',
        transport: _MockTransport((method, uri, headers, body) async {
          return _jsonResp(401, {'message': 'Not authorized, token failed'});
        }),
      );

      final controller = SessionController(apiClient: api, storage: storage);
      final restored = await controller.restoreSession();

      expect(restored, isFalse);
      expect(controller.isAuthenticated, isFalse);
      expect(await storage.readToken(), isNull);
      expect(controller.sessionNotice, contains('expired'));
    });
  });

  group('Auth Screen Widget Flows', () {
    testWidgets('LoginScreen displays error on 401 and navigates to Home on 200',
        (tester) async {
      final storage = InMemorySessionStorage();
      final api = OrbitCareApiClient(
        baseUrl: 'https://api.orbitcare.test',
        transport: _MockTransport((method, uri, headers, body) async {
          if (method == 'POST' && uri.path == '/api/auth/login') {
            final parsed = jsonDecode(body ?? '{}') as Map<String, dynamic>;
            if (parsed['password'] == 'WrongPass') {
              return _jsonResp(401, {'message': 'Invalid email or password'});
            }
            return _jsonResp(200, {
              'success': true,
              'token': 'valid-jwt',
              'user': {
                'id': 'u1',
                'name': 'Alex Vance',
                'email': 'alex@orbitcare.test',
                'role': 'astronaut',
              },
            });
          }
          return _defaultHomeHandler(method, uri);
        }),
      );

      final controller = SessionController(apiClient: api, storage: storage);
      await tester.pumpWidget(
        OrbitCareApp(
          sessionController: controller,
          initialRoute: AppRoutes.login,
        ),
      );

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'alex@orbitcare.test');
      await tester.enterText(fields.at(1), 'WrongPass');

      final loginBtn = find.text('Log In');
      await tester.ensureVisible(loginBtn);
      await tester.tap(loginBtn);
      await tester.pumpAndSettle();

      expect(find.text('Invalid email or password'), findsOneWidget);
      expect(controller.isAuthenticated, isFalse);

      // Now enter valid password
      await tester.enterText(fields.at(1), 'CorrectPass!1');
      await tester.ensureVisible(loginBtn);
      await tester.tap(loginBtn);
      await tester.pumpAndSettle();

      expect(controller.isAuthenticated, isTrue);
      expect(find.text('Hello, Alex Vance'), findsOneWidget);
    });

    testWidgets('Signup -> OTP verification activates session and opens Home',
        (tester) async {
      final storage = InMemorySessionStorage();
      final api = OrbitCareApiClient(
        baseUrl: 'https://api.orbitcare.test',
        transport: _MockTransport((method, uri, headers, body) async {
          if (method == 'POST' && uri.path == '/api/auth/register') {
            return _jsonResp(201, {
              'success': true,
              'message': 'Account created. Verification code sent.',
            });
          }
          if (method == 'POST' && uri.path == '/api/auth/verify-otp') {
            final parsed = jsonDecode(body ?? '{}') as Map<String, dynamic>;
            expect(parsed['purpose'], 'signup');
            expect(parsed['otp'], '123456');
            return _jsonResp(200, {
              'success': true,
              'token': 'signup-jwt',
              'user': {
                'id': 'u2',
                'name': 'Nova Lin',
                'email': 'nova@orbitcare.test',
                'role': 'astronaut',
              },
            });
          }
          return _defaultHomeHandler(method, uri);
        }),
      );

      final controller = SessionController(apiClient: api, storage: storage);
      await tester.pumpWidget(
        OrbitCareApp(
          sessionController: controller,
          initialRoute: AppRoutes.signup,
        ),
      );

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Nova Lin');
      await tester.enterText(fields.at(1), 'nova@orbitcare.test');
      await tester.enterText(fields.at(2), 'StrongPass!1');
      await tester.enterText(fields.at(3), 'StrongPass!1');

      final createBtn = find.text('Create Account').last;
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      expect(find.text('Verify Your Email'), findsOneWidget);

      const digits = ['1', '2', '3', '4', '5', '6'];
      for (var i = 0; i < 6; i++) {
        await tester.enterText(find.byKey(Key('otp_digit_$i')), digits[i]);
      }

      final verifyBtn = find.text('Verify Code');
      await tester.ensureVisible(verifyBtn);
      await tester.tap(verifyBtn);
      await tester.pumpAndSettle();

      expect(controller.isAuthenticated, isTrue);
      expect(await storage.readToken(), 'signup-jwt');
      expect(find.text('Hello, Nova Lin'), findsOneWidget);
    });

    testWidgets('ForgotPassword -> OTP -> ResetPassword completes flow',
        (tester) async {
      var resetSubmitted = false;
      final storage = InMemorySessionStorage();
      final api = OrbitCareApiClient(
        baseUrl: 'https://api.orbitcare.test',
        transport: _MockTransport((method, uri, headers, body) async {
          if (method == 'POST' && uri.path == '/api/auth/send-otp') {
            return _jsonResp(200, {'success': true, 'message': 'OTP sent'});
          }
          if (method == 'POST' && uri.path == '/api/auth/verify-otp') {
            final parsed = jsonDecode(body ?? '{}') as Map<String, dynamic>;
            expect(parsed['purpose'], 'reset_password');
            return _jsonResp(200, {'success': true, 'message': 'OTP verified'});
          }
          if (method == 'POST' && uri.path == '/api/auth/reset-password') {
            final parsed = jsonDecode(body ?? '{}') as Map<String, dynamic>;
            expect(parsed['otp'], '654321');
            expect(parsed['newPassword'], 'NewOrbit!2026');
            resetSubmitted = true;
            return _jsonResp(200, {'success': true, 'message': 'Password reset'});
          }
          return _jsonResp(404, {'message': 'Not found'});
        }),
      );

      final controller = SessionController(apiClient: api, storage: storage);
      await tester.pumpWidget(
        OrbitCareApp(
          sessionController: controller,
          initialRoute: AppRoutes.forgotPassword,
        ),
      );

      await tester.enterText(find.byType(TextField).first, 'alex@orbitcare.test');
      final sendBtn = find.text('Send Verification Code');
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      expect(find.text('Verify Reset Code'), findsOneWidget);

      const digits = ['6', '5', '4', '3', '2', '1'];
      for (var i = 0; i < 6; i++) {
        await tester.enterText(find.byKey(Key('otp_digit_$i')), digits[i]);
      }

      final verifyBtn = find.text('Verify Code');
      await tester.ensureVisible(verifyBtn);
      await tester.tap(verifyBtn);
      await tester.pumpAndSettle();

      expect(find.text('Reset Password'), findsOneWidget);
      final resetFields = find.byType(TextField);
      await tester.enterText(resetFields.at(0), 'NewOrbit!2026');
      await tester.enterText(resetFields.at(1), 'NewOrbit!2026');

      final updateBtn = find.text('Update Password');
      await tester.ensureVisible(updateBtn);
      await tester.tap(updateBtn);
      await tester.pumpAndSettle();

      expect(resetSubmitted, isTrue);
      expect(find.text('Welcome Back'), findsOneWidget);
    });

    testWidgets('LoginScreen allows configuring, testing, and persisting backend Server URL at runtime',
        (tester) async {
      final storage = InMemorySessionStorage();
      var healthChecked = false;
      final api = OrbitCareApiClient(
        baseUrl: '',
        transport: _MockTransport((method, uri, headers, body) async {
          if (method == 'GET' && uri.path == '/api/health') {
            healthChecked = true;
            return _jsonResp(200, {
              'success': true,
              'message': 'OrbitCare API is running',
              'database': 'connected',
            });
          }
          return _jsonResp(404, {'message': 'Not found'});
        }),
      );
      final controller = SessionController(apiClient: api, storage: storage);

      await tester.pumpWidget(
        OrbitCareApp(
          sessionController: controller,
          initialRoute: AppRoutes.login,
        ),
      );

      expect(controller.apiClient.isConfigured, isFalse);
      await tester.tap(find.byKey(const Key('configure_server_url_btn')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('server_url_input')),
        'https://demo.orbitcare.example/api/',
      );
      final testBtn = find.byKey(const Key('test_connection_btn'));
      await tester.ensureVisible(testBtn);
      await tester.tap(testBtn);
      await tester.pumpAndSettle();

      expect(healthChecked, isTrue);
      expect(find.textContaining('Connected'), findsOneWidget);

      final saveBtn = find.byKey(const Key('save_server_url_btn'));
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(controller.apiClient.isConfigured, isTrue);
      expect(controller.apiBaseUrl, 'https://demo.orbitcare.example');
      expect(await storage.readApiBaseUrl(), 'https://demo.orbitcare.example');
    });

    testWidgets(
      'SignupScreen shows user-friendly server setup CTA when unconfigured, allows configuring & testing /api/health, then creates account',
      (tester) async {
        final storage = InMemorySessionStorage();
        var healthCalled = false;
        var registerCalled = false;

        final api = OrbitCareApiClient(
          baseUrl: '',
          transport: _MockTransport((method, uri, headers, body) async {
            if (method == 'GET' && uri.path == '/api/health') {
              healthCalled = true;
              return _jsonResp(200, {
                'success': true,
                'message': 'OrbitCare API is running',
                'database': 'connected',
              });
            }
            if (method == 'POST' && uri.path == '/api/auth/register') {
              registerCalled = true;
              final parsed = jsonDecode(body ?? '{}') as Map<String, dynamic>;
              expect(parsed['fullName'], 'Dr. Nadia Salem');
              expect(parsed['email'], 'nadia@orbitcare.test');
              return _jsonResp(201, {
                'success': true,
                'message': 'User registered successfully',
              });
            }
            return _jsonResp(404, {'message': 'Not found'});
          }),
        );

        final controller = SessionController(apiClient: api, storage: storage);
        await tester.pumpWidget(
          OrbitCareApp(
            sessionController: controller,
            initialRoute: AppRoutes.signup,
          ),
        );

        // Must NOT show raw developer --dart-define flag on Signup screen.
        expect(find.textContaining('--dart-define'), findsNothing);
        expect(
          find.byKey(const Key('signup_configure_server_url_btn')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('signup_configure_server_url_btn')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('server_url_input')),
          'https://api.orbitcare.example/api/api/',
        );
        final testBtn = find.byKey(const Key('test_connection_btn'));
        await tester.ensureVisible(testBtn);
        await tester.tap(testBtn);
        await tester.pumpAndSettle();

        expect(healthCalled, isTrue);
        expect(find.textContaining('Connected'), findsOneWidget);

        final saveBtn = find.byKey(const Key('save_server_url_btn'));
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        expect(controller.apiBaseUrl, 'https://api.orbitcare.example');
        expect(await storage.readApiBaseUrl(), 'https://api.orbitcare.example');

        // Fill Signup form and create account against configured URL.
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'Dr. Nadia Salem');
        await tester.enterText(fields.at(1), 'nadia@orbitcare.test');
        await tester.enterText(fields.at(2), 'OrbitPass!2026');
        await tester.enterText(fields.at(3), 'OrbitPass!2026');

        final createBtn = find.widgetWithText(ElevatedButton, 'Create Account');
        await tester.ensureVisible(createBtn);
        await tester.tap(createBtn);
        await tester.pumpAndSettle();

        expect(registerCalled, isTrue);
        expect(find.text('Verify Your Email'), findsOneWidget);
      },
    );
  });

  group('API URL validation, precedence, persistence, and /api/health checks', () {
    test('normalizeApiBaseUrl strips trailing slashes and duplicate /api suffixes', () {
      expect(
        normalizeApiBaseUrl('  https://api.orbitcare.example/api/api///  '),
        'https://api.orbitcare.example',
      );
      expect(
        normalizeApiBaseUrl('http://192.168.1.50:5000/api'),
        'http://192.168.1.50:5000',
      );
      expect(
        validateApiBaseUrl('api.orbitcare.example'),
        contains('https:// or http://'),
      );
      expect(
        validateApiBaseUrl('https://user:pass@api.orbitcare.example'),
        contains('credentials'),
      );
      expect(validateApiBaseUrl(''), isNotNull);
    });

    test('resolveEffectiveApiBaseUrl enforces saved > buildDefault > unconfigured', () {
      final fromSaved = resolveEffectiveApiBaseUrl(
        savedUrl: 'https://saved.orbitcare.example/api/',
        buildDefaultUrl: 'https://default.orbitcare.example',
      );
      expect(fromSaved.baseUrl, 'https://saved.orbitcare.example');
      expect(fromSaved.source, ApiUrlSource.saved);

      final fromDefault = resolveEffectiveApiBaseUrl(
        savedUrl: '',
        buildDefaultUrl: 'https://default.orbitcare.example/api',
      );
      expect(fromDefault.baseUrl, 'https://default.orbitcare.example');
      expect(fromDefault.source, ApiUrlSource.buildDefault);

      final unconfigured = resolveEffectiveApiBaseUrl(
        savedUrl: null,
        buildDefaultUrl: '',
      );
      expect(unconfigured.isConfigured, isFalse);
      expect(unconfigured.source, ApiUrlSource.unconfigured);
    });

    test('ensureConfigLoaded restores persisted URL on restart and reset restores build default',
        () async {
      final storage = InMemorySessionStorage();
      await storage.writeApiBaseUrl('https://saved.orbitcare.example');

      final api = OrbitCareApiClient(
        baseUrl: 'https://default.orbitcare.example',
        transport: _MockTransport((m, u, h, b) async => _jsonResp(200, {'success': true})),
      );
      final controller = SessionController(
        apiClient: api,
        storage: storage,
        buildDefaultBaseUrl: 'https://default.orbitcare.example',
      );

      await controller.ensureConfigLoaded();
      expect(controller.apiBaseUrl, 'https://saved.orbitcare.example');
      expect(controller.urlSource, ApiUrlSource.saved);

      await controller.resetApiBaseUrlToDefault();
      expect(controller.apiBaseUrl, 'https://default.orbitcare.example');
      expect(controller.urlSource, ApiUrlSource.buildDefault);
      expect(await storage.readApiBaseUrl(), isNull);
    });

    test('checkHealth distinguishes connected, timeout, unreachable, serverError, invalidUrl, and missingConfig',
        () async {
      final apiMissing = OrbitCareApiClient(
        baseUrl: '',
        transport: _MockTransport((m, u, h, b) async => _jsonResp(200, {'success': true})),
      );
      expect(
        (await apiMissing.checkHealth()).status,
        ConnectionCheckStatus.missingConfig,
      );
      expect(
        (await apiMissing.checkHealth(baseUrlOverride: 'not-a-url')).status,
        ConnectionCheckStatus.invalidUrl,
      );

      final apiConnected = OrbitCareApiClient(
        baseUrl: 'https://ok.orbitcare.test',
        transport: _MockTransport((m, u, h, b) async {
          expect(m, 'GET');
          expect(u.toString(), 'https://ok.orbitcare.test/api/health');
          return _jsonResp(200, {
            'success': true,
            'message': 'OrbitCare API is running',
            'database': 'connected',
          });
        }),
      );
      final okResult = await apiConnected.checkHealth();
      expect(okResult.status, ConnectionCheckStatus.connected);
      expect(okResult.statusCode, 200);
      expect(okResult.databaseStatus, 'connected');

      final apiTimeout = OrbitCareApiClient(
        baseUrl: 'https://slow.orbitcare.test',
        transport: _MockTransport((m, u, h, b) async {
          throw TimeoutException('request timed out');
        }),
      );
      expect(
        (await apiTimeout.checkHealth()).status,
        ConnectionCheckStatus.timeout,
      );

      final apiUnreachable = OrbitCareApiClient(
        baseUrl: 'https://down.orbitcare.test',
        transport: _MockTransport((m, u, h, b) async {
          throw Exception('SocketException: Connection refused');
        }),
      );
      expect(
        (await apiUnreachable.checkHealth()).status,
        ConnectionCheckStatus.unreachable,
      );

      final apiServerError = OrbitCareApiClient(
        baseUrl: 'https://err.orbitcare.test',
        transport: _MockTransport((m, u, h, b) async {
          return _jsonResp(503, {'message': 'Database unavailable'});
        }),
      );
      final errResult = await apiServerError.checkHealth();
      expect(errResult.status, ConnectionCheckStatus.serverError);
      expect(errResult.statusCode, 503);
    });

    test('getMe unwraps backend nested { status: success, data: { user } } payload', () async {
      final api = OrbitCareApiClient(
        baseUrl: 'https://api.orbitcare.test',
        transport: _MockTransport((method, uri, headers, body) async {
          expect(method, 'GET');
          expect(uri.path, '/api/users/me');
          expect(headers['Authorization'], 'Bearer tok-123');
          return _jsonResp(200, {
            'status': 'success',
            'data': {
              'user': {
                '_id': 'usr-42',
                'name': 'Commander Elena Rostova',
                'email': 'elena@orbitcare.test',
                'role': 'astronaut',
              },
            },
          });
        }),
      );

      final user = await api.getMe(token: 'tok-123');
      expect(user.id, 'usr-42');
      expect(user.name, 'Commander Elena Rostova');
      expect(user.email, 'elena@orbitcare.test');
    });

    test('DashboardAverages parses backend average* keys as well as avg* keys', () {
      final averages = DashboardAverages.fromJson({
        'averageHeartRate': 76.5,
        'averageSpo2': 98.4,
        'averageRespiratoryRate': 15.2,
        'averageTemperature': 36.8,
      });
      expect(averages.heartRate, 76.5);
      expect(averages.spo2, 98.4);
      expect(averages.respiratoryRate, 15.2);
      expect(averages.temperature, 36.8);
    });
  });

  group('Model formatting helpers', () {
    test('formatOrbitTimestamp formats valid DateTime and handles null', () {
      expect(formatOrbitTimestamp(null), 'Timestamp unavailable');
      final formatted = formatOrbitTimestamp(DateTime.utc(2026, 11, 15, 14, 5));
      expect(formatted, contains('2026'));
      expect(formatted, contains('Nov'));
    });
  });
}
