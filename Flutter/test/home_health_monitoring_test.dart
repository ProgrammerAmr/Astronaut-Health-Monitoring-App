import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasa/cognitive_state/models/cognitive_state_models.dart';
import 'package:nasa/cognitive_state/services/csm_http_transport.dart';
import 'package:nasa/core/models/orbitcare_models.dart';
import 'package:nasa/core/services/orbitcare_api_client.dart';
import 'package:nasa/core/state/session_controller.dart';
import 'package:nasa/core/storage/session_storage.dart';
import 'package:nasa/main.dart';
import 'package:nasa/routes/app_routes.dart';

class _StatefulMockTransport implements CsmHttpTransport {
  final Future<CsmHttpResponse> Function(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) handler;

  _StatefulMockTransport(this.handler);

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

CsmHttpResponse _json(int status, Map<String, dynamic> body) {
  return CsmHttpResponse(statusCode: status, body: jsonEncode(body));
}

void main() {
  testWidgets(
      'Authenticated Home loads dashboard, vitals, alerts, reports, CSM status, creates measurement, marks alert read, and logs out',
      (tester) async {
    final measurements = <Map<String, dynamic>>[
      {
        '_id': 'm1',
        'heartRate': 74,
        'spo2': 98,
        'respiratoryRate': 15,
        'temperature': 36.8,
        'bloodPressure': {'systolic': 120, 'diastolic': 77},
        'measuredAt': '2026-11-15T10:00:00Z',
        'source': 'manual',
      },
    ];

    final alerts = <Map<String, dynamic>>[
      {
        '_id': 'a1',
        'title': '[SYNTHETIC DEMO] Hydration Reminder',
        'message': 'Simulated hydration check required.',
        'severity': 'medium',
        'isRead': false,
        'createdAt': '2026-11-15T09:30:00Z',
      },
    ];

    String? capturedCsmAuthHeader;
    var monthlyReportRequested = false;

    final transport = _StatefulMockTransport((method, uri, headers, body) async {
      // Every protected call must include real Bearer token
      expect(headers['Authorization'], 'Bearer live-session-jwt');

      if (method == 'GET' && uri.path == '/api/dashboard') {
        return _json(200, {
          'status': 'success',
          'data': {
            'totalMeasurements': measurements.length,
            'unreadAlerts':
                alerts.where((a) => a['isRead'] != true).length,
            'latestMeasurement': measurements.first,
            'averages': {'heartRate': 74, 'spo2': 98},
          },
        });
      }

      if (method == 'GET' && uri.path == '/api/measurements') {
        return _json(200, {'status': 'success', 'data': measurements});
      }

      if (method == 'POST' && uri.path == '/api/measurements') {
        final req = jsonDecode(body ?? '{}') as Map<String, dynamic>;
        final created = <String, dynamic>{
          '_id': 'm2',
          ...req,
          'measuredAt': '2026-11-15T12:00:00Z',
        };
        measurements.insert(0, created);
        return _json(201, {'status': 'success', 'data': created});
      }

      if (method == 'GET' && uri.path == '/api/alerts') {
        return _json(200, {'status': 'success', 'data': alerts});
      }

      if (method == 'PATCH' && uri.path == '/api/alerts/a1/read') {
        alerts[0]['isRead'] = true;
        return _json(200, {'status': 'success', 'data': alerts[0]});
      }

      if (method == 'GET' && uri.path == '/api/reports') {
        final period = uri.queryParameters['period'] ?? 'weekly';
        if (period == 'monthly') monthlyReportRequested = true;
        return _json(200, {
          'success': true,
          'data': {
            'period': period,
            'startDate': '2026-11-01T00:00:00Z',
            'endDate': '2026-11-15T12:00:00Z',
            'summary': {
              'records': measurements.length,
              'averageHeartRate': 74.5,
              'averageSpo2': 98.5,
              'averageRespiratoryRate': 15.0,
              'averageTemperature': 36.8,
              'totalSteps': 6850,
              'totalCalories': 2210,
              'totalSleepMinutes': 430,
            },
          },
        });
      }

      if (method == 'GET' && uri.path == '/api/cognitive-state/status') {
        capturedCsmAuthHeader = headers['Authorization'];
        return _json(200, {
          'service_available': true,
          'registered_model_available': false,
          'limitations': ['Experimental non-diagnostic prototype.'],
          'errors': <dynamic>[],
        });
      }

      if (method == 'POST' && uri.path == '/api/auth/logout') {
        return _json(200, {'success': true, 'message': 'Logged out'});
      }

      return _json(404, {'message': 'Unhandled $method ${uri.path}'});
    });

    final storage = InMemorySessionStorage();
    final api = OrbitCareApiClient(
      baseUrl: 'https://api.orbitcare.test',
      transport: transport,
    );
    final controller = SessionController(apiClient: api, storage: storage);
    await controller.establishSession(
      const AuthSession(
        token: 'live-session-jwt',
        user: AuthUser(
          id: 'u1',
          name: 'Alex Vance',
          email: 'alex@orbitcare.test',
          missionName: 'Orbital Demo Mission',
        ),
      ),
    );

    await tester.pumpWidget(
      OrbitCareApp(
        sessionController: controller,
        initialRoute: AppRoutes.home,
      ),
    );
    await tester.pumpAndSettle();

    // 1. Overview tab displays profile, latest vitals, and authenticated DEC-001 CSM card
    expect(find.text('Hello, Alex Vance'), findsOneWidget);
    expect(find.text('74 bpm'), findsOneWidget);
    expect(find.text('98%'), findsOneWidget);
    expect(capturedCsmAuthHeader, 'Bearer live-session-jwt');
    expect(find.text(kCsmResearchDisclaimer), findsOneWidget);
    expect(find.text('INSUFFICIENT_DATA'), findsOneWidget);

    // 2. Switch to Vitals tab and create a new measurement
    await tester.tap(find.text('Vitals'));
    await tester.pumpAndSettle();
    expect(find.text('120/77 mmHg'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fab_add_measurement')));
    await tester.pumpAndSettle();
    expect(find.text('Log Health Measurement'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('input_heart_rate')), '82');
    await tester.enterText(find.byKey(const Key('input_spo2')), '99');

    final saveBtn = find.text('Save Measurement');
    await tester.ensureVisible(saveBtn);
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    expect(find.text('82 bpm'), findsWidgets);

    // 3. Switch to Alerts tab and mark alert as read
    await tester.tap(find.text('Alerts'));
    await tester.pumpAndSettle();
    expect(find.text('[SYNTHETIC DEMO] Hydration Reminder'), findsOneWidget);
    expect(find.text('UNREAD'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mark_read_a1')));
    await tester.pumpAndSettle();
    expect(find.text('READ'), findsOneWidget);

    // 4. Switch to Reports tab and select Monthly
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('74.5 bpm'), findsOneWidget);
    expect(find.text('7h 10m'), findsOneWidget);

    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(monthlyReportRequested, isTrue);

    // 5. Logout clears session and navigates to LoginScreen
    await tester.tap(find.byKey(const Key('logout_button')));
    await tester.pumpAndSettle();
    expect(controller.isAuthenticated, isFalse);
    expect(await storage.readToken(), isNull);
    expect(find.text('Welcome Back'), findsOneWidget);
  });

  testWidgets('HomeScreen surfaces backend error state with Retry recovery',
      (tester) async {
    var shouldFailDashboard = true;

    final transport = _StatefulMockTransport((method, uri, headers, body) async {
      if (uri.path == '/api/dashboard') {
        if (shouldFailDashboard) {
          return _json(500, {'message': 'Database temporarily unavailable'});
        }
        return _json(200, {
          'status': 'success',
          'data': {
            'totalMeasurements': 3,
            'unreadAlerts': 0,
            'latestMeasurement': null,
            'averages': null,
          },
        });
      }
      if (uri.path == '/api/measurements') {
        return _json(200, {'status': 'success', 'data': <dynamic>[]});
      }
      if (uri.path == '/api/alerts') {
        return _json(200, {'status': 'success', 'data': <dynamic>[]});
      }
      if (uri.path == '/api/reports') {
        return _json(200, {
          'success': true,
          'data': {'period': 'weekly', 'summary': {'records': 0}},
        });
      }
      if (uri.path == '/api/cognitive-state/status') {
        return _json(503, {
          'service_available': false,
          'errors': [
            {'code': 'CSM_UPSTREAM_UNAVAILABLE', 'message': 'CSM offline'},
          ],
        });
      }
      return _json(404, {'message': 'Not found'});
    });

    final storage = InMemorySessionStorage();
    final api = OrbitCareApiClient(
      baseUrl: 'https://api.orbitcare.test',
      transport: transport,
    );
    final controller = SessionController(apiClient: api, storage: storage);
    await controller.establishSession(
      const AuthSession(
        token: 'jwt-retry-test',
        user: AuthUser(
          id: 'u1',
          name: 'Alex Vance',
          email: 'alex@orbitcare.test',
        ),
      ),
    );

    await tester.pumpWidget(
      OrbitCareApp(
        sessionController: controller,
        initialRoute: AppRoutes.home,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Database temporarily unavailable'), findsOneWidget);
    expect(find.text('SERVICE UNAVAILABLE'), findsOneWidget);

    shouldFailDashboard = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
  });
}
