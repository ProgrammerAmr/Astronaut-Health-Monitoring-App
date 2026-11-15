import '../../cognitive_state/models/cognitive_state_models.dart';
import '../../cognitive_state/services/cognitive_state_api_client.dart';

/// Offline Demo Mode implementation of [CognitiveStateApiClient].
///
/// Strictly preserves every DEC-001 safety boundary without making network calls:
/// - Never invents probabilities or clinical predictions.
/// - Clearly discloses offline synthetic demo state and safe abstention.
class DemoCognitiveStateApiClient extends CognitiveStateApiClient {
  DemoCognitiveStateApiClient() : super(baseUrl: '');

  @override
  bool get isConfigured => true;

  @override
  Future<CognitiveStateUiSnapshot> fetchStatus({String? authToken}) async {
    const status = CognitiveStateServiceStatus(
      apiVersion: 'v1-demo-local',
      schemaVersion: '1.0-dec001-draft',
      serviceAvailable: true,
      registeredModelAvailable: false,
      liveSensorEnabled: false,
      rawSignalPersistence: false,
      supportedModes: <String>['synthetic_demo', 'research_replay'],
      modelStatus: ModelStatusInfo(
        modelId: null,
        validated: false,
        calibrated: false,
        cohortLimitations: kCsmDefaultLimitations,
      ),
      limitations: kCsmDefaultLimitations,
    );

    return const CognitiveStateUiSnapshot(
      uiStatus: CognitiveStateUiStatus.insufficientData,
      serviceStatus: status,
      message:
          'Offline Demo Mode active: Cognitive State Monitoring runs locally with safe INSUFFICIENT_DATA abstention because no validated NASA SHARP-1 model artifact is bundled on device. Tap "Synthetic Demo" to inspect the provenance-labeled demo response.',
    );
  }

  @override
  Future<CognitiveStateUiSnapshot> analyze({
    required CognitiveStateMode mode,
    String? authToken,
    String? sessionId,
    double? windowEndSec,
    SignalQualityInfo? signalQuality,
    String? dataProvenance,
  }) async {
    if (mode == CognitiveStateMode.syntheticDemo) {
      final analysis = CognitiveStateAnalysisResponse(
        schemaVersion: '1.0-dec001-draft',
        status: 'INSUFFICIENT_DATA',
        mode: CognitiveStateMode.syntheticDemo.apiValue,
        demoMode: true,
        astronautId: 'demo-astronaut-001',
        sessionId: sessionId ?? 'offline-synthetic-demo',
        windowEndSec: windowEndSec ?? 120.0,
        dataProvenance: 'synthetic',
        prediction: const CognitiveStatePrediction(
          state: null,
          probabilities: null,
          confidence: null,
          abstained: true,
        ),
        signalQuality: const SignalQualityInfo(
          sqiScore: 0.94,
          valid: true,
          reasons: <String>['synthetic_offline_demo_preview'],
        ),
        modelStatus: const ModelStatusInfo(
          modelId: null,
          validated: false,
          calibrated: false,
          cohortLimitations: kCsmDefaultLimitations,
        ),
        warnings: const <String>[
          'Offline Demo Mode: Synthetic demo preview only. No real physiological telemetry and no trained CSM model exist on this device; probabilities are intentionally withheld.',
        ],
      );

      return CognitiveStateUiSnapshot(
        uiStatus: CognitiveStateUiStatus.syntheticDemo,
        analysis: analysis,
      );
    }

    final replayAnalysis = CognitiveStateAnalysisResponse(
      schemaVersion: '1.0-dec001-draft',
      status: 'INSUFFICIENT_DATA',
      mode: CognitiveStateMode.researchReplay.apiValue,
      demoMode: true,
      astronautId: 'demo-astronaut-001',
      sessionId: sessionId ?? 'offline-replay-check',
      windowEndSec: windowEndSec ?? 120.0,
      dataProvenance: 'real_nasa_csm_replay',
      prediction: const CognitiveStatePrediction(
        state: null,
        probabilities: null,
        confidence: null,
        abstained: true,
      ),
      signalQuality: signalQuality ??
          const SignalQualityInfo(
            sqiScore: 0.95,
            valid: true,
            reasons: <String>[
              'no_registered_model_artifact_in_offline_demo',
            ],
          ),
      modelStatus: const ModelStatusInfo(
        modelId: null,
        validated: false,
        calibrated: false,
        cohortLimitations: kCsmDefaultLimitations,
      ),
      warnings: const <String>[
        'Offline Demo Mode abstained safely (INSUFFICIENT_DATA): NASA SHARP-1 research replay requires a connected research backend and validated model artifact. No prediction was fabricated.',
      ],
    );

    return CognitiveStateUiSnapshot(
      uiStatus: CognitiveStateUiStatus.insufficientData,
      analysis: replayAnalysis,
      message:
          'Safe abstention (INSUFFICIENT_DATA): Offline Demo Mode does not bundle a validated research replay model and never fabricates attention probabilities.',
    );
  }
}
