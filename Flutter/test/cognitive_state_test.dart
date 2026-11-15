import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nasa/cognitive_state/models/cognitive_state_models.dart';
import 'package:nasa/cognitive_state/services/cognitive_state_api_client.dart';
import 'package:nasa/cognitive_state/services/csm_http_transport.dart';
import 'package:nasa/home/home_screen.dart';

class _FakeTransport implements CsmHttpTransport {
  final Future<CsmHttpResponse> Function(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) handler;

  _FakeTransport(this.handler);

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

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('CognitiveStateApiClient', () {
    test('returns unavailable when base URL or auth token is missing', () async {
      final unconfigured = CognitiveStateApiClient(baseUrl: '');
      final r1 = await unconfigured.fetchStatus(authToken: 'tok');
      expect(r1.uiStatus, CognitiveStateUiStatus.unavailable);
      expect(r1.errorCode, 'API_BASE_URL_UNCONFIGURED');

      final noToken = CognitiveStateApiClient(
        baseUrl: 'https://api.example.test',
      );
      final r2 = await noToken.analyze(mode: CognitiveStateMode.syntheticDemo);
      expect(r2.uiStatus, CognitiveStateUiStatus.unavailable);
      expect(r2.errorCode, 'AUTH_SESSION_REQUIRED');
    });

    test('maps timeout and 503 responses to unavailable without substituting predictions', () async {
      final timeoutClient = CognitiveStateApiClient(
        baseUrl: 'https://api.example.test',
        transport: _FakeTransport((_, _, _, _) async {
          throw TimeoutException('timed out');
        }),
      );
      final rTimeout = await timeoutClient.analyze(
        mode: CognitiveStateMode.researchReplay,
        authToken: 'jwt-token',
      );
      expect(rTimeout.uiStatus, CognitiveStateUiStatus.unavailable);
      expect(rTimeout.analysis, isNull);

      final downClient = CognitiveStateApiClient(
        baseUrl: 'https://api.example.test',
        transport: _FakeTransport((_, _, _, _) async {
          return CsmHttpResponse(
            statusCode: 503,
            body: jsonEncode({
              'status': 'ERROR',
              'data_provenance': 'unknown',
              'prediction': {'abstained': true},
              'errors': [
                {'code': 'CSM_UPSTREAM_UNAVAILABLE', 'message': 'Upstream down'},
              ],
            }),
          );
        }),
      );
      final rDown = await downClient.analyze(
        mode: CognitiveStateMode.researchReplay,
        authToken: 'jwt-token',
      );
      expect(rDown.uiStatus, CognitiveStateUiStatus.unavailable);
      expect(rDown.errorCode, 'CSM_UPSTREAM_UNAVAILABLE');
    });

    test('parses synthetic_demo response as syntheticDemo with validated=false and no invented probabilities', () async {
      final client = CognitiveStateApiClient(
        baseUrl: 'https://api.example.test',
        transport: _FakeTransport((method, uri, headers, body) async {
          expect(method, 'POST');
          expect(uri.path, '/api/cognitive-state/analyze');
          expect(headers['Authorization'], 'Bearer test-jwt');
          return CsmHttpResponse(
            statusCode: 200,
            body: jsonEncode({
              'schema_version': '1.0-dec001-draft',
              'status': 'INSUFFICIENT_DATA',
              'mode': 'synthetic_demo',
              'demo_mode': true,
              'data_provenance': 'synthetic',
              'prediction': {
                'state': null,
                'probabilities': null,
                'confidence': null,
                'abstained': true,
              },
              'signal_quality': {'valid': true, 'sqi_score': 0.92, 'reasons': []},
              'model_status': {'model_id': null, 'validated': false, 'calibrated': false},
              'warnings': ['Synthetic demo data only.'],
              'errors': [],
            }),
          );
        }),
      );

      final res = await client.analyze(
        mode: CognitiveStateMode.syntheticDemo,
        authToken: 'test-jwt',
      );
      expect(res.uiStatus, CognitiveStateUiStatus.syntheticDemo);
      expect(res.analysis?.dataProvenance, 'synthetic');
      expect(res.analysis?.modelStatus.validated, isFalse);
      expect(res.analysis?.prediction.probabilities, isNull);
    });
  });

