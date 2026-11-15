import 'dart:convert';

import '../models/orbitcare_models.dart';
import '../storage/session_storage.dart';

/// Offline synthetic astronaut health repository for OrbitCare Demo Mode.
///
/// Strictly separated from production backend data:
/// - Persists only under dedicated `orbitcare_demo_*` storage keys.
/// - Never contacts external APIs, MongoDB, or SMTP.
/// - All seeded records and alerts are explicitly identified as synthetic demo data.
class DemoHealthRepository {
  static const String demoSessionToken = 'orbitcare-local-demo-session';

  static const AuthUser demoUser = AuthUser(
    id: 'demo-astronaut-001',
    name: 'Commander Alex Vance (Demo)',
    email: 'demo.astronaut@orbitcare.local',
    role: 'astronaut',
    missionName: 'Orbital Demo Mission (Synthetic)',
    missionRole: 'Flight Engineer (Demo)',
    missionStatus: 'Offline Demo Simulation Active',
  );

  final SessionStorage _storage;
  final DateTime Function() _nowProvider;

  bool _loaded = false;
  List<HealthMeasurement> _measurements = <HealthMeasurement>[];
  List<HealthAlert> _alerts = <HealthAlert>[];
  DemoPreferences _preferences = const DemoPreferences();

  DemoHealthRepository({
    required SessionStorage storage,
    DateTime Function()? nowProvider,
  })  : _storage = storage,
        _nowProvider = nowProvider ?? DateTime.now;

  DemoPreferences get preferences => _preferences;

