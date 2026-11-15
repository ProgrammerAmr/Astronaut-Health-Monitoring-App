import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_widgets.dart';
import '../core/config/api_config.dart';
import '../core/config/backend_config.dart';

/// In-app backend connection diagnostics & configuration.
///
/// Solves the most common "the app will not connect / I cannot log in" problem
/// without a rebuild: the developer can see which URL the app is actually
/// using, test it against `GET /api/health`, read concrete fix hints, and save
/// a new URL that takes effect immediately.
class ConnectionSettingsScreen extends StatefulWidget {
  final BackendConfig? config;

  const ConnectionSettingsScreen({super.key, this.config});

  @override
  State<ConnectionSettingsScreen> createState() =>
      _ConnectionSettingsScreenState();
}

class _ConnectionSettingsScreenState extends State<ConnectionSettingsScreen> {
  late final BackendConfig _config = widget.config ?? BackendConfig.instance;
  late final TextEditingController _urlController;

  bool _probing = false;
  bool _saving = false;
  BackendProbeResult? _probeResult;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: _config.effectiveBaseUrl);
    _config.load();
    _config.addListener(_syncFieldWithConfig);
  }

  void _syncFieldWithConfig() {
    if (!mounted) return;
    if (!_probing && !_saving && _urlController.text != _config.effectiveBaseUrl) {
      _urlController.text = _config.effectiveBaseUrl;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _config.removeListener(_syncFieldWithConfig);
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _probe({bool useTypedUrl = true}) async {
    final typed = _urlController.text.trim();
    final target = useTypedUrl && typed.isNotEmpty
        ? normalizeApiBaseUrl(typed.startsWith('http')
            ? typed
            : 'http://$typed')
        : _config.effectiveBaseUrl;

    setState(() {
      _probing = true;
      _probeResult = null;
      _validationError = null;
    });

    final result = await _config.probeHealth(url: target);
    if (!mounted) return;
    setState(() {
      _probing = false;
      _probeResult = result;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _validationError = null;
    });

    try {
      await _config.setOverride(_urlController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backend URL saved: ${_config.effectiveBaseUrl}'),
        ),
      );
      await _probe(useTypedUrl: false);
    } on ArgumentError catch (error) {
      if (!mounted) return;
      setState(() {
        _validationError = error.message.toString();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _validationError = 'Could not save the URL: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _resetToDefault() async {
    await _config.clearOverride();
    if (!mounted) return;
    setState(() {
      _urlController.text = _config.effectiveBaseUrl;
      _probeResult = null;
      _validationError = null;
    });
  }

  void _applyPreset(String url) {
    setState(() {
      _urlController.text = url;
      _validationError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final source = _config.source;
    final probeResult = _probeResult;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Backend Connection',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.navy),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _StatusCard(
              url: _config.effectiveBaseUrl,
              sourceLabel: describeApiBaseUrlSource(source),
              isOverride: source == ApiBaseUrlSource.runtimeOverride,
            ),
            const SizedBox(height: 18),
            const SectionLabel(text: 'Backend URL', icon: Icons.link),
            const SizedBox(height: 10),
            AppTextField(
              label: 'API base URL',
              hint: 'http://192.168.1.10:5000',
              icon: Icons.dns_outlined,
              keyboardType: TextInputType.url,
              controller: _urlController,
              enabled: !_saving,
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 10),
              Text(
                _validationError!,
                style: const TextStyle(color: Color(0xFFB42318), fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _PresetChip(
                  label: 'Android emulator (10.0.2.2)',
                  url: 'http://$kAndroidEmulatorHostAlias:$kOrbitCareApiPort',
                  onSelected: _applyPreset,
                ),
                _PresetChip(
                  label: 'This device (localhost)',
                  url: 'http://localhost:$kOrbitCareApiPort',
                  onSelected: _applyPreset,
                ),
                _PresetChip(
                  label: 'This device (127.0.0.1)',
                  url: 'http://127.0.0.1:$kOrbitCareApiPort',
                  onSelected: _applyPreset,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    text: _saving ? 'Saving...' : 'Save URL',
                    icon: Icons.save_outlined,
                    isLoading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    text: _probing ? 'Testing...' : 'Test',
                    icon: Icons.wifi_tethering,
                    isLoading: _probing,
                    onPressed: _probing ? null : () => _probe(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _saving ? null : _resetToDefault,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Reset to build default'),
            ),
            if (probeResult != null) ...[
              const SizedBox(height: 12),
              _ProbeResultCard(result: probeResult),
            ],
            const SizedBox(height: 24),
            const SectionLabel(
              text: 'If the test fails, check',
              icon: Icons.checklist,
            ),
            const SizedBox(height: 10),
            const _ChecklistCard(),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String url;
  final String sourceLabel;
  final bool isOverride;

  const _StatusCard({
    required this.url,
    required this.sourceLabel,
    required this.isOverride,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
            children: [
              Icon(
                isOverride ? Icons.edit_location_alt : Icons.info_outline,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Active backend URL',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            url.isEmpty ? '(not set)' : url,
            style: const TextStyle(
              color: AppColors.darkText,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Source: $sourceLabel',
            style: const TextStyle(color: AppColors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final String url;
  final ValueChanged<String> onSelected;

  const _PresetChip({
    required this.label,
    required this.url,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      avatar: const Icon(Icons.bolt, size: 15, color: AppColors.primary),
      backgroundColor: AppColors.lightBackground,
      side: const BorderSide(color: AppColors.border),
      onPressed: () => onSelected(url),
    );
  }
}

class _ProbeResultCard extends StatelessWidget {
  final BackendProbeResult result;

  const _ProbeResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final ok = result.reachable;
    final background = ok ? const Color(0xFFECFDF3) : const Color(0xFFFEF3F2);
    final border = ok ? const Color(0xFFA6F4C5) : const Color(0xFFFDA29B);
    final foreground = ok ? const Color(0xFF067647) : const Color(0xFFB42318);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                ok ? Icons.check_circle_outline : Icons.error_outline,
                color: foreground,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ok ? 'Connection OK' : 'Connection failed',
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.message,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'GET ${result.probedUrl}/api/health'
            '${result.statusCode == null ? '' : ' -> HTTP ${result.statusCode}'}'
            '${result.elapsed == Duration.zero ? '' : ' in ${result.elapsed.inMilliseconds} ms'}',
            style: TextStyle(
              color: foreground.withValues(alpha: 0.8),
              fontSize: 11.5,
              fontFamily: 'monospace',
            ),
          ),
          if (result.hints.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...result.hints.map(
              (hint) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.arrow_right, size: 18, color: foreground),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        hint,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard();

  static const List<String> _items = <String>[
    'The backend is running on the PC: cd backend && npm run dev (you should see "OrbitCare API running on ...").',
    'MongoDB is running, otherwise the backend exits at startup. Run: npm run doctor inside backend/ for a full report.',
    'Phone and PC are on the same Wi-Fi, and you entered the PC LAN IP (Windows: ipconfig -> IPv4, macOS/Linux: ifconfig / ip addr).',
    'Windows Firewall allows TCP port 5000 (Node.js) — or temporarily test with the firewall off.',
    'Android emulator: use http://10.0.2.2:5000. iOS simulator, Windows, macOS, Linux and web: use http://localhost:5000.',
    'The account is email-verified. Login is blocked until the OTP is confirmed; in development the OTP is printed in the backend terminal as [DEVELOPMENT OTP].',
    'For a ready-made verified account run: cd backend && npm run seed:demo, then sign in with demo.astronaut@orbitcare.local.',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_box_outline_blank,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: AppColors.grey,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
