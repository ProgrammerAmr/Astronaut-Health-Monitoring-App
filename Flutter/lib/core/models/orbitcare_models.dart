import 'dart:convert';

class OrbitCareApiException implements Exception {
  final int? statusCode;
  final String message;
  final String code;

  const OrbitCareApiException({
    this.statusCode,
    required this.message,
    this.code = 'API_ERROR',
  });

  bool get isUnauthorized => statusCode == 401;
  bool get isUnverified => statusCode == 403 && code == 'EMAIL_UNVERIFIED';
  bool get isNetworkError => code == 'NETWORK_ERROR' || code == 'TIMEOUT';
  bool get isConfigError => code == 'API_BASE_URL_UNCONFIGURED';

  @override
  String toString() => 'OrbitCareApiException($code, $statusCode): $message';
}

enum ConnectionCheckStatus {
  missingConfig,
  invalidUrl,
  connected,
  timeout,
  unreachable,
  serverError,
}

class ConnectionCheckResult {
  final ConnectionCheckStatus status;
  final String? normalizedUrl;
  final String message;
  final int? statusCode;
  final int? latencyMs;
  final String? databaseStatus;
  final bool? emailConfigured;

  const ConnectionCheckResult({
    required this.status,
    required this.message,
    this.normalizedUrl,
    this.statusCode,
    this.latencyMs,
    this.databaseStatus,
    this.emailConfigured,
  });

  bool get isSuccess => status == ConnectionCheckStatus.connected;
}

class OtpRouteArgs {
  final String email;
  final String purpose; // 'signup' or 'reset_password'

  const OtpRouteArgs({
    required this.email,
    required this.purpose,
  });

  bool get isSignup => purpose == 'signup';
}

class ResetPasswordRouteArgs {
  final String email;
  final String otp;

  const ResetPasswordRouteArgs({
    required this.email,
    required this.otp,
  });
}

class AuthUser {
  final String id;
  final String name;
  final String email;
  final String role;
  final String? missionName;
  final String? missionRole;
  final String? missionStatus;

  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.role = 'astronaut',
    this.missionName,
    this.missionRole,
    this.missionStatus,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final mission = json['mission'] is Map
        ? Map<String, dynamic>.from(json['mission'] as Map)
        : null;
    return AuthUser(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? 'Astronaut').toString(),
      email: (json['email'] ?? '').toString(),
      role: (json['role'] ?? 'astronaut').toString(),
      missionName: mission?['name']?.toString(),
      missionRole: mission?['role']?.toString(),
      missionStatus: mission?['status']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'email': email,
      'role': role,
      if (missionName != null || missionRole != null || missionStatus != null)
        'mission': <String, dynamic>{
          if (missionName != null) 'name': missionName,
          if (missionRole != null) 'role': missionRole,
          if (missionStatus != null) 'status': missionStatus,
        },
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static AuthUser? tryParseJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return AuthUser.fromJson(Map<String, dynamic>.from(decoded));
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

class AuthSession {
  final String token;
  final AuthUser user;

  const AuthSession({
    required this.token,
    required this.user,
  });

  AuthSession copyWith({String? token, AuthUser? user}) {
    return AuthSession(
      token: token ?? this.token,
      user: user ?? this.user,
    );
  }
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _toDateTime(dynamic value) {
  if (value is DateTime) return value;
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value.trim());
  }
  return null;
}

class BloodPressure {
  final double? systolic;
  final double? diastolic;

  const BloodPressure({this.systolic, this.diastolic});

  factory BloodPressure.fromJson(Map<String, dynamic> json) {
    return BloodPressure(
      systolic: _toDouble(json['systolic']),
      diastolic: _toDouble(json['diastolic']),
    );
  }

  bool get hasValues => systolic != null || diastolic != null;

  String get formatted {
    final sys = systolic != null ? systolic!.round().toString() : '--';
    final dia = diastolic != null ? diastolic!.round().toString() : '--';
    return '$sys/$dia mmHg';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (systolic != null) 'systolic': systolic,
      if (diastolic != null) 'diastolic': diastolic,
    };
  }
}

class SleepInfo {
  final int? durationMinutes;
  final String? quality;

  const SleepInfo({this.durationMinutes, this.quality});

  factory SleepInfo.fromJson(Map<String, dynamic> json) {
    return SleepInfo(
      durationMinutes: _toInt(json['durationMinutes']),
      quality: json['quality']?.toString(),
    );
  }

  bool get hasValues =>
      durationMinutes != null || (quality != null && quality!.isNotEmpty);

  String get formattedDuration {
    if (durationMinutes == null) return '--';
    final hours = durationMinutes! ~/ 60;
    final mins = durationMinutes! % 60;
    return '${hours}h ${mins}m';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (durationMinutes != null) 'durationMinutes': durationMinutes,
      if (quality != null) 'quality': quality,
    };
  }
}

