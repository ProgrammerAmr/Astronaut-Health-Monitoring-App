import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class _HomePalette {
  static const Color iconCircleBg = Color(0xFFF0F2FA);
  static const Color smallIconCircleBg = Color(0xFFECF1FD);
  static const Color cardShadow = Color(0x10101828);
  static const Color navShadow = Color(0x0E101828);

  static const Color missionPillBg = Color(0xFFE9F0FF);
  static const Color missionDotGreen = Color(0xFF259E88);
  static const Color slateText = Color(0xFF48566B);
  static const Color bodyText = Color(0xFF475467);
  static const Color mutedGrey = Color(0xFF6B7280);
  static const Color navInactive = Color(0xFF989FA9);

  static const Color telemetryTeal = Color(0xFF186B6E);
  static const Color sectionBlue = Color(0xFF154C8B);
  static const Color ringBlue = Color(0xFF0A58B4);
  static const Color ringTrack = Color(0xFFE2ECF8);
  static const Color primaryActionBlue = Color(0xFF0755A8);
  static const Color primaryActionShadow = Color(0x2E0755A8);

  static const Color mintBadgeBg = Color(0xFFDFF2EE);
  static const Color mintBadgeText = Color(0xFF1F7A68);
  static const Color positiveTeal = Color(0xFF279B83);

  static const Color alertRed = Color(0xFFC41D14);
  static const Color spo2Blue = Color(0xFF1557A4);
  static const Color tempTeal = Color(0xFF086C74);

  static const Color podBadgeBg = Color(0xFFE7EEFF);
  static const Color softSurface = Color(0xFFEFF3FF);
  static const Color deepSleepPillBg = Color(0xFFF7F9FF);
  static const Color deepSleepPillText = Color(0xFF1E60AE);

  static const Color sleepDeep = Color(0xFF0955AE);
  static const Color sleepLight = Color(0xFF4E90FC);
  static const Color sleepRem = Color(0xFF5AD8E7);
  static const Color innerDivider = Color(0xFFE8EEF7);

  static const Color bellIcon = Color(0xFF2B3445);
  static const Color refreshIcon = Color(0xFF444F65);
  static const Color activityIcon = Color(0xFF0F4C8C);

  static const List<BoxShadow> cardShadows = [
    BoxShadow(color: cardShadow, blurRadius: 18, offset: Offset(0, 6)),
  ];
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedNavIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TopHeaderBar(
                onBackTap: () => Navigator.maybePop(context),
                onNotificationTap: () {},
              ),
              const SizedBox(height: 10),
              const _MissionStatusRow(),
              const SizedBox(height: 14),
              const _GreetingHeader(),
              const SizedBox(height: 16),
              _OverallHealthCard(onRefreshTap: () {}),
              const SizedBox(height: 14),
              const _VitalsRow(),
              const SizedBox(height: 16),
              _SleepRecoveryCard(onViewArchitectureTap: () {}),
              const SizedBox(height: 16),
              const _PhysicalCountermeasureCard(),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _ClinicalCheckInButton(onPressed: () {}),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _HomeBottomNavBar(
        selectedIndex: _selectedNavIndex,
        onTap: (index) => setState(() => _selectedNavIndex = index),
      ),
    );
  }
}

class _TopHeaderBar extends StatelessWidget {
  final VoidCallback onBackTap;
  final VoidCallback onNotificationTap;

