import 'package:flutter/material.dart';

import '../cognitive_state/models/cognitive_state_models.dart';
import '../cognitive_state/services/cognitive_state_api_client.dart';
import '../cognitive_state/widgets/cognitive_state_research_card.dart';
import '../constants/app_colors.dart';
import '../core/models/orbitcare_models.dart';
import '../core/services/orbitcare_api_client.dart';
import '../core/state/session_controller.dart';
import '../routes/app_routes.dart';
import 'add_measurement_screen.dart';

class HomeScreen extends StatefulWidget {
  final OrbitCareApiClient? apiClient;
  final CognitiveStateApiClient? csmApiClient;
  final String? authToken;
  final CognitiveStateUiSnapshot? initialCsmSnapshot;
  final bool autoFetchCsmStatus;
  final bool? autoFetchHealthData;

  const HomeScreen({
    super.key,
    this.apiClient,
    this.csmApiClient,
    this.authToken,
    this.initialCsmSnapshot,
    this.autoFetchCsmStatus = true,
    this.autoFetchHealthData,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  bool _initialized = false;

  // Dashboard state
  bool _loadingDashboard = false;
  DashboardSummary? _dashboard;
  String? _dashboardError;

  // Measurements state
  bool _loadingMeasurements = false;
  List<HealthMeasurement> _measurements = const <HealthMeasurement>[];
  String? _measurementsError;

  // Alerts state
  bool _loadingAlerts = false;
  bool _unreadOnly = false;
  List<HealthAlert> _alerts = const <HealthAlert>[];
  String? _alertsError;
  final Set<String> _markingAlertIds = <String>{};

  // Reports state
  bool _loadingReport = false;
  String _reportPeriod = 'weekly';
  HealthReport? _report;
  String? _reportError;

  SessionController? get _sessionController => SessionScope.maybeOf(context);

  OrbitCareApiClient? get _apiClient =>
      widget.apiClient ?? _sessionController?.apiClient;

  CognitiveStateApiClient? get _csmClient =>
      widget.csmApiClient ?? _sessionController?.csmApiClient;

  String? get _authToken {
    final explicit = widget.authToken?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return _sessionController?.token;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final shouldFetch = widget.autoFetchHealthData ??
          (_authToken != null &&
              _authToken!.isNotEmpty &&
              _apiClient != null &&
              _apiClient!.isConfigured);
      if (shouldFetch) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadAllHealthData();
        });
      }
    }
  }

  Future<void> _handleUnauthorizedIfNeeded(OrbitCareApiException error) async {
    if (!error.isUnauthorized) return;
    final controller = _sessionController;
    if (controller != null) {
      await controller.handleUnauthorized();
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
  }

  Future<void> _loadAllHealthData() async {
    await Future.wait<void>([
      _loadDashboard(),
      _loadMeasurements(),
      _loadAlerts(),
      _loadReport(),
    ]);
  }

  Future<void> _loadDashboard() async {
    final client = _apiClient;
    final token = _authToken;
    if (client == null || token == null || token.isEmpty) return;

    setState(() {
      _loadingDashboard = true;
      _dashboardError = null;
    });

    try {
      final summary = await client.getDashboard(token: token);
      if (!mounted) return;
      setState(() {
        _dashboard = summary;
      });
    } on OrbitCareApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        await _handleUnauthorizedIfNeeded(e);
        return;
      }
      setState(() {
        _dashboardError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dashboardError = 'Unable to load dashboard summary.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingDashboard = false;
        });
      }
    }
  }

  Future<void> _loadMeasurements() async {
    final client = _apiClient;
    final token = _authToken;
    if (client == null || token == null || token.isEmpty) return;

    setState(() {
      _loadingMeasurements = true;
      _measurementsError = null;
    });

    try {
      final list = await client.getMeasurements(token: token, limit: 30);
      if (!mounted) return;
      setState(() {
        _measurements = list;
      });
    } on OrbitCareApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        await _handleUnauthorizedIfNeeded(e);
        return;
      }
      setState(() {
        _measurementsError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _measurementsError = 'Unable to load health measurements.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingMeasurements = false;
        });
      }
    }
  }

  Future<void> _loadAlerts() async {
    final client = _apiClient;
    final token = _authToken;
    if (client == null || token == null || token.isEmpty) return;

    setState(() {
      _loadingAlerts = true;
      _alertsError = null;
    });

    try {
      final list = await client.getAlerts(
        token: token,
        isRead: _unreadOnly ? false : null,
      );
      if (!mounted) return;
      setState(() {
        _alerts = list;
      });
    } on OrbitCareApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        await _handleUnauthorizedIfNeeded(e);
        return;
      }
      setState(() {
        _alertsError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _alertsError = 'Unable to load health alerts.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingAlerts = false;
        });
      }
    }
  }

  Future<void> _markAlertRead(HealthAlert alert) async {
    if (alert.isRead || _markingAlertIds.contains(alert.id)) return;
    final client = _apiClient;
    final token = _authToken;
    if (client == null || token == null || token.isEmpty) return;

    setState(() {
      _markingAlertIds.add(alert.id);
    });

    try {
      await client.markAlertRead(token: token, alertId: alert.id);
      if (!mounted) return;
      setState(() {
        if (_unreadOnly) {
          _alerts = _alerts.where((item) => item.id != alert.id).toList();
        } else {
          _alerts = _alerts
              .map((item) =>
                  item.id == alert.id ? item.copyWith(isRead: true) : item)
              .toList();
        }
        if (_dashboard != null && _dashboard!.unreadAlerts > 0) {
          _dashboard = DashboardSummary(
            totalMeasurements: _dashboard!.totalMeasurements,
            unreadAlerts: _dashboard!.unreadAlerts - 1,
            latestMeasurement: _dashboard!.latestMeasurement,
            averages: _dashboard!.averages,
          );
        }
      });
    } on OrbitCareApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        await _handleUnauthorizedIfNeeded(e);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _markingAlertIds.remove(alert.id);
        });
      }
    }
  }

  Future<void> _loadReport([String? periodOverride]) async {
    final client = _apiClient;
    final token = _authToken;
    if (client == null || token == null || token.isEmpty) return;

    final targetPeriod = periodOverride ?? _reportPeriod;
    setState(() {
      _reportPeriod = targetPeriod;
      _loadingReport = true;
      _reportError = null;
    });

    try {
      final report = await client.getReport(
        token: token,
        period: targetPeriod,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
      });
    } on OrbitCareApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        await _handleUnauthorizedIfNeeded(e);
        return;
      }
      setState(() {
        _reportError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reportError = 'Unable to load health report.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingReport = false;
        });
      }
    }
  }

  Future<void> _openAddMeasurement() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => AddMeasurementScreen(
          apiClient: _apiClient,
          authToken: _authToken,
        ),
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Measurement saved successfully.')),
      );
      await Future.wait<void>([
        _loadDashboard(),
        _loadMeasurements(),
        _loadReport(),
      ]);
    }
  }

  Future<void> _handleLogout() async {
    final controller = _sessionController;
    if (controller != null) {
      await controller.logout();
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final user = _sessionController?.user;
    final unreadCount = _dashboard?.unreadAlerts ??
        _alerts.where((alert) => !alert.isRead).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'OrbitCare',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_authToken != null && _authToken!.isNotEmpty)
            IconButton(
              tooltip: 'Refresh Data',
              onPressed: _loadAllHealthData,
              icon: const Icon(Icons.refresh, color: AppColors.navy),
            ),
          if (_sessionController != null)
            IconButton(
              key: const Key('logout_button'),
              tooltip: 'Sign Out',
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout, color: AppColors.navy),
            ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _buildOverviewTab(user),
            _buildVitalsTab(),
            _buildAlertsTab(),
            _buildReportsTab(),
          ],
        ),
      ),
      floatingActionButton: (_selectedIndex == 1 &&
              _authToken != null &&
              _authToken!.isNotEmpty)
          ? FloatingActionButton.extended(
              key: const Key('fab_add_measurement'),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              onPressed: _openAddMeasurement,
              icon: const Icon(Icons.add),
              label: const Text('Log Vitals'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.lightBackground,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: AppColors.primary),
            label: 'Overview',
          ),
          const NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart, color: AppColors.primary),
            label: 'Vitals',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: const Icon(Icons.notifications, color: AppColors.primary),
            ),
            label: 'Alerts',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart, color: AppColors.primary),
            label: 'Reports',
          ),
        ],
      ),
    );
  }

  // ==================== TAB 1: OVERVIEW + CSM ====================

  Widget _buildOverviewTab(AuthUser? user) {
    final isAuthenticated = _authToken != null && _authToken!.isNotEmpty;

    return RefreshIndicator(
      onRefresh: _loadAllHealthData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user != null
                            ? 'Hello, ${user.name}'
                            : 'Crew Research Dashboard',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.missionName ??
                            'Hackathon prototype • Non-clinical astronaut health monitoring workspace.',
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: AppColors.grey,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isAuthenticated)
                  ElevatedButton.icon(
                    key: const Key('overview_log_vitals_btn'),
                    onPressed: _openAddMeasurement,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Log Vitals'),
                  ),
              ],
            ),

            if (isAuthenticated) ...[
              const SizedBox(height: 18),
              _buildDashboardSummarySection(),
            ],

            const SizedBox(height: 18),

            // DEC-001 Cognitive State Monitoring Research Card (authenticated)
            CognitiveStateResearchCard(
              apiClient: _csmClient,
              authToken: _authToken,
              initialSnapshot: widget.initialCsmSnapshot,
              autoFetchStatus: widget.autoFetchCsmStatus,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardSummarySection() {
    if (_loadingDashboard && _dashboard == null) {
      return const _SectionLoadingCard(label: 'Loading crew health overview...');
    }

    if (_dashboardError != null && _dashboard == null) {
      return _SectionErrorCard(
        message: _dashboardError!,
        onRetry: _loadDashboard,
      );
    }

    final summary = _dashboard;
    final latest = summary?.latestMeasurement;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _KpiStatCard(
                title: 'Measurements',
                value: '${summary?.totalMeasurements ?? 0}',
                icon: Icons.monitor_heart_outlined,
                accentColor: AppColors.primary,
                onTap: () => setState(() => _selectedIndex = 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _KpiStatCard(
                title: 'Unread Alerts',
                value: '${summary?.unreadAlerts ?? 0}',
                icon: Icons.notifications_active_outlined,
                accentColor: (summary?.unreadAlerts ?? 0) > 0
                    ? const Color(0xFFB42318)
                    : AppColors.teal,
                onTap: () => setState(() => _selectedIndex = 2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Latest Vitals Snapshot',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                  if (latest?.source == 'imported')
                    const _SmallTag(
                      label: 'Demo / Imported',
                      bgColor: Color(0xFFFFF3CD),
                      fgColor: Color(0xFF8A5300),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (latest == null)
                const Text(
                  'No vitals recorded yet. Tap "Log Vitals" to record your first measurement.',
                  style: TextStyle(fontSize: 13, color: AppColors.grey),
                )
              else ...[
                Text(
                  'Recorded: ${formatOrbitTimestamp(latest.measuredAt)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.grey),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (latest.heartRate != null)
                      _VitalPill(
                        label: 'Heart Rate',
                        value: '${latest.heartRate!.round()} bpm',
                      ),
                    if (latest.spo2 != null)
                      _VitalPill(
                        label: 'SpO2',
                        value: '${latest.spo2!.toStringAsFixed(0)}%',
                      ),
                    if (latest.respiratoryRate != null)
                      _VitalPill(
                        label: 'Resp. Rate',
                        value: '${latest.respiratoryRate!.round()} br/min',
                      ),
                    if (latest.temperature != null)
                      _VitalPill(
                        label: 'Temp',
                        value: '${latest.temperature!.toStringAsFixed(1)} °C',
                      ),
                    if (latest.bloodPressure?.hasValues == true)
                      _VitalPill(
                        label: 'Blood Pressure',
                        value: latest.bloodPressure!.formatted,
                      ),
                    if (latest.bloodSugar != null)
                      _VitalPill(
                        label: 'Blood Sugar',
                        value: '${latest.bloodSugar!.round()} mg/dL',
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ==================== TAB 2: VITALS HISTORY ====================

  Widget _buildVitalsTab() {
    if (_loadingMeasurements && _measurements.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: _SectionLoadingCard(label: 'Loading measurement history...'),
      );
    }

    if (_measurementsError != null && _measurements.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: _SectionErrorCard(
          message: _measurementsError!,
          onRetry: _loadMeasurements,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMeasurements,
      child: _measurements.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _SectionEmptyCard(
                  icon: Icons.monitor_heart_outlined,
                  title: 'No Measurements Yet',
                  description:
                      'Record heart rate, SpO2, respiratory rate, temperature, blood pressure, or sleep to start tracking trends.',
                  actionLabel: 'Log First Measurement',
                  onAction: _openAddMeasurement,
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
              itemCount: _measurements.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _MeasurementCard(measurement: _measurements[index]);
              },
            ),
    );
  }

  // ==================== TAB 3: ALERTS ====================

  Widget _buildAlertsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              FilterChip(
                label: const Text('All Alerts'),
                selected: !_unreadOnly,
                onSelected: (_) {
                  if (_unreadOnly) {
                    setState(() => _unreadOnly = false);
                    _loadAlerts();
                  }
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Unread Only'),
                selected: _unreadOnly,
                onSelected: (_) {
                  if (!_unreadOnly) {
                    setState(() => _unreadOnly = true);
                    _loadAlerts();
                  }
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingAlerts && _alerts.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: _SectionLoadingCard(label: 'Loading alerts...'),
                )
              : _alertsError != null && _alerts.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: _SectionErrorCard(
                        message: _alertsError!,
                        onRetry: _loadAlerts,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadAlerts,
                      child: _alerts.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.all(20),
                              children: [
                                _SectionEmptyCard(
                                  icon: Icons.notifications_none,
                                  title: _unreadOnly
                                      ? 'No Unread Alerts'
                                      : 'No Health Alerts',
                                  description: _unreadOnly
                                      ? 'All crew notifications have been acknowledged.'
                                      : 'No operational health alerts are currently recorded for your account.',
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                              itemCount: _alerts.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final alert = _alerts[index];
                                final isBusy =
                                    _markingAlertIds.contains(alert.id);
                                return _AlertCard(
                                  alert: alert,
                                  isBusy: isBusy,
                                  onMarkRead: () => _markAlertRead(alert),
                                );
                              },
                            ),
                    ),
        ),
      ],
    );
  }

  // ==================== TAB 4: REPORTS ====================

  Widget _buildReportsTab() {
    return RefreshIndicator(
      onRefresh: () => _loadReport(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Health Summary Reports',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: ['daily', 'weekly', 'monthly'].map((period) {
                final label =
                    '${period[0].toUpperCase()}${period.substring(1)}';
                return ChoiceChip(
                  label: Text(label),
                  selected: _reportPeriod == period,
                  onSelected: (_) {
                    if (_reportPeriod != period) {
                      _loadReport(period);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            if (_loadingReport && _report == null)
              const _SectionLoadingCard(label: 'Generating report summary...')
            else if (_reportError != null && _report == null)
              _SectionErrorCard(
                message: _reportError!,
                onRetry: () => _loadReport(),
              )
            else if (_report == null || _report!.records == 0)
              const _SectionEmptyCard(
                icon: Icons.bar_chart_outlined,
                title: 'No Data in Selected Period',
                description:
                    'No health measurements fall within this report window yet. Log measurements or choose a wider period.',
              )
            else
              _ReportSummaryCard(report: _report!),
          ],
        ),
      ),
    );
  }
}

class _KpiStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color accentColor;
  final VoidCallback? onTap;

  const _KpiStatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accentColor, size: 22),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VitalPill extends StatelessWidget {
  final String label;
  final String value;

  const _VitalPill({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.lightBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

class _MeasurementCard extends StatelessWidget {
  final HealthMeasurement measurement;

  const _MeasurementCard({required this.measurement});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  formatOrbitTimestamp(measurement.measuredAt),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
              ),
              _SmallTag(
                label: measurement.source == 'imported'
                    ? 'IMPORTED / DEMO'
                    : measurement.source.toUpperCase(),
                bgColor: measurement.source == 'imported'
                    ? const Color(0xFFFFF3CD)
                    : AppColors.lightBackground,
                fgColor: measurement.source == 'imported'
                    ? const Color(0xFF8A5300)
                    : AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (measurement.heartRate != null)
                _VitalPill(
                  label: 'Heart Rate',
                  value: '${measurement.heartRate!.round()} bpm',
                ),
              if (measurement.spo2 != null)
                _VitalPill(
                  label: 'SpO2',
                  value: '${measurement.spo2!.toStringAsFixed(0)}%',
                ),
              if (measurement.respiratoryRate != null)
                _VitalPill(
                  label: 'Resp. Rate',
                  value: '${measurement.respiratoryRate!.round()} br/min',
                ),
              if (measurement.temperature != null)
                _VitalPill(
                  label: 'Temp',
                  value: '${measurement.temperature!.toStringAsFixed(1)} °C',
                ),
              if (measurement.bloodPressure?.hasValues == true)
                _VitalPill(
                  label: 'BP',
                  value: measurement.bloodPressure!.formatted,
                ),
              if (measurement.bloodSugar != null)
                _VitalPill(
                  label: 'Blood Sugar',
                  value: '${measurement.bloodSugar!.round()} mg/dL',
                ),
              if (measurement.sleep?.hasValues == true)
                _VitalPill(
                  label: 'Sleep',
                  value:
                      '${measurement.sleep!.formattedDuration}${measurement.sleep!.quality != null ? ' (${measurement.sleep!.quality})' : ''}',
                ),
              if (measurement.activity?.steps != null)
                _VitalPill(
                  label: 'Activity',
                  value: '${measurement.activity!.steps} steps',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final HealthAlert alert;
  final bool isBusy;
  final VoidCallback onMarkRead;

  const _AlertCard({
    required this.alert,
    required this.isBusy,
    required this.onMarkRead,
  });

  Color _severityBg(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
      case 'high':
        return const Color(0xFFFEF3F2);
      case 'medium':
        return const Color(0xFFFFF8E6);
      default:
        return AppColors.lightBackground;
    }
  }

  Color _severityFg(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
      case 'high':
        return const Color(0xFFB42318);
      case 'medium':
        return const Color(0xFF8A5300);
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: alert.isRead ? AppColors.white : const Color(0xFFF6FAFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: alert.isRead ? AppColors.border : AppColors.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _SmallTag(
                label: alert.severity.toUpperCase(),
                bgColor: _severityBg(alert.severity),
                fgColor: _severityFg(alert.severity),
              ),
              _SmallTag(
                label: alert.isRead ? 'READ' : 'UNREAD',
                bgColor: alert.isRead
                    ? const Color(0xFFF2F4F8)
                    : const Color(0xFFDCEBFF),
                fgColor: alert.isRead ? AppColors.grey : AppColors.navy,
              ),
              Text(
                formatOrbitTimestamp(alert.createdAt),
                style: const TextStyle(fontSize: 11, color: AppColors.grey),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            alert.title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            alert.message,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.darkText,
              height: 1.4,
            ),
          ),
          if (!alert.isRead) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: Key('mark_read_${alert.id}'),
                onPressed: isBusy ? null : onMarkRead,
                icon: isBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.done_all, size: 16),
                label: const Text('Mark as Read'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportSummaryCard extends StatelessWidget {
  final HealthReport report;

  const _ReportSummaryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final sleepHours = report.totalSleepMinutes ~/ 60;
    final sleepMins = report.totalSleepMinutes % 60;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${report.period.toUpperCase()} REPORT • ${report.records} RECORD(S)',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${formatOrbitTimestamp(report.startDate)} → ${formatOrbitTimestamp(report.endDate)}',
            style: const TextStyle(fontSize: 12, color: AppColors.grey),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _VitalPill(
                label: 'Avg Heart Rate',
                value: report.averageHeartRate != null
                    ? '${report.averageHeartRate!.toStringAsFixed(1)} bpm'
                    : '--',
              ),
              _VitalPill(
                label: 'Avg SpO2',
                value: report.averageSpo2 != null
                    ? '${report.averageSpo2!.toStringAsFixed(1)}%'
                    : '--',
              ),
              _VitalPill(
                label: 'Avg Resp. Rate',
                value: report.averageRespiratoryRate != null
                    ? '${report.averageRespiratoryRate!.toStringAsFixed(1)} br/min'
                    : '--',
              ),
              _VitalPill(
                label: 'Avg Temp',
                value: report.averageTemperature != null
                    ? '${report.averageTemperature!.toStringAsFixed(1)} °C'
                    : '--',
              ),
              _VitalPill(
                label: 'Total Steps',
                value: '${report.totalSteps}',
              ),
              _VitalPill(
                label: 'Total Calories',
                value: '${report.totalCalories.round()} kcal',
              ),
              _VitalPill(
                label: 'Total Sleep',
                value: '${sleepHours}h ${sleepMins}m',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallTag extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color fgColor;

  const _SmallTag({
    required this.label,
    required this.bgColor,
    required this.fgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: fgColor,
        ),
      ),
    );
  }
}

class _SectionLoadingCard extends StatelessWidget {
  final String label;

  const _SectionLoadingCard({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.navy, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _SectionErrorCard({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3F2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDA29B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, color: Color(0xFFB42318), size: 20),
              SizedBox(width: 8),
              Text(
                'Unable to Load Data',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB42318),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(fontSize: 13, color: AppColors.darkText),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _SectionEmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionEmptyCard({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AppColors.grey),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.grey,
              height: 1.4,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
              ),
              icon: const Icon(Icons.add, size: 18),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