  group('HomeScreen CognitiveStateResearchCard 6 distinct UI states', () {
    testWidgets('1. loading state displays disclaimer and progress indicator', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const HomeScreen(
            autoFetchCsmStatus: false,
            initialCsmSnapshot: CognitiveStateUiSnapshot(
              uiStatus: CognitiveStateUiStatus.loading,
            ),
          ),
        ),
      );
      expect(find.text(kCsmResearchDisclaimer), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('2. unavailable state displays service unavailable banner', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const HomeScreen(
            autoFetchCsmStatus: false,
            initialCsmSnapshot: CognitiveStateUiSnapshot(
              uiStatus: CognitiveStateUiStatus.unavailable,
              errorCode: 'CSM_UPSTREAM_UNAVAILABLE',
              message: 'Backend unavailable.',
            ),
          ),
        ),
      );
      expect(find.text(kCsmResearchDisclaimer), findsOneWidget);
      expect(find.text('SERVICE UNAVAILABLE'), findsOneWidget);
      expect(find.text('Backend unavailable.'), findsOneWidget);
    });

    testWidgets('3. INSUFFICIENT_DATA state displays safe abstention details', (tester) async {
      final resp = CognitiveStateAnalysisResponse.fromJson({
        'schema_version': '1.0-dec001-draft',
        'status': 'INSUFFICIENT_DATA',
        'mode': 'research_replay',
        'data_provenance': 'real_nasa_csm_replay',
        'prediction': {'abstained': true},
        'signal_quality': {
          'valid': true,
          'sqi_score': 0.94,
          'reasons': ['NO_REGISTERED_MODEL_ARTIFACT'],
        },
        'model_status': {'validated': false, 'calibrated': false},
      });
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            autoFetchCsmStatus: false,
            initialCsmSnapshot: CognitiveStateUiSnapshot(
              uiStatus: CognitiveStateUiStatus.insufficientData,
              analysis: resp,
            ),
          ),
        ),
      );
      expect(find.text(kCsmResearchDisclaimer), findsOneWidget);
      expect(find.text('INSUFFICIENT_DATA'), findsOneWidget);
      expect(find.textContaining('NO_REGISTERED_MODEL_ARTIFACT'), findsOneWidget);
    });

    testWidgets('4. ERROR state displays error code without substituting predictions', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const HomeScreen(
            autoFetchCsmStatus: false,
            initialCsmSnapshot: CognitiveStateUiSnapshot(
              uiStatus: CognitiveStateUiStatus.error,
              errorCode: 'LIVE_SENSOR_UNSUPPORTED',
              message: 'Live sensor rejected.',
            ),
          ),
        ),
      );
      expect(find.text(kCsmResearchDisclaimer), findsOneWidget);
      expect(find.text('ERROR'), findsOneWidget);
      expect(find.text('Live sensor rejected.'), findsOneWidget);
    });

    testWidgets('5. synthetic demo state prominently displays Synthetic demo data label', (tester) async {
      final resp = CognitiveStateAnalysisResponse.fromJson({
        'schema_version': '1.0-dec001-draft',
        'status': 'INSUFFICIENT_DATA',
        'mode': 'synthetic_demo',
        'demo_mode': true,
        'data_provenance': 'synthetic',
        'prediction': {'abstained': true},
        'signal_quality': {'valid': true, 'sqi_score': 0.92, 'reasons': []},
        'model_status': {'validated': false, 'calibrated': false},
        'warnings': ['Synthetic demo data: probabilities withheld.'],
      });
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            autoFetchCsmStatus: false,
            initialCsmSnapshot: CognitiveStateUiSnapshot(
              uiStatus: CognitiveStateUiStatus.syntheticDemo,
              analysis: resp,
            ),
          ),
        ),
      );
      expect(find.text(kCsmResearchDisclaimer), findsOneWidget);
      expect(find.text(kCsmSyntheticDemoLabel), findsWidgets);
      expect(find.text('Model Validated: false'), findsOneWidget);
    });

    testWidgets('6. valid research response state renders state, probabilities, and provenance', (tester) async {
      final resp = CognitiveStateAnalysisResponse.fromJson({
        'schema_version': '1.0-dec001-draft',
        'status': 'OK',
        'mode': 'research_replay',
        'data_provenance': 'real_nasa_csm_replay',
        'prediction': {
          'state': 'CA',
          'probabilities': {'Baseline': 0.15, 'CA': 0.72, 'DA': 0.08, 'SS': 0.05},
          'confidence': 0.72,
          'abstained': false,
        },
        'signal_quality': {'valid': true, 'sqi_score': 0.96, 'reasons': []},
        'model_status': {'validated': false, 'calibrated': true},
      });
      await tester.pumpWidget(
        _wrap(
          HomeScreen(
            autoFetchCsmStatus: false,
            initialCsmSnapshot: CognitiveStateUiSnapshot(
              uiStatus: CognitiveStateUiStatus.validResearch,
              analysis: resp,
            ),
          ),
        ),
      );
      expect(find.text(kCsmResearchDisclaimer), findsOneWidget);
      expect(find.text('RESEARCH REPLAY'), findsOneWidget);
      expect(find.text('CA'), findsWidgets);
      expect(find.text('72.0%'), findsWidgets);
    });
  });
}