class ActivityInfo {
  final int? steps;
  final double? calories;
  final int? durationMinutes;
  final String? level;

  const ActivityInfo({
    this.steps,
    this.calories,
    this.durationMinutes,
    this.level,
  });

  factory ActivityInfo.fromJson(Map<String, dynamic> json) {
    return ActivityInfo(
      steps: _toInt(json['steps']),
      calories: _toDouble(json['calories']),
      durationMinutes: _toInt(json['durationMinutes']),
      level: json['level']?.toString(),
    );
  }

  bool get hasValues =>
      steps != null ||
      calories != null ||
      durationMinutes != null ||
      (level != null && level!.isNotEmpty);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (steps != null) 'steps': steps,
      if (calories != null) 'calories': calories,
      if (durationMinutes != null) 'durationMinutes': durationMinutes,
      if (level != null) 'level': level,
    };
  }
}

class HealthMeasurement {
  final String id;
  final double? heartRate;
  final double? pulseRate;
  final double? respiratoryRate;
  final double? spo2;
  final double? temperature;
  final BloodPressure? bloodPressure;
  final double? bloodSugar;
  final SleepInfo? sleep;
  final ActivityInfo? activity;
  final DateTime? measuredAt;
  final String source;

  const HealthMeasurement({
    required this.id,
    this.heartRate,
    this.pulseRate,
    this.respiratoryRate,
    this.spo2,
    this.temperature,
    this.bloodPressure,
    this.bloodSugar,
    this.sleep,
    this.activity,
    this.measuredAt,
    this.source = 'manual',
  });

  factory HealthMeasurement.fromJson(Map<String, dynamic> json) {
    final bpMap = json['bloodPressure'] is Map
        ? Map<String, dynamic>.from(json['bloodPressure'] as Map)
        : null;
    final sleepMap = json['sleep'] is Map
        ? Map<String, dynamic>.from(json['sleep'] as Map)
        : null;
    final actMap = json['activity'] is Map
        ? Map<String, dynamic>.from(json['activity'] as Map)
        : null;

    return HealthMeasurement(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      heartRate: _toDouble(json['heartRate']),
      pulseRate: _toDouble(json['pulseRate']),
      respiratoryRate: _toDouble(json['respiratoryRate']),
      spo2: _toDouble(json['spo2']),
      temperature: _toDouble(json['temperature']),
      bloodPressure: bpMap != null ? BloodPressure.fromJson(bpMap) : null,
      bloodSugar: _toDouble(json['bloodSugar']),
      sleep: sleepMap != null ? SleepInfo.fromJson(sleepMap) : null,
      activity: actMap != null ? ActivityInfo.fromJson(actMap) : null,
      measuredAt: _toDateTime(json['measuredAt'] ?? json['createdAt']),
      source: (json['source'] ?? 'manual').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      '_id': id,
      if (heartRate != null) 'heartRate': heartRate,
      if (pulseRate != null) 'pulseRate': pulseRate,
      if (respiratoryRate != null) 'respiratoryRate': respiratoryRate,
      if (spo2 != null) 'spo2': spo2,
      if (temperature != null) 'temperature': temperature,
      if (bloodPressure?.hasValues == true)
        'bloodPressure': bloodPressure!.toJson(),
      if (bloodSugar != null) 'bloodSugar': bloodSugar,
      if (sleep?.hasValues == true) 'sleep': sleep!.toJson(),
      if (activity?.hasValues == true) 'activity': activity!.toJson(),
      if (measuredAt != null) 'measuredAt': measuredAt!.toUtc().toIso8601String(),
      'source': source,
    };
  }
}

class DashboardAverages {
  final double? heartRate;
  final double? spo2;
  final double? respiratoryRate;
  final double? temperature;

  const DashboardAverages({
    this.heartRate,
    this.spo2,
    this.respiratoryRate,
    this.temperature,
  });

  factory DashboardAverages.fromJson(Map<String, dynamic> json) {
    return DashboardAverages(
      heartRate: _toDouble(json['averageHeartRate'] ?? json['heartRate']),
      spo2: _toDouble(json['averageSpo2'] ?? json['spo2']),
      respiratoryRate: _toDouble(
        json['averageRespiratoryRate'] ?? json['respiratoryRate'],
      ),
      temperature: _toDouble(json['averageTemperature'] ?? json['temperature']),
    );
  }
}

class DashboardSummary {
  final int totalMeasurements;
  final int unreadAlerts;
  final HealthMeasurement? latestMeasurement;
  final DashboardAverages? averages;

