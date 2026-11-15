const String kCsmResearchDisclaimer =
    'Experimental research prototype — not a medical diagnosis or flight-certified system.';

const String kCsmSyntheticDemoLabel = 'Synthetic demo data';

const List<String> kCsmDefaultLimitations = <String>[
  'Experimental research prototype — not a medical diagnosis or flight-certified system.',
  'No trained or validated CSM model artifact is currently shipped; research replay abstains safely with INSUFFICIENT_DATA.',
  'NASA SHARP-1 cohort comprises 100% male commercial airline pilots in a 1g simulator; not validated on astronauts or microgravity physiology.',
  'Live-sensor inference is disabled until an approved signal schema, physical units, sampling rate, and verified model artifact exist.',
];

enum CognitiveStateUiStatus {
  loading,
  unavailable,
  insufficientData,
  error,
  syntheticDemo,
  validResearch,
}

enum CognitiveStateMode {
  syntheticDemo('synthetic_demo'),
  researchReplay('research_replay');

  const CognitiveStateMode(this.apiValue);
  final String apiValue;
}

class CognitiveStateError {
  final String code;
  final String message;

  const CognitiveStateError({
    required this.code,
    required this.message,
  });

  factory CognitiveStateError.fromJson(Map<String, dynamic> json) {
    return CognitiveStateError(
      code: (json['code'] ?? 'UNKNOWN_ERROR').toString(),
      message: (json['message'] ?? 'An unexpected error occurred.').toString(),
    );
  }
}

class CognitiveStatePrediction {
  final String? state;
  final Map<String, double>? probabilities;
  final double? confidence;
  final bool abstained;

  const CognitiveStatePrediction({
    this.state,
    this.probabilities,
    this.confidence,
    required this.abstained,
  });

  factory CognitiveStatePrediction.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const CognitiveStatePrediction(abstained: true);
    }

    Map<String, double>? parsedProbs;
    final rawProbs = json['probabilities'];
    if (rawProbs is Map) {
      final map = <String, double>{};
      for (final entry in rawProbs.entries) {
        final v = entry.value;
        if (v is num && v.isFinite) {
          map[entry.key.toString()] = v.toDouble().clamp(0.0, 1.0);
        }
      }
      if (map.isNotEmpty) {
        parsedProbs = map;
      }
    }

    final rawConf = json['confidence'];
    final double? conf =
        (rawConf is num && rawConf.isFinite) ? rawConf.toDouble() : null;

    return CognitiveStatePrediction(
      state: json['state']?.toString(),
      probabilities: parsedProbs,
      confidence: conf,
      abstained: json['abstained'] == true || json['state'] == null,
    );
  }
}

class SignalQualityInfo {
  final double sqiScore;
  final bool valid;
  final List<String> reasons;

  const SignalQualityInfo({
    required this.sqiScore,
    required this.valid,
    this.reasons = const <String>[],
  });

  factory SignalQualityInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SignalQualityInfo(sqiScore: 0.0, valid: false);
    }
    final rawScore = json['sqi_score'];
    final score =
        (rawScore is num && rawScore.isFinite) ? rawScore.toDouble() : 0.0;
    final rawReasons = json['reasons'];
    final reasons = rawReasons is List
        ? rawReasons.map((e) => e.toString()).toList()
        : const <String>[];
    return SignalQualityInfo(
      sqiScore: score.clamp(0.0, 1.0),
      valid: json['valid'] == true,
      reasons: reasons,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'valid': valid,
      'sqi_score': sqiScore,
      'reasons': reasons,
    };
  }
}

class ModelStatusInfo {
  final String? modelId;
  final bool validated;
  final bool calibrated;
  final String? evaluationProtocol;
  final List<String> cohortLimitations;

  const ModelStatusInfo({
    this.modelId,
    this.validated = false,
    this.calibrated = false,
    this.evaluationProtocol,
    this.cohortLimitations = kCsmDefaultLimitations,
  });

  factory ModelStatusInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ModelStatusInfo();
    }
    final rawLimits = json['cohort_limitations'];
    final limits = rawLimits is List
        ? rawLimits.map((e) => e.toString()).toList()
        : kCsmDefaultLimitations;
    return ModelStatusInfo(
      modelId: json['model_id']?.toString(),
      validated: json['validated'] == true,
      calibrated: json['calibrated'] == true,
      evaluationProtocol: json['evaluation_protocol']?.toString(),
      cohortLimitations: limits,
    );
  }
}

class CognitiveStateAnalysisResponse {
  final String schemaVersion;
  final String status;
  final String? mode;
  final bool demoMode;
  final String? astronautId;
  final String? sessionId;
  final double? windowEndSec;
  final String dataProvenance;
  final CognitiveStatePrediction prediction;
  final SignalQualityInfo signalQuality;
  final ModelStatusInfo modelStatus;
  final List<String> warnings;
  final List<CognitiveStateError> errors;
  final String disclaimer;

  const CognitiveStateAnalysisResponse({
    required this.schemaVersion,
    required this.status,
    this.mode,
    this.demoMode = false,
    this.astronautId,
    this.sessionId,
    this.windowEndSec,
    required this.dataProvenance,
    required this.prediction,
    required this.signalQuality,
    required this.modelStatus,
    this.warnings = const <String>[],
    this.errors = const <CognitiveStateError>[],
    this.disclaimer = kCsmResearchDisclaimer,
  });