  const _TopHeaderBar({
    required this.onBackTap,
    required this.onNotificationTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          InkWell(
            onTap: onBackTap,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: AppColors.navy,
              ),
            ),
          ),
          Material(
            color: _HomePalette.iconCircleBg,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onNotificationTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.notifications_none_rounded,
                      size: 22,
                      color: _HomePalette.bellIcon,
                    ),
                    Positioned(
                      top: 9,
                      right: 9,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: _HomePalette.alertRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionStatusRow extends StatelessWidget {
  const _MissionStatusRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _HomePalette.missionPillBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: _HomePalette.missionDotGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Flexible(
                  child: Text(
                    'MISSION ARTEMIS VII \u2022 DAY 42',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: _HomePalette.slateText,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.satellite_alt_outlined,
              size: 16,
              color: _HomePalette.telemetryTeal,
            ),
            SizedBox(width: 4),
            Text(
              'Telemetry Live',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: _HomePalette.slateText,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Good morning, Alex.',
          style: TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w700,
            color: AppColors.darkText,
            height: 1.15,
            letterSpacing: -0.4,
          ),
        ),
        SizedBox(height: 5),
        Text(
          'Orbital diurnal phase cycle at 08:30 UTC.',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w400,
            color: _HomePalette.bodyText,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _OverallHealthCard extends StatelessWidget {
  final VoidCallback onRefreshTap;

  const _OverallHealthCard({required this.onRefreshTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: _HomePalette.cardShadows,
      ),
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'DIAGNOSTIC SUMMARY',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: _HomePalette.sectionBlue,
                            letterSpacing: 0.4,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _HomePalette.mintBadgeBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Optimal',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: _HomePalette.mintBadgeText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Overall Health',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkText,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: _HomePalette.iconCircleBg,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: onRefreshTap,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(
                      Icons.sync,
                      size: 19,
                      color: _HomePalette.refreshIcon,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _HealthScoreRing(score: 94, maxScore: 100),
              SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'All vitals nominal.\n'
                      'Physiological microgravity adaptation tracking smoothly '
                      'within nominal parameters.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: _HomePalette.bodyText,
                        height: 1.48,
                      ),
                    ),
                    SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.verified_outlined,
                          size: 16,
                          color: _HomePalette.sectionBlue,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Zero anomalous variances detected',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _HomePalette.sectionBlue,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthScoreRing extends StatelessWidget {
  final int score;
  final int maxScore;

  const _HealthScoreRing({required this.score, required this.maxScore});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 86,
      child: CustomPaint(
        painter: _HealthScoreRingPainter(progress: score / maxScore),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkText,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '/ $maxScore',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _HomePalette.mutedGrey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthScoreRingPainter extends CustomPainter {
  final double progress;

  const _HealthScoreRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const double strokeWidth = 6.5;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _HomePalette.ringTrack
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2 + 0.04,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = _HomePalette.ringBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _HealthScoreRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _VitalsRow extends StatelessWidget {
  const _VitalsRow();

  static const TextStyle _labelStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: _HomePalette.mutedGrey,
  );

  static const TextStyle _valueStyle = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w700,
    color: AppColors.darkText,
    height: 1.15,
  );

  static const TextStyle _unitStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: _HomePalette.mutedGrey,
  );

  static const TextStyle _mutedSubStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: _HomePalette.mutedGrey,
  );

  static const TextStyle _positiveSubStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: _HomePalette.positiveTeal,
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: _VitalMetricCard(
            icon: Icons.favorite,
            iconColor: _HomePalette.alertRed,
            label: Text('BPM', style: _labelStyle),
            value: Text('68', style: _valueStyle),
            subtitle: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '+2 ', style: _positiveSubStyle),
                  TextSpan(text: 'vs base', style: _mutedSubStyle),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _VitalMetricCard(
            icon: Icons.air,
            iconColor: _HomePalette.spo2Blue,
            label: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'SPO', style: _labelStyle),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: Transform.translate(
                      offset: const Offset(0, 2),
                      child: const Text(
                        '2',
                        style: TextStyle(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w500,
                          color: _HomePalette.mutedGrey,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            value: const Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '99', style: _valueStyle),
                  TextSpan(text: '%', style: _unitStyle),
                ],
              ),
            ),
            subtitle: const Text('Optimal', style: _positiveSubStyle),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: _VitalMetricCard(
            icon: Icons.thermostat,
            iconColor: _HomePalette.tempTeal,
            label: Text('TEMP', style: _labelStyle),
            value: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '36.6', style: _valueStyle),
                  TextSpan(text: '\u00B0C', style: _unitStyle),
                ],
              ),
            ),
            subtitle: Text('Nominal', style: _mutedSubStyle),
          ),
        ),
      ],
    );
  }
}

class _VitalMetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Widget label;
  final Widget value;
  final Widget subtitle;

  const _VitalMetricCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _HomePalette.cardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 4),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: label,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: value,
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: subtitle,
          ),
        ],
      ),
    );
  }
}

class _SleepRecoveryCard extends StatelessWidget {
  final VoidCallback onViewArchitectureTap;

