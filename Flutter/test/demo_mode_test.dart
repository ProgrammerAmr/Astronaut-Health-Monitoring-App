import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasa/cognitive_state/models/cognitive_state_models.dart';
import 'package:nasa/cognitive_state/services/csm_http_transport.dart';
import 'package:nasa/core/demo/demo_cognitive_state_api_client.dart';
import 'package:nasa/core/demo/demo_health_repository.dart';
import 'package:nasa/core/services/orbitcare_api_client.dart';
import 'package:nasa/core/state/session_controller.dart';
import 'package:nasa/core/storage/session_storage.dart';
import 'package:nasa/main.dart';
import 'package:nasa/routes/app_routes.dart';

/// Strict guard proving Demo Mode never triggers accidental HTTP/network calls.
class _FailIfNetworkCalledTransport implements CsmHttpTransport {
  int callCount = 0;

  @override
  Future<CsmHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    required Duration timeout,
  }) async {
    callCount++;
    fail('Demo Mode must not perform network requests, tried: $method $uri');
  }
}

void main() {
  group('Offline Demo Mode repository & DEC-001 safety boundaries', () {
    test('DemoHealthRepository seeds consistent Daily/Weekly/Monthly data, persists local edits, and resets cleanly',
        () async {
      final storage = InMemorySessionStorage();
      final fixedNow = DateTime.utc(2026, 11, 15, 14, 0);
      final repo = DemoHealthRepository(
        storage: storage,
        nowProvider: () => fixedNow,
      );

      final dashboard = await repo.getDashboard();
      expect(dashboard.totalMeasurements, 10);
      expect(dashboard.unreadAlerts, 3);
      expect(dashboard.latestMeasurement, isNotNull);
      expect(dashboard.latestMeasurement!.heartRate, 72);
      expect(dashboard.latestMeasurement!.spo2, 99);

      // Daily (24h)=3, Weekly (7d)=7, Monthly (30d)=10
      final daily = await repo.getReport('daily');
      final weekly = await repo.getReport('weekly');
      final monthly = await repo.getReport('monthly');
      expect(daily.records, 3);
      expect(weekly.records, 7);
      expect(monthly.records, 10);

      // Alerts cover critical, high, medium, and low
      final alerts = await repo.getAlerts();
      final severities = alerts.map((a) => a.severity).toSet();
      expect(severities, containsAll(<String>['critical', 'high', 'medium', 'low']));

      // Creating an extreme measurement locally adds record + local demo threshold alert
      await repo.createMeasurement(<String, dynamic>{
        'heartRate': 125.0,
        'spo2': 98.0,
        'temperature': 37.0,
      });
      final afterAdd = await repo.getDashboard();
      expect(afterAdd.totalMeasurements, 11);
      expect(afterAdd.unreadAlerts, 4);

      // Marking an alert read persists across a fresh repository instance
      await repo.markAlertRead('demo-a-01');
      final reloadedRepo = DemoHealthRepository(
        storage: storage,
        nowProvider: () => fixedNow,
      );
      final reloadedDashboard = await reloadedRepo.getDashboard();
      expect(reloadedDashboard.totalMeasurements, 11);
      expect(reloadedDashboard.unreadAlerts, 3);

      // Reset restores exact clean 10-measurement / 3-unread baseline
      await reloadedRepo.resetToDefaults();
      final resetDashboard = await reloadedRepo.getDashboard();
      expect(resetDashboard.totalMeasurements, 10);
      expect(resetDashboard.unreadAlerts, 3);
    });

    test('DemoCognitiveStateApiClient never invents predictions and preserves DEC-001 abstention',
        () async {
      final csm = DemoCognitiveStateApiClient();
      expect(csm.isConfigured, isTrue);

      final status = await csm.fetchStatus(authToken: 'demo');
      expect(status.uiStatus, CognitiveStateUiStatus.insufficientData);
      expect(status.serviceStatus?.registeredModelAvailable, isFalse);

      final synthetic = await csm.analyze(
        mode: CognitiveStateMode.syntheticDemo,
        authToken: 'demo',
      );
      expect(synthetic.uiStatus, CognitiveStateUiStatus.syntheticDemo);
      expect(synthetic.analysis?.isSynthetic, isTrue);
      expect(synthetic.analysis?.modelStatus.validated, isFalse);
      expect(synthetic.analysis?.prediction.abstained, isTrue);
      expect(synthetic.analysis?.prediction.probabilities, isNull);

      final replay = await csm.analyze(
        mode: CognitiveStateMode.researchReplay,
        authToken: 'demo',
      );
      expect(replay.uiStatus, CognitiveStateUiStatus.insufficientData);
      expect(replay.analysis?.prediction.abstained, isTrue);
      expect(replay.analysis?.prediction.probabilities, isNull);
    });

    test('Demo Mode never touches or mixes with production tokens or server URL',
        () async {
      final storage = InMemorySessionStorage(
        initialApiBaseUrl: 'https://prod.orbitcare.example',
      );
      final guard = _FailIfNetworkCalledTransport();
      final controller = SessionController(
        apiClient: OrbitCareApiClient(baseUrl: '', transport: guard),
        storage: storage,
      );

      await controller.enterDemoMode();
      expect(controller.isDemoMode, isTrue);
      expect(await storage.readToken(), isNull);
      expect(await storage.readDemoModeActive(), isTrue);
      expect(await storage.readApiBaseUrl(), 'https://prod.orbitcare.example');
      expect(guard.callCount, 0);

      await controller.logout();
      expect(controller.isDemoMode, isFalse);
      expect(await storage.readDemoModeActive(), isFalse);
      expect(await storage.readApiBaseUrl(), 'https://prod.orbitcare.example');
      expect(guard.callCount, 0);
    });
  });

  group('Presentation Acceptance Walkthrough (End-to-End Offline Demo Mode)', () {
    testWidgets(
      'Walkthrough: Login -> Demo Mode -> Dashboard -> Vitals -> Add Measurement -> Alerts Details/Mark Read -> Reports -> Profile/Settings -> App Restart Persistence',
      (tester) async {
        final storage = InMemorySessionStorage();
        final guard = _FailIfNetworkCalledTransport();
        final controller = SessionController(
          apiClient: OrbitCareApiClient(baseUrl: '', transport: guard),
          storage: storage,
        );

        // 1. Fresh app launch on LoginScreen with NO backend URL configured
        await tester.pumpWidget(
          OrbitCareApp(
            sessionController: controller,
            initialRoute: AppRoutes.login,
          ),
        );
        await tester.pumpAndSettle();

        expect(controller.isProductionApiConfigured, isFalse);
        final demoBtn = find.byKey(const Key('continue_demo_user_btn'));
        await tester.ensureVisible(demoBtn);
        await tester.tap(demoBtn);
        await tester.pumpAndSettle();

        // 2. Reaches existing HomeScreen Dashboard in clearly labeled DEMO MODE
        expect(controller.isDemoMode, isTrue);
        expect(find.byKey(const Key('demo_mode_banner')), findsOneWidget);
        expect(find.text('DEMO MODE'), findsOneWidget);
        expect(find.textContaining('Commander Alex Vance'), findsOneWidget);

        // 3. Inspect all vital sign cards on Overview (HR, SpO2, Resp, Temp, BP, Sugar)
        expect(find.text('72 bpm'), findsWidgets);
        expect(find.text('99%'), findsWidgets);
        expect(find.text('15 br/min'), findsWidgets);
        expect(find.text('36.7 °C'), findsWidgets);
        expect(find.text('118/76 mmHg'), findsWidgets);
        expect(find.text('94 mg/dL'), findsWidgets);

        // 4. DEC-001 Cognitive State card operates offline with safe abstention & Synthetic Demo
        expect(find.text(kCsmResearchDisclaimer), findsOneWidget);
        expect(find.text('INSUFFICIENT_DATA'), findsOneWidget);
        final syntheticCsmBtn = find.text('Synthetic Demo');
        await tester.ensureVisible(syntheticCsmBtn);
        await tester.tap(syntheticCsmBtn);
        await tester.pumpAndSettle();
        expect(find.text('Synthetic Demo Output — Probabilities Withheld'), findsOneWidget);

        // 5. Navigate to Vitals tab, inspect history + trend chart, and log a new vital locally
        await tester.tap(find.text('Vitals'));
        await tester.pumpAndSettle();
        expect(find.text('Recent Heart Rate & SpO2 Trend'), findsOneWidget);
        expect(find.text('118/76 mmHg'), findsWidgets);

        await tester.tap(find.byKey(const Key('fab_add_measurement')));
        await tester.pumpAndSettle();
        expect(find.textContaining('Demo Mode (Offline)'), findsOneWidget);

        await tester.enterText(find.byKey(const Key('input_heart_rate')), '80');
        await tester.enterText(find.byKey(const Key('input_spo2')), '98');
        await tester.enterText(find.byKey(const Key('input_temperature')), '37.0');

        final saveMeasurementBtn = find.text('Save Measurement');
        await tester.ensureVisible(saveMeasurementBtn);
        await tester.tap(saveMeasurementBtn);
        await tester.pumpAndSettle();

        expect(find.text('80 bpm'), findsWidgets);

        // 6. Navigate to Alerts tab, inspect Critical/High/Medium/Low alerts, open details, mark read
        await tester.tap(find.text('Alerts'));
        await tester.pumpAndSettle();
        expect(find.text('CRITICAL'), findsOneWidget);
        expect(find.text('HIGH'), findsOneWidget);
        expect(find.text('[DEMO] Elevated Post-EVA Heart Rate (114 bpm)'), findsOneWidget);

        // Tap alert card to inspect Alert Details bottom sheet
        await tester.tap(find.byKey(const Key('alert_card_demo-a-01')));
        await tester.pumpAndSettle();
        expect(find.text('Alert Details'), findsOneWidget);

        // Mark as read from inside detail sheet
        await tester.tap(find.byKey(const Key('sheet_mark_read_demo-a-01')));
        await tester.pumpAndSettle();

        // Filter to Unread Only -> demo-a-01 no longer listed
        await tester.tap(find.text('Unread Only'));
        await tester.pumpAndSettle();
        expect(find.text('[DEMO] Elevated Post-EVA Heart Rate (114 bpm)'), findsNothing);
        expect(find.text('[DEMO] Mild SpO2 Dip During Simulated Exercise (95%)'), findsOneWidget);

        // 7. Navigate to Reports tab and verify Weekly, Daily, and Monthly summaries & charts
        await tester.tap(find.text('Reports'));
        await tester.pumpAndSettle();
        expect(find.textContaining('WEEKLY REPORT'), findsOneWidget);
        expect(find.textContaining('Weekly Vitals Trend'), findsOneWidget);

        await tester.tap(find.text('Daily'));
        await tester.pumpAndSettle();
        expect(find.textContaining('DAILY REPORT'), findsOneWidget);

        await tester.tap(find.text('Monthly'));
        await tester.pumpAndSettle();
        expect(find.textContaining('MONTHLY REPORT'), findsOneWidget);

        // 8. Open Profile & Settings, verify demo profile, toggle Fahrenheit, verify persisted change
        await tester.tap(find.byKey(const Key('profile_settings_btn')));
        await tester.pumpAndSettle();
        expect(find.text('Profile & Settings'), findsOneWidget);
        expect(find.text('Commander Alex Vance (Demo)'), findsOneWidget);
        expect(find.text('Orbital Demo Mission (Synthetic)'), findsOneWidget);

        final fSwitch = find.byKey(const Key('toggle_fahrenheit_switch'));
        await tester.ensureVisible(fSwitch);
        await tester.tap(fSwitch);
        await tester.pumpAndSettle();
        expect(controller.demoPreferences.useFahrenheit, isTrue);

        // Navigate back to Home -> temperature now formatted in °F
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.textContaining('°F'), findsWidgets);

        // 9. Simulate app restart with fresh SessionController sharing the same SessionStorage
        final restartedController = SessionController(
          apiClient: OrbitCareApiClient(baseUrl: '', transport: guard),
          storage: storage,
        );
        final restored = await restartedController.restoreSession();
        expect(restored, isTrue);
        expect(restartedController.isDemoMode, isTrue);
        expect(restartedController.demoPreferences.useFahrenheit, isTrue);

        // Newly logged 80 bpm measurement and acknowledged alert persisted across restart!
        final persistedMeasurements =
            await restartedController.apiClient.getMeasurements(
          token: restartedController.token!,
        );
        expect(persistedMeasurements.first.heartRate, 80);

        final persistedAlerts = await restartedController.apiClient.getAlerts(
          token: restartedController.token!,
          isRead: false,
        );
        expect(persistedAlerts.any((a) => a.id == 'demo-a-01'), isFalse);

        // 10. Verify ZERO network calls occurred across the entire walkthrough!
        expect(guard.callCount, 0);
      },
    );

    testWidgets('SignupScreen also provides direct Continue as Demo User entry',
        (tester) async {
      final storage = InMemorySessionStorage();
      final guard = _FailIfNetworkCalledTransport();
      final controller = SessionController(
        apiClient: OrbitCareApiClient(baseUrl: '', transport: guard),
        storage: storage,
      );

      await tester.pumpWidget(
        OrbitCareApp(
          sessionController: controller,
          initialRoute: AppRoutes.signup,
        ),
      );
      await tester.pumpAndSettle();

      final demoBtn = find.byKey(const Key('signup_continue_demo_user_btn'));
      await tester.ensureVisible(demoBtn);
      await tester.tap(demoBtn);
      await tester.pumpAndSettle();

      expect(controller.isDemoMode, isTrue);
      expect(find.byKey(const Key('demo_mode_banner')), findsOneWidget);
      expect(guard.callCount, 0);
    });
  });
}
