import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_widgets.dart';
import '../core/config/api_config.dart';
import '../core/models/orbitcare_models.dart';
import '../core/state/session_controller.dart';

/// Dedicated screen to configure, test (`GET /api/health`), and persist the
/// OrbitCare backend server base URL before signup or login.
class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final TextEditingController _urlController = TextEditingController();

  bool _hydrated = false;
  bool _isTesting = false;
  bool _isSaving = false;
  ConnectionCheckResult? _checkResult;
  String? _saveError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hydrated) {
      _hydrated = true;
      _hydrateInitialUrl();
    }
  }

  Future<void> _hydrateInitialUrl() async {
    final controller = SessionScope.maybeOf(context);
    if (controller == null) return;
    await controller.ensureConfigLoaded();
    if (!mounted) return;
    if (_urlController.text.isEmpty && controller.apiBaseUrl.isNotEmpty) {
      setState(() {
        _urlController.text = controller.apiBaseUrl;
      });
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String _sourceLabel(ApiUrlSource source) {
    switch (source) {
      case ApiUrlSource.saved:
        return 'Saved on Device';
      case ApiUrlSource.buildDefault:
        return 'Build Default';
      case ApiUrlSource.unconfigured:
        return 'Not Configured';
    }
  }

  Future<void> _handleTestConnection() async {
    final controller = SessionScope.maybeOf(context);
    if (controller == null) return;

    setState(() {
      _isTesting = true;
      _saveError = null;
    });

    final result = await controller.testConnection(
      candidateUrl: _urlController.text,
    );

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _checkResult = result;
    });
  }

  Future<void> _handleSave() async {
    final controller = SessionScope.maybeOf(context);
    if (controller == null) return;

    final validationError = validateApiBaseUrl(_urlController.text);
    if (validationError != null) {
      setState(() {
        _saveError = validationError;
        _checkResult = ConnectionCheckResult(
          status: _urlController.text.trim().isEmpty
              ? ConnectionCheckStatus.missingConfig
              : ConnectionCheckStatus.invalidUrl,
          message: validationError,
        );
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      await controller.updateApiBaseUrl(_urlController.text);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on OrbitCareApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saveError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saveError = 'Unable to save server URL right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _handleReset() async {
    final controller = SessionScope.maybeOf(context);
    if (controller == null) return;

    setState(() {
      _isSaving = true;
      _saveError = null;
      _checkResult = null;
    });

    try {
      await controller.resetApiBaseUrlToDefault();
      if (!mounted) return;
      setState(() {
        _urlController.text = controller.apiBaseUrl;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = SessionScope.maybeOf(context);
    final source = controller?.urlSource ?? ApiUrlSource.unconfigured;
    final currentText = _urlController.text.trim();
    final previewUrl =
        isValidApiBaseUrl(currentText) ? normalizeApiBaseUrl(currentText) : null;
    final busy = _isTesting || _isSaving;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Configure Server URL',
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
              // Active source & precedence card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Active Configuration',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navy,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: source == ApiUrlSource.unconfigured
                                ? const Color(0xFFFFF3CD)
                                : const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _sourceLabel(source),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: source == ApiUrlSource.unconfigured
                                  ? const Color(0xFF8A5300)
                                  : AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      controller != null && controller.apiBaseUrl.isNotEmpty
                          ? controller.apiBaseUrl
                          : 'No backend URL is currently saved.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Precedence: a URL saved on this device overrides any optional build-time default. Physical phones require a reachable public HTTPS URL (not localhost or 127.0.0.1).',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.grey,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Input & Test Connection card
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
                    const Text(
                      'ORBITCARE BACKEND BASE URL',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('server_url_input'),
                      controller: _urlController,
                      enabled: !busy,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      onChanged: (_) {
                        setState(() {
                          _saveError = null;
                          _checkResult = null;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'https://your-orbitcare-backend.example.com',
                        prefixIcon: const Icon(
                          Icons.dns_outlined,
                          color: AppColors.navy,
                        ),
                        errorText: _saveError,
                        filled: true,
                        fillColor: AppColors.lightBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    if (previewUrl != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Health check target: $previewUrl/api/health',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.grey,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const Key('test_connection_btn'),
                        onPressed: busy ? null : _handleTestConnection,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _isTesting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Icon(Icons.wifi_tethering_outlined),
                        label: Text(
                          _isTesting
                              ? 'Testing /api/health...'
                              : 'Test Connection',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    if (_checkResult != null) ...[
                      const SizedBox(height: 14),
                      _ConnectionResultCard(result: _checkResult!),
                    ],
                    const SizedBox(height: 18),
                    PrimaryButton(
                      key: const Key('save_server_url_btn'),
                      text: 'Save Server URL',
                      icon: Icons.check_circle_outline,
                      isLoading: _isSaving,
                      onPressed: busy ? null : _handleSave,
                    ),
                    if (source == ApiUrlSource.saved) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton.icon(
                          key: const Key('reset_server_url_btn'),
                          onPressed: busy ? null : _handleReset,
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: Text(
                            controller?.hasBuildDefault == true
                                ? 'Reset to Build Default'
                                : 'Clear Saved Server URL',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionResultCard extends StatelessWidget {
  final ConnectionCheckResult result;

  const _ConnectionResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final bool isOk = result.isSuccess;
    final bool isWarning =
        result.status == ConnectionCheckStatus.missingConfig ||
            result.status == ConnectionCheckStatus.timeout;

    final Color bgColor;
    final Color borderColor;
    final Color fgColor;
    final IconData icon;
    final String title;

    if (isOk) {
      bgColor = const Color(0xFFECFDF3);
      borderColor = const Color(0xFF6CE9A6);
      fgColor = const Color(0xFF067647);
      icon = Icons.check_circle_outline;
      title = result.latencyMs != null
          ? 'Connected (${result.latencyMs} ms)'
          : 'Connected';
    } else if (isWarning) {
      bgColor = const Color(0xFFFFFAEB);
      borderColor = const Color(0xFFFEC84B);
      fgColor = const Color(0xFFB54708);
      icon = result.status == ConnectionCheckStatus.timeout
          ? Icons.timer_off_outlined
          : Icons.warning_amber_rounded;
      title = result.status == ConnectionCheckStatus.timeout
          ? 'Connection Timed Out'
          : 'Configuration Required';
    } else {
      bgColor = const Color(0xFFFEF3F2);
      borderColor = const Color(0xFFFDA29B);
      fgColor = const Color(0xFFB42318);
      icon = Icons.error_outline;
      switch (result.status) {
        case ConnectionCheckStatus.invalidUrl:
          title = 'Invalid Server URL';
        case ConnectionCheckStatus.unreachable:
          title = 'Server Unreachable';
        case ConnectionCheckStatus.serverError:
          title = result.statusCode != null
              ? 'Server Error (HTTP ${result.statusCode})'
              : 'Server Error';
        default:
          title = 'Connection Failed';
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: fgColor, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: fgColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            result.message,
            style: TextStyle(
              color: fgColor,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          if (isOk && result.databaseStatus != null) ...[
            const SizedBox(height: 6),
            Text(
              'Database: ${result.databaseStatus}'
              '${result.emailConfigured != null ? ' • Email OTP: ${result.emailConfigured! ? 'configured' : 'dev console mode'}' : ''}',
              style: TextStyle(
                color: fgColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