  const _SleepRecoveryCard({required this.onViewArchitectureTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: _HomePalette.cardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: _HomePalette.smallIconCircleBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bedtime_outlined,
                  size: 16,
                  color: _HomePalette.spo2Blue,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Sleep & Rest\nRecovery',
                  style: TextStyle(
                    fontSize: 17.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _HomePalette.podBadgeBg,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  'Pod 02 \u2022\nCircadian Sync',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: _HomePalette.slateText,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            decoration: BoxDecoration(
              color: _HomePalette.softSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      '7h 45m',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _HomePalette.deepSleepPillBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'Deep Sleep 88%',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _HomePalette.deepSleepPillText,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Target: 8h 00m',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _HomePalette.slateText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: const SizedBox(
                    height: 10,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 33,
                          child: ColoredBox(color: _HomePalette.sleepDeep),
                        ),
                        Expanded(
                          flex: 46,
                          child: ColoredBox(color: _HomePalette.sleepLight),
                        ),
                        Expanded(
                          flex: 21,
                          child: ColoredBox(color: _HomePalette.sleepRem),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _SleepLegendItem(
                          color: _HomePalette.sleepDeep,
                          label: 'Deep (2h 28m)',
                        ),
                      ),
                    ),
                    SizedBox(width: 6),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _SleepLegendItem(
                          color: _HomePalette.sleepLight,
                          label: 'Light (3h 25m)',
                        ),
                      ),
                    ),
                    SizedBox(width: 6),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: _SleepLegendItem(
                          color: _HomePalette.sleepRem,
                          label: 'REM (1h 52m)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: _SleepStatColumn(
                          title: 'TOTAL SLEEP',
                          value: '7h 45m',
                          valueColor: AppColors.darkText,
                        ),
                      ),
                      SizedBox(
                        height: 26,
                        width: 1,
                        child: ColoredBox(color: _HomePalette.innerDivider),
                      ),
                      Expanded(
                        child: _SleepStatColumn(
                          title: 'QUALITY',
                          value: 'Excellent',
                          valueColor: _HomePalette.positiveTeal,
                        ),
                      ),
                      SizedBox(
                        height: 26,
                        width: 1,
                        child: ColoredBox(color: _HomePalette.innerDivider),
                      ),
                      Expanded(
                        child: _SleepStatColumn(
                          title: 'DEEP PHASE',
                          value: '2h 10m',
                          valueColor: AppColors.darkText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: _HomePalette.softSurface,
            borderRadius: BorderRadius.circular(23),
            child: InkWell(
              onTap: onViewArchitectureTap,
              borderRadius: BorderRadius.circular(23),
              child: const SizedBox(
                width: double.infinity,
                height: 46,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        'View Sleep Staging Architecture',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: _HomePalette.sectionBlue,
                        ),
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: _HomePalette.sectionBlue,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SleepLegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _SleepLegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: _HomePalette.slateText,
          ),
        ),
      ],
    );
  }
}

class _SleepStatColumn extends StatelessWidget {
  final String title;
  final String value;
  final Color valueColor;