  bool get isSynthetic =>
      dataProvenance == 'synthetic' ||
      demoMode ||
      mode == CognitiveStateMode.syntheticDemo.apiValue;

  CognitiveStateUiStatus resolveUiStatus() {
    if (status == 'ERROR' || errors.isNotEmpty) {
      return CognitiveStateUiStatus.error;
    }
    if (isSynthetic) {
      return CognitiveStateUiStatus.syntheticDemo;
    }
    if (status == 'OK' &&
        !prediction.abstained &&
        prediction.state != null &&
        dataProvenance == 'real_nasa_csm_replay') {
      return CognitiveStateUiStatus.validResearch;
    }
    return CognitiveStateUiStatus.insufficientData;
  }

  factory CognitiveStateAnalysisResponse.fromJson(Map<String, dynamic> json) {
    final rawWarnings = json['warnings'];
    final warnings = rawWarnings is List
        ? rawWarnings.map((e) => e.toString()).toList()
        : const <String>[];

    final rawErrors = json['errors'];
    final errors = <CognitiveStateError>[];
    if (rawErrors is List) {
      for (final item in rawErrors) {
        if (item is Map<String, dynamic>) {
          errors.add(CognitiveStateError.fromJson(item));
        } else if (item is Map) {
          errors.add(
            CognitiveStateError.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final rawWinEnd = json['window_end_sec'];
    final double? windowEnd = (rawWinEnd is num && rawWinEnd.isFinite)
        ? rawWinEnd.toDouble()
        : null;

    final rawPrediction = json['prediction'];
    final rawSqi = json['signal_quality'];
    final rawModel = json['model_status'];

    return CognitiveStateAnalysisResponse(
      schemaVersion: (json['schema_version'] ?? 'unknown').toString(),
      status: (json['status'] ?? 'INSUFFICIENT_DATA').toString(),
      mode: json['mode']?.toString(),
      demoMode: json['demo_mode'] == true,
      astronautId: json['astronaut_id']?.toString(),
      sessionId: json['session_id']?.toString(),
      windowEndSec: windowEnd,
      dataProvenance: (json['data_provenance'] ?? 'unknown').toString(),
      prediction: CognitiveStatePrediction.fromJson(
        rawPrediction is Map ? Map<String, dynamic>.from(rawPrediction) : null,
      ),
      signalQuality: SignalQualityInfo.fromJson(
        rawSqi is Map ? Map<String, dynamic>.from(rawSqi) : null,
      ),
      modelStatus: ModelStatusInfo.fromJson(
        rawModel is Map ? Map<String, dynamic>.from(rawModel) : null,
      ),
      warnings: warnings,
      errors: errors,
      disclaimer: (json['disclaimer'] ?? kCsmResearchDisclaimer).toString(),
    );
  }
}

class CognitiveStateServiceStatus {
  final String apiVersion;
  final String schemaVersion;
  final bool serviceAvailable;
  final bool registeredModelAvailable;
  final bool liveSensorEnabled;
  final bool rawSignalPersistence;
  final List<String> supportedModes;
  final ModelStatusInfo modelStatus;
  final List<String> limitations;
  final List<CognitiveStateError> errors;
  final String disclaimer;

  const CognitiveStateServiceStatus({
    required this.apiVersion,
    required this.schemaVersion,
    required this.serviceAvailable,
    required this.registeredModelAvailable,
    required this.liveSensorEnabled,
    required this.rawSignalPersistence,
    required this.supportedModes,
    required this.modelStatus,
    required this.limitations,
    this.errors = const <CognitiveStateError>[],
    this.disclaimer = kCsmResearchDisclaimer,
  });

  factory CognitiveStateServiceStatus.fromJson(Map<String, dynamic> json) {
    final rawModes = json['supported_modes'];
    final modes = rawModes is List
        ? rawModes.map((e) => e.toString()).toList()
        : const <String>['synthetic_demo', 'research_replay'];

    final rawLimits = json['limitations'];
    final limits = rawLimits is List
        ? rawLimits.map((e) => e.toString()).toList()
        : kCsmDefaultLimitations;

    final rawErrors = json['errors'];
    final errors = <CognitiveStateError>[];
    if (rawErrors is List) {
      for (final item in rawErrors) {
        if (item is Map) {
          errors.add(
            CognitiveStateError.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final rawModel = json['model_status'];

    return CognitiveStateServiceStatus(
      apiVersion: (json['api_version'] ?? 'v1').toString(),
      schemaVersion: (json['schema_version'] ?? 'unknown').toString(),
      serviceAvailable: json['service_available'] == true,
      registeredModelAvailable: json['registered_model_available'] == true,
      liveSensorEnabled: json['live_sensor_enabled'] == true,
      rawSignalPersistence: json['raw_signal_persistence'] == true,
      supportedModes: modes,
      modelStatus: ModelStatusInfo.fromJson(
        rawModel is Map ? Map<String, dynamic>.from(rawModel) : null,
      ),
      limitations: limits,
      errors: errors,
      disclaimer: (json['disclaimer'] ?? kCsmResearchDisclaimer).toString(),
    );
  }
}

class CognitiveStateUiSnapshot {
  final CognitiveStateUiStatus uiStatus;
  final CognitiveStateAnalysisResponse? analysis;
  final CognitiveStateServiceStatus? serviceStatus;
  final String? message;
  final String? errorCode;

  const CognitiveStateUiSnapshot({
    required this.uiStatus,
    this.analysis,
    this.serviceStatus,
    this.message,
    this.errorCode,
  });
}
