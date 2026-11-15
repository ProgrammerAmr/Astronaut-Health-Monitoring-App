import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../core/models/orbitcare_models.dart';
import '../core/state/session_controller.dart';
import '../routes/app_routes.dart';

/// Astronaut Profile & Local Settings screen matching OrbitCare's visual design.
/// Supports both Offline Demo Mode (with local persisted preferences and Demo
/// Data Reset) and authenticated Production sessions.
class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  bool _busy = false;

  Future<void> _updatePrefs(
    SessionController controller,
    DemoPreferences next,
  ) async {
    await controller.updateDemoPreferences(next);
  }

  Future<void> _resetDemoData(SessionController controller) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await controller.resetDemoData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Demo measurements and alerts reset to baseline.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleExitOrLogout(SessionController controller) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await controller.logout();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = SessionScope.maybeOf(context);
    final user = controller?.user;
    final isDemo = controller?.isDemoMode ?? false;
    final prefs = controller?.demoPreferences ?? const DemoPreferences();
    final serverUrl = controller?.apiBaseUrl ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Profile & Settings',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.navy),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Card
              Container(
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
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.lightBackground,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.person_outline,
                            size: 28,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.name ?? 'Astronaut Profile',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navy,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user?.email ?? 'Not signed in',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _ProfileBadge(
                          label: isDemo
                              ? 'DEMO MODE • OFFLINE'
                              : 'PRODUCTION ACCOUNT',
                          bgColor: isDemo
                              ? const Color(0xFFFFF3CD)
                              : const Color(0xFFEFF6FF),
                          fgColor: isDemo
                              ? const Color(0xFF8A5300)
                              : AppColors.primary,
                        ),
                        if (user != null)
                          _ProfileBadge(
                            label: 'ROLE: ${user.role.toUpperCase()}',
                            bgColor: AppColors.lightBackground,
                            fgColor: AppColors.navy,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: AppColors.border, height: 1),
                    const SizedBox(height: 12),
                    _InfoRow(
                      label: 'Mission',
                      value: user?.missionName ?? 'Not assigned',
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: 'Mission Role',
                      value: user?.missionRole ?? 'Crew Member',
                    ),
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: 'Status',
                      value: user?.missionStatus ??
                          (isDemo ? 'Offline Demo Simulation Active' : 'Active'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Display & Local Preferences Card
              Material(
                color: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DISPLAY & LOCAL PREFERENCES',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        key: const Key('toggle_fahrenheit_switch'),
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Show Temperature in Fahrenheit (°F)',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.navy,
                          ),
                        ),
                        subtitle: Text(
                          prefs.useFahrenheit
                              ? 'Currently displaying temperatures in °F'
                              : 'Currently displaying temperatures in °C',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.grey,
                          ),
                        ),
                        value: prefs.useFahrenheit,
                        onChanged: controller == null
                            ? null
                            : (val) => _updatePrefs(
                                  controller,
                                  prefs.copyWith(useFahrenheit: val),
                                ),
                      ),
                      if (isDemo) ...[
                        const Divider(color: AppColors.border, height: 1),
                        SwitchListTile.adaptive(
                          key: const Key('toggle_auto_alerts_switch'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Auto-Generate Local Demo Threshold Alerts',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.navy,
                            ),
                          ),
                          subtitle: const Text(
                            'When logging out-of-range vitals in Demo Mode, create a clearly labeled local [DEMO] reminder.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.grey,
                            ),
                          ),
                          value: prefs.autoThresholdAlerts,
                          onChanged: controller == null
                              ? null
                              : (val) => _updatePrefs(
                                    controller,
                                    prefs.copyWith(autoThresholdAlerts: val),
                                  ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              if (isDemo) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBF0),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE6B84C)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.science_outlined,
                            color: Color(0xFF8A5300),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Offline Demo Mode Controls',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6E4100),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'All vitals, alerts, and reports in Demo Mode are locally stored synthetic sample data (no live server, real sensors, or email OTP). Your demo changes persist locally across app restarts and never mix with production user accounts.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.darkText,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const Key('reset_demo_data_btn'),
                          onPressed: (_busy || controller == null)
                              ? null
                              : () => _resetDemoData(controller),
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: const Text('Reset Demo Data to Baseline'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // Backend & Session Card
              Material(
                color: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BACKEND & SESSION',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        key: const Key('settings_server_config_btn'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.dns_outlined,
                          color: AppColors.primary,
                        ),
                        title: const Text(
                          'Configure Production Server URL',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.navy,
                          ),
                        ),
                        subtitle: Text(
                          serverUrl.isNotEmpty
                              ? serverUrl
                              : (isDemo
                                  ? 'Not configured (bypassed in Offline Demo Mode)'
                                  : 'Not configured'),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.grey,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: AppColors.grey,
                        ),
                        onTap: () {
                          Navigator.pushNamed(context, AppRoutes.serverConfig);
                        },
                      ),
                      const Divider(color: AppColors.border, height: 1),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          key: const Key('settings_logout_btn'),
                          onPressed: (_busy || controller == null)
                              ? null
                              : () => _handleExitOrLogout(controller),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB42318),
                            foregroundColor: AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: Icon(
                            isDemo ? Icons.exit_to_app : Icons.logout,
                            size: 18,
                          ),
                          label: Text(
                            isDemo ? 'Exit Demo Mode' : 'Sign Out',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color fgColor;

  const _ProfileBadge({
    required this.label,
    required this.bgColor,
    required this.fgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fgColor,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.navy,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