  Future<void> ensureLoaded() async {
    if (_loaded) return;

    final rawPrefs = await _storage.readDemoPrefsJson();
    _preferences = DemoPreferences.tryParseJsonString(rawPrefs);

    final rawState = await _storage.readDemoStateJson();
    if (rawState != null && rawState.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawState);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          final rawMeasurements = map['measurements'];
          final rawAlerts = map['alerts'];
          if (rawMeasurements is List && rawAlerts is List) {
            _measurements = rawMeasurements
                .whereType<Map>()
                .map((item) => HealthMeasurement.fromJson(
                      Map<String, dynamic>.from(item),
                    ))
                .toList();
            _alerts = rawAlerts
                .whereType<Map>()
                .map((item) => HealthAlert.fromJson(
                      Map<String, dynamic>.from(item),
                    ))
                .toList();
            _loaded = true;
            return;
          }
        }
      } catch (_) {
        // Re-seed cleanly if persisted demo snapshot is unreadable.
      }
    }

    _seedBaseline();
    _loaded = true;
    await _persistState();
  }

  Future<void> resetToDefaults() async {
    _seedBaseline();
    _loaded = true;
    await _persistState();
  }

  Future<void> updatePreferences(DemoPreferences next) async {
    _preferences = next;
    await _storage.writeDemoPrefsJson(next.toJsonString());
  }

  Future<void> _persistState() async {
    final encoded = jsonEncode(<String, dynamic>{
      'measurements': _measurements.map((m) => m.toJson()).toList(),
      'alerts': _alerts.map((a) => a.toJson()).toList(),
    });
    await _storage.writeDemoStateJson(encoded);
  }

  void _seedBaseline() {
    final now = _nowProvider().toUtc();

    // 10 internally consistent synthetic measurements spanning 14 days:
    // - Last 24h (Daily): 3 records
    // - Last 7d (Weekly): 7 records
    // - Last 30d (Monthly): 10 records
    _measurements = <HealthMeasurement>[
      HealthMeasurement(
        id: 'demo-m-10',
        heartRate: 72,
        pulseRate: 72,
        respiratoryRate: 15,
        spo2: 99,
        temperature: 36.7,
        bloodPressure: const BloodPressure(systolic: 118, diastolic: 76),
        bloodSugar: 94,
        sleep: const SleepInfo(durationMinutes: 445, quality: 'good'),
        activity: const ActivityInfo(
          steps: 7150,
          calories: 2240,
          durationMinutes: 68,
          level: 'moderate',
        ),
        measuredAt: now.subtract(const Duration(hours: 2)),
        source: 'demo_synthetic',
      ),
      HealthMeasurement(
        id: 'demo-m-09',
        heartRate: 114,
        pulseRate: 114,
        respiratoryRate: 22,
        spo2: 95,
        temperature: 37.3,
        bloodPressure: const BloodPressure(systolic: 134, diastolic: 85),
        bloodSugar: 108,
        sleep: const SleepInfo(durationMinutes: 370, quality: 'fair'),
        activity: const ActivityInfo(
          steps: 9400,
          calories: 2790,
          durationMinutes: 105,
          level: 'intense',
        ),
        measuredAt: now.subtract(const Duration(hours: 8)),
        source: 'demo_synthetic',
      ),
      HealthMeasurement(
        id: 'demo-m-08',
        heartRate: 67,
        pulseRate: 67,
        respiratoryRate: 14,
        spo2: 99,
        temperature: 36.6,
        bloodPressure: const BloodPressure(systolic: 116, diastolic: 74),
        bloodSugar: 91,
        sleep: const SleepInfo(durationMinutes: 460, quality: 'excellent'),
        activity: const ActivityInfo(
          steps: 5600,
          calories: 1980,
          durationMinutes: 50,
          level: 'light',
        ),
        measuredAt: now.subtract(const Duration(hours: 19)),
        source: 'demo_synthetic',
      ),
      HealthMeasurement(
        id: 'demo-m-07',
        heartRate: 76,
        pulseRate: 76,
        respiratoryRate: 16,
        spo2: 98,
        temperature: 36.9,
        bloodPressure: const BloodPressure(systolic: 122, diastolic: 79),
        bloodSugar: 99,
        sleep: const SleepInfo(durationMinutes: 395, quality: 'fair'),
        activity: const ActivityInfo(
          steps: 8250,
          calories: 2490,
          durationMinutes: 82,
          level: 'high',
        ),
        measuredAt: now.subtract(const Duration(days: 2, hours: 3)),
        source: 'demo_synthetic',
      ),
      HealthMeasurement(
        id: 'demo-m-06',
        heartRate: 70,
        pulseRate: 70,
        respiratoryRate: 15,
        spo2: 98,
        temperature: 36.8,
        bloodPressure: const BloodPressure(systolic: 119, diastolic: 77),
        bloodSugar: 95,
        sleep: const SleepInfo(durationMinutes: 430, quality: 'good'),
        activity: const ActivityInfo(
          steps: 6800,
          calories: 2180,
          durationMinutes: 65,
          level: 'moderate',
        ),
        measuredAt: now.subtract(const Duration(days: 3, hours: 5)),
        source: 'demo_synthetic',
      ),
      HealthMeasurement(
        id: 'demo-m-05',
        heartRate: 84,
        pulseRate: 84,
        respiratoryRate: 17,
        spo2: 96,
        temperature: 37.1,
        bloodPressure: const BloodPressure(systolic: 126, diastolic: 81),
        bloodSugar: 103,
        sleep: const SleepInfo(durationMinutes: 360, quality: 'fair'),
        activity: const ActivityInfo(
          steps: 8900,
          calories: 2610,
          durationMinutes: 92,
          level: 'high',
        ),
        measuredAt: now.subtract(const Duration(days: 4, hours: 6)),
        source: 'demo_synthetic',
      ),
      HealthMeasurement(
        id: 'demo-m-04',
        heartRate: 69,
        pulseRate: 69,
        respiratoryRate: 14,
        spo2: 99,
        temperature: 36.7,
        bloodPressure: const BloodPressure(systolic: 117, diastolic: 75),
        bloodSugar: 92,
        sleep: const SleepInfo(durationMinutes: 455, quality: 'excellent'),
        activity: const ActivityInfo(
          steps: 6150,
          calories: 2090,
          durationMinutes: 60,
          level: 'moderate',
        ),
        measuredAt: now.subtract(const Duration(days: 6, hours: 2)),
        source: 'demo_synthetic',
      ),
      HealthMeasurement(
        id: 'demo-m-03',
        heartRate: 74,
        pulseRate: 74,
        respiratoryRate: 15,
        spo2: 98,
        temperature: 36.8,
        bloodPressure: const BloodPressure(systolic: 121, diastolic: 78),
        bloodSugar: 97,
        sleep: const SleepInfo(durationMinutes: 420, quality: 'good'),
        activity: const ActivityInfo(
          steps: 7050,
          calories: 2260,
          durationMinutes: 70,
          level: 'moderate',
        ),
        measuredAt: now.subtract(const Duration(days: 9, hours: 4)),
        source: 'demo_synthetic',
      ),
      HealthMeasurement(
        id: 'demo-m-02',
        heartRate: 78,
        pulseRate: 78,
        respiratoryRate: 16,
        spo2: 97,
        temperature: 36.9,
        bloodPressure: const BloodPressure(systolic: 124, diastolic: 80),
        bloodSugar: 100,
        sleep: const SleepInfo(durationMinutes: 405, quality: 'fair'),
        activity: const ActivityInfo(
          steps: 7800,
          calories: 2390,
          durationMinutes: 78,
          level: 'high',
        ),
        measuredAt: now.subtract(const Duration(days: 11, hours: 6)),
        source: 'demo_synthetic',
      ),
      HealthMeasurement(
        id: 'demo-m-01',
        heartRate: 68,
        pulseRate: 68,
        respiratoryRate: 14,
        spo2: 99,
        temperature: 36.7,
        bloodPressure: const BloodPressure(systolic: 118, diastolic: 76),
        bloodSugar: 93,
        sleep: const SleepInfo(durationMinutes: 450, quality: 'good'),
        activity: const ActivityInfo(
          steps: 6450,
          calories: 2140,
          durationMinutes: 64,
          level: 'moderate',
        ),
        measuredAt: now.subtract(const Duration(days: 13, hours: 3)),
        source: 'demo_synthetic',
      ),
    ];

    // Representative synthetic operational alerts (critical, high, medium, low).
    // Strictly non-diagnostic and never generated from DEC-001 CSM outputs.
    _alerts = <HealthAlert>[
      HealthAlert(
        id: 'demo-a-01',
        title: '[DEMO] Elevated Post-EVA Heart Rate (114 bpm)',
        message:
            'Synthetic demo alert: Simulated intense EVA workout recorded Heart Rate at 114 bpm and BP 134/85 mmHg. Recovery reading 6 hours later returned to nominal 72 bpm. Non-diagnostic demonstration sample.',
        severity: 'critical',
        isRead: false,
        createdAt: now.subtract(const Duration(hours: 8)),
      ),
      HealthAlert(
        id: 'demo-a-02',
        title: '[DEMO] Mild SpO2 Dip During Simulated Exercise (95%)',
        message:
            'Synthetic demo alert: Oxygen saturation temporarily dipped to 95% during peak simulated treadmill load before recovering to 99%. Review breathing cadence checklist.',
        severity: 'high',
        isRead: false,
        createdAt: now.subtract(const Duration(hours: 7, minutes: 45)),
      ),
      HealthAlert(
        id: 'demo-a-03',
        title: '[DEMO] Sleep Duration Below 7h Target',
        message:
            'Synthetic demo alert: Logged sleep duration was 6h 10m following the simulated high-activity cycle. Recommended demo action: schedule recovery rest window and log hydration.',
        severity: 'medium',
        isRead: false,
        createdAt: now.subtract(const Duration(days: 1, hours: 1)),
      ),
      HealthAlert(
        id: 'demo-a-04',
        title: '[DEMO] Hydration & Electrolyte Reminder',
        message:
            'Synthetic demo operational reminder: Maintain scheduled fluid intake during high-exertion orbital training blocks.',
        severity: 'medium',
        isRead: true,
        createdAt: now.subtract(const Duration(days: 2, hours: 4)),
      ),
      HealthAlert(
        id: 'demo-a-05',
        title: '[DEMO] Routine Baseline Vitals Nominal',
        message:
            'Synthetic demo confirmation: Resting vitals (HR 69 bpm, SpO2 99%, Temp 36.7 °C) remained within baseline simulation bounds.',
        severity: 'low',
        isRead: true,
        createdAt: now.subtract(const Duration(days: 4, hours: 2)),
      ),
    ];
  }

  Future<DashboardSummary> getDashboard() async {
    await ensureLoaded();
    final unread = _alerts.where((a) => !a.isRead).length;
    final latest = _measurements.isNotEmpty ? _measurements.first : null;
    final averages = _computeAverages(_measurements);

    return DashboardSummary(
      totalMeasurements: _measurements.length,
      unreadAlerts: unread,
      latestMeasurement: latest,
      averages: averages,
    );
  }

  Future<List<HealthMeasurement>> getMeasurements({int limit = 30}) async {
    await ensureLoaded();
    return List<HealthMeasurement>.unmodifiable(_measurements.take(limit));
  }

  Future<HealthMeasurement> createMeasurement(
    Map<String, dynamic> payload,
  ) async {
    await ensureLoaded();
    final now = _nowProvider().toUtc();
    final id = 'demo-m-local-${now.microsecondsSinceEpoch}';

    final normalizedPayload = <String, dynamic>{
      ...payload,
      '_id': id,
      'measuredAt': now.toIso8601String(),
      'source': 'demo_local',
    };
    final created = HealthMeasurement.fromJson(normalizedPayload);
    _measurements.insert(0, created);

    // Optional local non-diagnostic threshold reminder for live demo interactivity
    if (_preferences.autoThresholdAlerts) {
      _maybeCreateLocalDemoAlert(created, now);
    }

    await _persistState();
    return created;
  }

  void _maybeCreateLocalDemoAlert(HealthMeasurement m, DateTime now) {
    if (m.spo2 != null && m.spo2! < 94) {
      _alerts.insert(
        0,
        HealthAlert(
          id: 'demo-a-local-spo2-${now.microsecondsSinceEpoch}',
          title: '[DEMO] Low Simulated SpO2 Logged (${m.spo2!.toStringAsFixed(0)}%)',
          message:
              'Local demo threshold triggered: You logged SpO2 at ${m.spo2!.toStringAsFixed(0)}% (< 94% demo threshold). Stored locally only — not a medical alert.',
          severity: 'critical',
          isRead: false,
          createdAt: now,
        ),
      );
      return;
    }

    if (m.heartRate != null && (m.heartRate! > 110 || m.heartRate! < 48)) {
      _alerts.insert(
        0,
        HealthAlert(
          id: 'demo-a-local-hr-${now.microsecondsSinceEpoch}',
          title:
              '[DEMO] Out-of-Range Heart Rate Logged (${m.heartRate!.round()} bpm)',
          message:
              'Local demo threshold triggered: Heart rate ${m.heartRate!.round()} bpm is outside the 48–110 bpm demo resting band. Stored locally only.',
          severity: m.heartRate! > 130 ? 'critical' : 'high',
          isRead: false,
          createdAt: now,
        ),
      );
      return;
    }

    if (m.temperature != null && m.temperature! >= 38.0) {
      _alerts.insert(
        0,
        HealthAlert(
          id: 'demo-a-local-temp-${now.microsecondsSinceEpoch}',
          title:
              '[DEMO] Elevated Body Temperature Logged (${m.temperature!.toStringAsFixed(1)} °C)',
          message:
              'Local demo threshold triggered: Temperature ${m.temperature!.toStringAsFixed(1)} °C exceeds 38.0 °C demo threshold. Stored locally only.',
          severity: 'medium',
          isRead: false,
          createdAt: now,
        ),
      );
    }
  }

  Future<List<HealthAlert>> getAlerts({bool? isRead}) async {
    await ensureLoaded();
    if (isRead == null) {
      return List<HealthAlert>.unmodifiable(_alerts);
    }
    return List<HealthAlert>.unmodifiable(
      _alerts.where((a) => a.isRead == isRead),
    );
  }

  Future<HealthAlert> markAlertRead(String alertId) async {
    await ensureLoaded();
    final idx = _alerts.indexWhere((a) => a.id == alertId);
    if (idx == -1) {
      throw const OrbitCareApiException(
        statusCode: 404,
        code: 'DEMO_ALERT_NOT_FOUND',
        message: 'Demo alert not found.',
      );
    }
    final updated = _alerts[idx].copyWith(isRead: true);
    _alerts[idx] = updated;
    await _persistState();
    return updated;
  }

  Future<HealthReport> getReport(String period) async {
    await ensureLoaded();
    final now = _nowProvider().toUtc();
    final Duration window;
    switch (period.toLowerCase()) {
      case 'daily':
        window = const Duration(days: 1);
      case 'monthly':
        window = const Duration(days: 30);
      case 'weekly':
      default:
        window = const Duration(days: 7);
    }

    final startDate = now.subtract(window);
    final inWindow = _measurements.where((m) {
      final ts = m.measuredAt;
      if (ts == null) return false;
      return !ts.isBefore(startDate);
    }).toList();

    final averages = _computeAverages(inWindow);
    int totalSteps = 0;
    double totalCalories = 0;
    int totalSleepMinutes = 0;

    for (final m in inWindow) {
      totalSteps += m.activity?.steps ?? 0;
      totalCalories += m.activity?.calories ?? 0;
      totalSleepMinutes += m.sleep?.durationMinutes ?? 0;
    }

    return HealthReport(
      period: period,
      startDate: startDate,
      endDate: now,
      records: inWindow.length,
      averageHeartRate: averages.heartRate,
      averageSpo2: averages.spo2,
      averageRespiratoryRate: averages.respiratoryRate,
      averageTemperature: averages.temperature,
      totalSteps: totalSteps,
      totalCalories: totalCalories,
      totalSleepMinutes: totalSleepMinutes,
    );
  }

  DashboardAverages _computeAverages(List<HealthMeasurement> items) {
    double? avg(Iterable<double?> values) {
      final nums = values.whereType<double>().toList();
      if (nums.isEmpty) return null;
      final sum = nums.fold<double>(0, (a, b) => a + b);
      return sum / nums.length;
    }

    return DashboardAverages(
      heartRate: avg(items.map((m) => m.heartRate)),
      spo2: avg(items.map((m) => m.spo2)),
      respiratoryRate: avg(items.map((m) => m.respiratoryRate)),
      temperature: avg(items.map((m) => m.temperature)),
    );
  }
}