  const _SleepStatColumn({
    required this.title,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: _HomePalette.slateText,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhysicalCountermeasureCard extends StatelessWidget {
  const _PhysicalCountermeasureCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: _HomePalette.cardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: _HomePalette.smallIconCircleBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fitness_center,
                  size: 15,
                  color: _HomePalette.spo2Blue,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Physical\nCountermeasure',
                  style: TextStyle(
                    fontSize: 17.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _HomePalette.mintBadgeBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Completed',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _HomePalette.mintBadgeText,
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 38, top: 4),
            child: Text(
              'ARED \u2022 T2 Treadmill Protocol',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _HomePalette.slateText,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: _HomePalette.softSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: AppColors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.directions_run,
                    size: 20,
                    color: _HomePalette.activityIcon,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '45m Active',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkText,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Resistance & Cardio Session',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: _HomePalette.bodyText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '480',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkText,
                      ),
                    ),
                    Text(
                      'kcal',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _HomePalette.bodyText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClinicalCheckInButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ClinicalCheckInButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        color: _HomePalette.primaryActionBlue,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: _HomePalette.primaryActionShadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 21,
                  height: 21,
                  child: CustomPaint(
                    painter: _StethoscopePainter(color: AppColors.white),
                  ),
                ),
                SizedBox(width: 10),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Start Daily Clinical Check-in',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: AppColors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _HomeBottomNavBar({
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: _HomePalette.navShadow,
                  blurRadius: 16,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  Expanded(
                    child: _NavBarItem(
                      label: 'Home',
                      isSelected: selectedIndex == 0,
                      onTap: () => onTap(0),
                      iconBuilder: (color) =>
                          Icon(Icons.home_outlined, size: 23, color: color),
                    ),
                  ),
                  Expanded(
                    child: _NavBarItem(
                      label: 'Health',
                      isSelected: selectedIndex == 1,
                      onTap: () => onTap(1),
                      iconBuilder: (color) => SizedBox(
                        width: 22,
                        height: 22,
                        child: CustomPaint(
                          painter: _HeartCheckPainter(color: color),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _NavBarItem(
                      label: 'AI Insights',
                      isSelected: selectedIndex == 2,
                      onTap: () => onTap(2),
                      iconBuilder: (color) => SizedBox(
                        width: 22,
                        height: 22,
                        child: CustomPaint(
                          painter: _LightbulbRaysPainter(color: color),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _NavBarItem(
                      label: 'Profile',
                      isSelected: selectedIndex == 3,
                      onTap: () => onTap(3),
                      iconBuilder: (color) => Icon(
                        Icons.person_outline_rounded,
                        size: 23,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget Function(Color color) iconBuilder;

  const _NavBarItem({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.iconBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final Color color =
        isSelected ? _HomePalette.ringBlue : _HomePalette.navInactive;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          iconBuilder(color),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StethoscopePainter extends CustomPainter {
  final Color color;

  const _StethoscopePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.095
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path earTube = Path()
      ..moveTo(w * 0.25, h * 0.14)
      ..lineTo(w * 0.17, h * 0.14)
      ..lineTo(w * 0.17, h * 0.40)
      ..arcToPoint(
        Offset(w * 0.57, h * 0.40),
        radius: Radius.circular(w * 0.20),
        clockwise: false,
      )
      ..lineTo(w * 0.57, h * 0.14)
      ..lineTo(w * 0.49, h * 0.14);
    canvas.drawPath(earTube, paint);

    final Path lowerTube = Path()
      ..moveTo(w * 0.37, h * 0.60)
      ..lineTo(w * 0.37, h * 0.69)
      ..arcToPoint(
        Offset(w * 0.81, h * 0.69),
        radius: Radius.circular(w * 0.22),
        clockwise: false,
      )
      ..lineTo(w * 0.81, h * 0.54);
    canvas.drawPath(lowerTube, paint);

    canvas.drawCircle(Offset(w * 0.81, h * 0.43), w * 0.11, paint);
  }

  @override
  bool shouldRepaint(covariant _StethoscopePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _HeartCheckPainter extends CustomPainter {
  final Color color;

  const _HeartCheckPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path heart = Path()
      ..moveTo(w * 0.50, h * 0.84)
      ..cubicTo(w * 0.16, h * 0.62, w * 0.10, h * 0.36, w * 0.21, h * 0.22)
      ..cubicTo(w * 0.30, h * 0.12, w * 0.44, h * 0.15, w * 0.50, h * 0.27)
      ..cubicTo(w * 0.56, h * 0.15, w * 0.70, h * 0.12, w * 0.79, h * 0.22)
      ..cubicTo(w * 0.90, h * 0.36, w * 0.84, h * 0.62, w * 0.50, h * 0.84)
      ..close();
    canvas.drawPath(heart, paint);

    final Path check = Path()
      ..moveTo(w * 0.36, h * 0.49)
      ..lineTo(w * 0.46, h * 0.59)
      ..lineTo(w * 0.65, h * 0.39);
    canvas.drawPath(check, paint);
  }

  @override
  bool shouldRepaint(covariant _HeartCheckPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _LightbulbRaysPainter extends CustomPainter {
  final Color color;

  const _LightbulbRaysPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path bulb = Path()
      ..moveTo(w * 0.40, h * 0.72)
      ..lineTo(w * 0.40, h * 0.65)
      ..cubicTo(w * 0.31, h * 0.59, w * 0.28, h * 0.48, w * 0.32, h * 0.38)
      ..cubicTo(w * 0.36, h * 0.29, w * 0.43, h * 0.25, w * 0.50, h * 0.25)
      ..cubicTo(w * 0.57, h * 0.25, w * 0.64, h * 0.29, w * 0.68, h * 0.38)
      ..cubicTo(w * 0.72, h * 0.48, w * 0.69, h * 0.59, w * 0.60, h * 0.65)
      ..lineTo(w * 0.60, h * 0.72)
      ..close();
    canvas.drawPath(bulb, paint);

    canvas.drawLine(Offset(w * 0.41, h * 0.80), Offset(w * 0.59, h * 0.80), paint);
    canvas.drawLine(Offset(w * 0.44, h * 0.88), Offset(w * 0.56, h * 0.88), paint);
    canvas.drawLine(Offset(w * 0.50, h * 0.08), Offset(w * 0.50, h * 0.15), paint);
    canvas.drawLine(Offset(w * 0.22, h * 0.20), Offset(w * 0.27, h * 0.25), paint);
    canvas.drawLine(Offset(w * 0.78, h * 0.20), Offset(w * 0.73, h * 0.25), paint);
    canvas.drawLine(Offset(w * 0.12, h * 0.47), Offset(w * 0.19, h * 0.47), paint);
    canvas.drawLine(Offset(w * 0.88, h * 0.47), Offset(w * 0.81, h * 0.47), paint);
  }

  @override
  bool shouldRepaint(covariant _LightbulbRaysPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