  const DashboardSummary({
    required this.totalMeasurements,
    required this.unreadAlerts,
    this.latestMeasurement,
    this.averages,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final latestMap = json['latestMeasurement'] is Map
        ? Map<String, dynamic>.from(json['latestMeasurement'] as Map)
        : null;
    final avgMap = json['averages'] is Map
        ? Map<String, dynamic>.from(json['averages'] as Map)
        : null;

    return DashboardSummary(
      totalMeasurements: _toInt(json['totalMeasurements']) ?? 0,
      unreadAlerts: _toInt(json['unreadAlerts']) ?? 0,
      latestMeasurement:
          latestMap != null ? HealthMeasurement.fromJson(latestMap) : null,
      averages: avgMap != null ? DashboardAverages.fromJson(avgMap) : null,
    );
  }
}

class HealthAlert {
  final String id;
  final String title;
  final String message;
  final String severity;
  final bool isRead;
  final DateTime? createdAt;

  const HealthAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.isRead,
    this.createdAt,
  });

  factory HealthAlert.fromJson(Map<String, dynamic> json) {
    return HealthAlert(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Health Alert').toString(),
      message: (json['message'] ?? '').toString(),
      severity: (json['severity'] ?? 'medium').toString(),
      isRead: json['isRead'] == true,
      createdAt: _toDateTime(json['createdAt']),
    );
  }

  HealthAlert copyWith({bool? isRead}) {
    return HealthAlert(
      id: id,
      title: title,
      message: message,
      severity: severity,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      '_id': id,
      'title': title,
      'message': message,
      'severity': severity,
      'isRead': isRead,
      if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
    };
  }
}

class HealthReport {
  final String period;
  final DateTime? startDate;
  final DateTime? endDate;
  final int records;
  final double? averageHeartRate;
  final double? averageSpo2;
  final double? averageRespiratoryRate;
  final double? averageTemperature;
  final int totalSteps;
  final double totalCalories;
  final int totalSleepMinutes;

  const HealthReport({
    required this.period,
    this.startDate,
    this.endDate,
    required this.records,
    this.averageHeartRate,
    this.averageSpo2,
    this.averageRespiratoryRate,
    this.averageTemperature,
    required this.totalSteps,
    required this.totalCalories,
    required this.totalSleepMinutes,
  });

  factory HealthReport.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] is Map
        ? Map<String, dynamic>.from(json['summary'] as Map)
        : <String, dynamic>{};

    return HealthReport(
      period: (json['period'] ?? 'weekly').toString(),
      startDate: _toDateTime(json['startDate']),
      endDate: _toDateTime(json['endDate']),
      records: _toInt(summary['records']) ?? 0,
      averageHeartRate: _toDouble(summary['averageHeartRate']),
      averageSpo2: _toDouble(summary['averageSpo2']),
      averageRespiratoryRate: _toDouble(summary['averageRespiratoryRate']),
      averageTemperature: _toDouble(summary['averageTemperature']),
      totalSteps: _toInt(summary['totalSteps']) ?? 0,
      totalCalories: _toDouble(summary['totalCalories']) ?? 0,
      totalSleepMinutes: _toInt(summary['totalSleepMinutes']) ?? 0,
    );
  }
}

/// Formats UTC/local timestamps cleanly without requiring extra intl dependency.
String formatOrbitTimestamp(DateTime? dt) {
  if (dt == null) return 'Timestamp unavailable';
  final local = dt.toLocal();
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months[local.month - 1];
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month $day, ${local.year} • $hour:$minute';
}

/// Formats body temperature in °C or °F according to user display preference.
String formatOrbitTemperature(double? celsius, {bool useFahrenheit = false}) {
  if (celsius == null) return '--';
  if (useFahrenheit) {
    final fahrenheit = (celsius * 9 / 5) + 32;
    return '${fahrenheit.toStringAsFixed(1)} °F';
  }
  return '${celsius.toStringAsFixed(1)} °C';
}

/// Local display and Demo Mode preferences stored separately from production
/// auth credentials.
class DemoPreferences {
  final bool useFahrenheit;
  final bool autoThresholdAlerts;

  const DemoPreferences({
    this.useFahrenheit = false,
    this.autoThresholdAlerts = true,
  });

  DemoPreferences copyWith({
    bool? useFahrenheit,
    bool? autoThresholdAlerts,
  }) {
    return DemoPreferences(
      useFahrenheit: useFahrenheit ?? this.useFahrenheit,
      autoThresholdAlerts: autoThresholdAlerts ?? this.autoThresholdAlerts,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'useFahrenheit': useFahrenheit,
      'autoThresholdAlerts': autoThresholdAlerts,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static DemoPreferences tryParseJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const DemoPreferences();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        return DemoPreferences(
          useFahrenheit: map['useFahrenheit'] == true,
          autoThresholdAlerts: map['autoThresholdAlerts'] != false,
        );
      }
    } catch (_) {
      // Fall back to defaults cleanly if corrupted.
    }
    return const DemoPreferences();
  }
}

