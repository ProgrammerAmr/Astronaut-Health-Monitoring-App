import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../models/cognitive_state_models.dart';
import '../services/cognitive_state_api_client.dart';

class CognitiveStateResearchCard extends StatefulWidget {
  final CognitiveStateApiClient? apiClient;
  final String? authToken;
  final CognitiveStateUiSnapshot? initialSnapshot;
  final bool autoFetchStatus;

  const CognitiveStateResearchCard({
    super.key,
    this.apiClient,
    this.authToken,
    this.initialSnapshot,
    this.autoFetchStatus = true,
  });

  @override
  State<CognitiveStateResearchCard> createState() =>
      _CognitiveStateResearchCardState();
}

class _CognitiveStateResearchCardState
    extends State<CognitiveStateResearchCard> {
  late final CognitiveStateApiClient _client;
  late CognitiveStateUiSnapshot _snapshot;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _client = widget.apiClient ?? CognitiveStateApiClient();
    if (widget.initialSnapshot != null) {
      _snapshot = widget.initialSnapshot!;
    } else if (widget.autoFetchStatus) {
      _snapshot = const CognitiveStateUiSnapshot(
        uiStatus: CognitiveStateUiStatus.loading,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadStatus();
      });
    } else {
      _snapshot = const CognitiveStateUiSnapshot(
        uiStatus: CognitiveStateUiStatus.unavailable,
        message: 'Cognitive state service status has not been loaded yet.',
      );
    }
  }

  Future<void> _loadStatus() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _snapshot = const CognitiveStateUiSnapshot(
        uiStatus: CognitiveStateUiStatus.loading,
      );
    });

    final result = await _client.fetchStatus(authToken: widget.authToken);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _snapshot = result;
    });
  }

  Future<void> _requestAnalysis(CognitiveStateMode mode) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _snapshot = const CognitiveStateUiSnapshot(
        uiStatus: CognitiveStateUiStatus.loading,
      );
    });

    final result = await _client.analyze(
      mode: mode,
      authToken: widget.authToken,
      sessionId: mode == CognitiveStateMode.syntheticDemo
          ? 'synthetic-demo-preview'
          : 'nasa-replay-check',
      dataProvenance: mode == CognitiveStateMode.syntheticDemo
          ? 'synthetic'
          : 'real_nasa_csm_replay',
      signalQuality: mode == CognitiveStateMode.researchReplay
          ? const SignalQualityInfo(sqiScore: 0.95, valid: true)
          : null,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _snapshot = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSynthetic = _snapshot.uiStatus ==
            CognitiveStateUiStatus.syntheticDemo ||
        (_snapshot.analysis?.isSynthetic == true);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.lightBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.psychology_outlined,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cognitive State Monitoring',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _StatusChip(
                          label: 'DEC-001 RESEARCH',
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.10),
                          textColor: AppColors.primary,
                        ),
                        if (isSynthetic)
                          const _StatusChip(
                            label: kCsmSyntheticDemoLabel,
                            backgroundColor: Color(0xFFFFF3CD),
                            textColor: Color(0xFF8A5300),
                            icon: Icons.science_outlined,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Prominent non-diagnostic disclaimer banner (always visible)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF0C36D)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Color(0xFF8A5300),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kCsmResearchDisclaimer,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF663C00),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Dynamic state body
          _buildStateContent(),

          const SizedBox(height: 16),

          // Action controls
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _loadStatus,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh Status'),
              ),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _requestAnalysis(CognitiveStateMode.syntheticDemo),
                icon: const Icon(Icons.science_outlined, size: 16),
                label: const Text('Synthetic Demo'),
              ),
              ElevatedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _requestAnalysis(CognitiveStateMode.researchReplay),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                ),
                icon: const Icon(Icons.analytics_outlined, size: 16),
                label: const Text('Research Replay'),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 10),

          // Fixed limitations notice
          const Text(
            'Scope & Validation Boundaries',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 6),
          ..._effectiveLimitations().take(3).map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.grey,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.grey,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  List<String> _effectiveLimitations() {
    List<String> raw;
    final fromStatus = _snapshot.serviceStatus?.limitations;
    final fromModel = _snapshot.analysis?.modelStatus.cohortLimitations;
    if (fromStatus != null && fromStatus.isNotEmpty) {
      raw = fromStatus;
    } else if (fromModel != null && fromModel.isNotEmpty) {
      raw = fromModel;
    } else {
      raw = kCsmDefaultLimitations;
    }
    final filtered =
        raw.where((item) => item.trim() != kCsmResearchDisclaimer).toList();
    return filtered.isNotEmpty ? filtered : kCsmDefaultLimitations;
  }

  Widget _buildStateContent() {
    switch (_snapshot.uiStatus) {
      case CognitiveStateUiStatus.loading:
        return _buildLoadingView();
      case CognitiveStateUiStatus.unavailable:
        return _buildUnavailableView();
      case CognitiveStateUiStatus.insufficientData:
        return _buildInsufficientDataView();
      case CognitiveStateUiStatus.error:
        return _buildErrorView();
      case CognitiveStateUiStatus.syntheticDemo:
        return _buildSyntheticDemoView();
      case CognitiveStateUiStatus.validResearch:
        return _buildValidResearchView();
    }
  }

  Widget _buildLoadingView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.lightBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary,
            ),
          ),
          SizedBox(width: 12),
          Flexible(
            child: Text(
              'Loading cognitive state research status...',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppColors.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailableView() {
    return _StateBox(
      icon: Icons.cloud_off_outlined,
      accentColor: const Color(0xFF5C6B82),
      backgroundColor: const Color(0xFFF2F4F8),
      badgeLabel: 'SERVICE UNAVAILABLE',
      title: 'Cognitive State Service Unavailable',
      description: _snapshot.message ??
          'The research backend or AI service is currently unreachable. No prediction has been substituted.',
      code: _snapshot.errorCode,
    );
  }

  Widget _buildInsufficientDataView() {
    final analysis = _snapshot.analysis;
    final sqi = analysis?.signalQuality;
    final reasons = sqi?.reasons ?? const <String>[];
    final warnings = analysis?.warnings ?? const <String>[];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFD7FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusChip(
                label: 'INSUFFICIENT_DATA',
                backgroundColor: Color(0xFFDCEBFF),
                textColor: AppColors.navy,
                icon: Icons.shield_outlined,
              ),
              _StatusChip(
                label: 'Abstained Safely',
                backgroundColor: AppColors.white,
                textColor: AppColors.primary,
              ),
              _StatusChip(
                label: 'Model Validated: false',
                backgroundColor: AppColors.white,
                textColor: AppColors.grey,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _snapshot.message ??
                'No validated cognitive state prediction is available for this request. The system abstained safely instead of substituting Baseline or inventing probabilities.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.darkText,
              height: 1.4,
            ),
          ),
          if (sqi != null) ...[
            const SizedBox(height: 10),
            Text(
              'Signal Quality (SQI): ${(sqi.sqiScore * 100).toStringAsFixed(0)}% • Valid: ${sqi.valid}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
              ),
            ),
          ],
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Abstention reason(s): ${reasons.join(", ")}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.grey,
              ),
            ),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              warnings.first,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.grey,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    final analysis = _snapshot.analysis;
    final firstErr =
        analysis != null && analysis.errors.isNotEmpty ? analysis.errors.first : null;
    final code = firstErr?.code ?? _snapshot.errorCode ?? 'ERROR';
    final msg = firstErr?.message ??
        _snapshot.message ??
        'Request failed. No prediction was substituted.';

    return _StateBox(
      icon: Icons.error_outline,
      accentColor: const Color(0xFFB42318),
      backgroundColor: const Color(0xFFFEF3F2),
      badgeLabel: 'ERROR',
      title: 'Cognitive State Request Error',
      description: msg,
      code: code,
    );
  }

  Widget _buildSyntheticDemoView() {
    final analysis = _snapshot.analysis;
    final sqi = analysis?.signalQuality;
    final warnings = analysis?.warnings ?? const <String>[];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6B84C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _StatusChip(
                label: kCsmSyntheticDemoLabel,
                backgroundColor: Color(0xFFFFE7A3),
                textColor: Color(0xFF6E4100),
                icon: Icons.science_outlined,
              ),
              _StatusChip(
                label: 'Provenance: synthetic',
                backgroundColor: AppColors.white,
                textColor: Color(0xFF8A5300),
              ),
              _StatusChip(
                label: 'Model Validated: false',
                backgroundColor: AppColors.white,
                textColor: AppColors.grey,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Synthetic Demo Output — Probabilities Withheld',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF6E4100),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            warnings.isNotEmpty
                ? warnings.first
                : 'Synthetic demo data only. No real physiological telemetry and no registered CSM model artifact exist; probabilities are intentionally withheld.',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.darkText,
              height: 1.4,
            ),
          ),
          if (sqi != null) ...[
            const SizedBox(height: 8),
            Text(
              'Demo SQI: ${(sqi.sqiScore * 100).toStringAsFixed(0)}% • Prediction: Abstained (status: ${analysis?.status ?? "INSUFFICIENT_DATA"})',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.navy,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildValidResearchView() {
    final analysis = _snapshot.analysis!;
    final pred = analysis.prediction;
    final probs = pred.probabilities ?? const <String, double>{};
    final sqi = analysis.signalQuality;
    final model = analysis.modelStatus;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF8CE0C4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              const _StatusChip(
                label: 'RESEARCH REPLAY',
                backgroundColor: Color(0xFFD1FAE5),
                textColor: Color(0xFF065F46),
                icon: Icons.verified_outlined,
              ),
              _StatusChip(
                label: 'Provenance: ${analysis.dataProvenance}',
                backgroundColor: AppColors.white,
                textColor: AppColors.navy,
              ),
              _StatusChip(
                label: 'Model Validated: ${model.validated}',
                backgroundColor: AppColors.white,
                textColor: model.validated
                    ? const Color(0xFF065F46)
                    : const Color(0xFF8A5300),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Estimated Attention State (Research)',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.grey,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pred.state ?? 'N/A',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
              if (pred.confidence != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Confidence',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.grey,
                      ),
                    ),
                    Text(
                      '${(pred.confidence! * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.teal,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (probs.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...probs.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.darkText,
                          ),
                        ),
                        Text(
                          '${(entry.value * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.grey,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: entry.value,
                        minHeight: 6,
                        backgroundColor: AppColors.white,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'SQI: ${(sqi.sqiScore * 100).toStringAsFixed(0)}% • Calibrated: ${model.calibrated}',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final IconData? icon;

  const _StatusChip({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _StateBox extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final Color backgroundColor;
  final String badgeLabel;
  final String title;
  final String description;
  final String? code;

  const _StateBox({
    required this.icon,
    required this.accentColor,
    required this.backgroundColor,
    required this.badgeLabel,
    required this.title,
    required this.description,
    this.code,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accentColor),
              const SizedBox(width: 6),
              Text(
                badgeLabel,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                ),
              ),
              if (code case final String errCode when errCode.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '($errCode)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.grey,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.darkText,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
