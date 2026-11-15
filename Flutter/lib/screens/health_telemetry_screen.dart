import 'package:flutter/material.dart';

import '../constants/app_assets.dart';
import '../constants/app_colors.dart';

/// Colour values sampled from the reference design.
const Color _lavender = Color(0xFFF0F2FF);
const Color _chipBlue = Color(0xFFE1ECFF);
const Color _blue = Color(0xFF0B57D0);
const Color _deepBlue = Color(0xFF0755A8);
const Color _mutedBlue = Color(0xFF3E5B85);
const Color _ink = AppColors.darkText;
const Color _labelInk = Color(0xFF3B4453);
const Color _grey = Color(0xFF5F6878);
const Color _navGrey = Color(0xFF98A0AE);
const Color _teal = AppColors.teal;
const Color _dotBlue = AppColors.primary;

const List<BoxShadow> _cardShadows = <BoxShadow>[
  BoxShadow(
    color: Color(0x14071D49),
    blurRadius: 12,
    offset: Offset(0, 3),
  ),
];

const List<BoxShadow> _badgeShadows = <BoxShadow>[
  BoxShadow(
    color: Color(0x1A071D49),
    blurRadius: 8,
    offset: Offset(0, 2),
  ),
];

BoxDecoration _whiteCard({double radius = 18}) => BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: _cardShadows,
    );

/// "Health Telemetry" screen (the active "Health" tab of the reference).
class HealthTelemetryScreen extends StatelessWidget {
  const HealthTelemetryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: <Widget>[
          // Device chrome shown at the very top of the reference.
          const _DeviceStatusBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _ScreenHeader(),
                  const SizedBox(height: 8),
                  const _BodyMapCard(),
                  const SizedBox(height: 12),
                  const _VitalsHeading(),
                  const SizedBox(height: 12),
                  const _HeartRateCard(),
                  const SizedBox(height: 8),
                  const _BloodOxygenCard(),
                  const SizedBox(height: 8),
                  const Row(
                    children: <Widget>[
                      Expanded(child: _CoreTempCard()),
                      SizedBox(width: 8),
                      Expanded(child: _BreathingCard()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const _BloodPressureCard(),
                  const SizedBox(height: 10),
                  const _ZeroGCountermeasureCard(),
                  const SizedBox(height: 12),
                  const _SleepModePanel(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          const _BottomNavBar(),
          const _HomeIndicator(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Device chrome (status bar / gesture bar) present in the reference image
// ---------------------------------------------------------------------------

class _DeviceStatusBar extends StatelessWidget {
  const _DeviceStatusBar();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 56,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 20,
            top: 20,
            child: Text(
              '9:30',
              style: TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Align(
            alignment: Alignment(0, 0.15),
            child: SizedBox(
              width: 22,
              height: 22,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFF101014),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Positioned(
            right: 22,
            top: 21,
            child: SizedBox(
              width: 48,
              height: 16,
              child: CustomPaint(painter: _StatusBarIconsPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeIndicator extends StatelessWidget {
  const _HomeIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      alignment: Alignment.center,
      child: Container(
        width: 144,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(0xFF000000),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _ScreenHeader extends StatelessWidget {
  const _ScreenHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  color: _ink,
                  size: 20,
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: _lavender,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.notifications_none,
                      color: _ink,
                      size: 19,
                    ),
                  ),
                  Positioned(
                    right: 3,
                    top: 2,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE62626),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Text(
          'Health Telemetry',
          style: TextStyle(
            color: _ink,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Mission Sol 142 • Crew Monitoring',
          style: TextStyle(
            color: _grey,
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Body map card
// ---------------------------------------------------------------------------

class _BodyMapCard extends StatelessWidget {
  const _BodyMapCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _whiteCard(radius: 20),
      padding: const EdgeInsets.only(left: 13, right: 13, top: 16),
      child: Column(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: AspectRatio(
              aspectRatio: 298 / 372,
              child: DecoratedBox(
                decoration: const BoxDecoration(color: _lavender),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    // The reference body map is a 298 x 372 design area. All
                    // children are positioned in those design units so the
                    // illustration and its labels scale together.
                    final double u = constraints.maxWidth / 298;
                    double d(double v) => v * u;
                    return Stack(
                      clipBehavior: Clip.hardEdge,
                      children: <Widget>[
                        Positioned(
                          left: d(16),
                          top: d(-18),
                          width: d(267),
                          height: d(404),
                          child: Image.asset(
                            AppAssets.bodyAnatomy,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                        // Neuro / Nominal callout.
                        Positioned(
                          left: d(205),
                          top: d(47),
                          width: d(92),
                          height: d(68),
                          child: _BodyCallout(
                            scale: u,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Neuro •',
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: d(12),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: d(6)),
                                Text(
                                  'Nominal',
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: d(12),
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        _BioNode(
                          left: d(180),
                          top: d(69),
                          size: d(20),
                          color: _dotBlue,
                          inner: d(6),
                        ),
                        // Heart rate callout.
                        Positioned(
                          left: d(66),
                          top: d(141),
                          width: d(69),
                          height: d(33),
                          child: _BodyCallout(
                            scale: u,
                            child: Center(
                              child: Text(
                                '68 BPM',
                                style: TextStyle(
                                  color: _blue,
                                  fontSize: d(11),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _BioNode(
                          left: d(136),
                          top: d(143),
                          size: d(28),
                          color: const Color(0xFF9EC6F5),
                          ringColor: _dotBlue,
                          ringSize: d(20),
                          inner: d(8),
                        ),
                        _BioNode(
                          left: d(143),
                          top: d(191),
                          size: d(12),
                          color: _teal,
                          inner: d(4),
                        ),
                        // SpO2 callout.
                        Positioned(
                          left: d(166),
                          top: d(181),
                          width: d(92),
                          height: d(33),
                          child: _BodyCallout(
                            scale: u,
                            child: Center(
                              child: Text(
                                'SpO2 99%',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: d(12),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Blood pressure callout.
                        Positioned(
                          left: d(85),
                          top: d(256),
                          width: d(94),
                          height: d(34),
                          child: _BodyCallout(
                            scale: u,
                            child: Center(
                              child: Text(
                                '118/76 mmHg',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: d(12),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _BioNode(
                          left: d(184),
                          top: d(259),
                          size: d(16),
                          color: _mutedBlue,
                          inner: d(6),
                        ),
                        Positioned(
                          left: d(201),
                          top: d(348),
                          child: Text(
                            'Z-AXIS 1.04G',
                            style: TextStyle(
                              color: _grey,
                              fontSize: d(11),
                              letterSpacing: d(1),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: _dotBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '4 bio-nodes active',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _chipBlue,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Continuous Live',
                      style: TextStyle(
                        color: _blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
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
}

class _BodyCallout extends StatelessWidget {
  final Widget child;
  final double scale;

  const _BodyCallout({
    required this.child,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 6 * scale,
        vertical: 4 * scale,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16 * scale),
        boxShadow: _badgeShadows,
      ),
      child: FittedBox(fit: BoxFit.scaleDown, child: child),
    );
  }
}

class _BioNode extends StatelessWidget {
  final double left;
  final double top;
  final double size;
  final Color color;
  final double inner;
  final Color? ringColor;
  final double? ringSize;

  const _BioNode({
    required this.left,
    required this.top,
    required this.size,
    required this.color,
    required this.inner,
    this.ringColor,
    this.ringSize,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: ringColor != null
            ? Container(
                width: ringSize,
                height: ringSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ringColor,
                  shape: BoxShape.circle,
                ),
                child: Container(
                  width: inner,
                  height: inner,
                  decoration: const BoxDecoration(
                    color: AppColors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : Container(
                width: inner,
                height: inner,
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vitals & Physiology
// ---------------------------------------------------------------------------

class _VitalsHeading extends StatelessWidget {
  const _VitalsHeading();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(
          'Vitals & Physiology',
          style: TextStyle(
            color: _ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: 3),
          child: Text(
            'SYNC: 25 AGO',
            style: TextStyle(
              color: _grey,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _VitalIconSquare extends StatelessWidget {
  final IconData icon;

  const _VitalIconSquare({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 43,
      height: 43,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _chipBlue,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: _blue, size: 22),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final bool bold;

  const _StatusChip(this.text, {this.bold = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 21,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _chipBlue,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: _blue,
          fontSize: 11,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

const TextStyle _vitalLabelStyle = TextStyle(
  color: _labelInk,
  fontSize: 11,
  fontWeight: FontWeight.w500,
  letterSpacing: 1.1,
);

const TextStyle _vitalValueStyle = TextStyle(
  color: _ink,
  fontSize: 26,
  fontWeight: FontWeight.w700,
  height: 1.05,
);

const TextStyle _vitalUnitStyle = TextStyle(
  color: _grey,
  fontSize: 13,
  fontWeight: FontWeight.w400,
);

class _HeartRateCard extends StatelessWidget {
  const _HeartRateCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 65,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: _whiteCard(),
      child: Row(
        children: <Widget>[
          const _VitalIconSquare(icon: Icons.favorite_border),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('HEART RATE', style: _vitalLabelStyle),
                SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text('68', style: _vitalValueStyle),
                    SizedBox(width: 4),
                    Text('BPM', style: _vitalUnitStyle),
                  ],
                ),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              const _StatusChip('Resting Normal'),
              const SizedBox(height: 8),
              SizedBox(
                width: 79,
                height: 24,
                child: CustomPaint(painter: _EcgPainter()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BloodOxygenCard extends StatelessWidget {
  const _BloodOxygenCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: _whiteCard(),
      child: Row(
        children: <Widget>[
          const _VitalIconSquare(icon: Icons.air),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('BLOOD OXYGEN', style: _vitalLabelStyle),
                SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text('99', style: _vitalValueStyle),
                    SizedBox(width: 4),
                    Text('%SpO2', style: _vitalUnitStyle),
                  ],
                ),
              ],
            ),
          ),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              _StatusChip('Optimal', bold: false),
              SizedBox(height: 8),
              Text(
                'Steady trend',
                style: TextStyle(
                  color: _grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallVitalCard extends StatelessWidget {
  final String label;
  final Widget value;
  final Widget icon;
  final String sensor;

  const _SmallVitalCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.sensor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 81,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: _whiteCard(radius: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(label, style: _vitalLabelStyle),
              icon,
            ],
          ),
          value,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Flexible(
                child: Text(
                  sensor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _labelInk,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: _dotBlue,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoreTempCard extends StatelessWidget {
  const _CoreTempCard();

  @override
  Widget build(BuildContext context) {
    return const _SmallVitalCard(
      label: 'CORE TEMP',
      icon: Icon(Icons.thermostat, color: _mutedBlue, size: 14),
      sensor: 'Dermal Probe',
      value: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('36.6', style: _vitalValueStyle),
          Padding(
            padding: EdgeInsets.only(top: 4, left: 1),
            child: Text(
              '°C',
              style: TextStyle(
                color: _grey,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreathingCard extends StatelessWidget {
  const _BreathingCard();

  @override
  Widget build(BuildContext context) {
    return const _SmallVitalCard(
      label: 'BREATHING',
      icon: SizedBox(
        width: 14,
        height: 16,
        child: CustomPaint(painter: _LungsPainter()),
      ),
      sensor: 'Acoustic Sensor',
      value: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Text('14', style: _vitalValueStyle),
          SizedBox(width: 3),
          Text('br/min', style: _vitalUnitStyle),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Blood pressure card
// ---------------------------------------------------------------------------

class _BloodPressureCard extends StatelessWidget {
  const _BloodPressureCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 106,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: _whiteCard(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(
                width: 14,
                height: 14,
                child: CustomPaint(painter: _GaugePainter()),
              ),
              const SizedBox(width: 8),
              const Text('BLOOD PRESSURE', style: _vitalLabelStyle),
              const Spacer(),
              const Text(
                'MAP 90',
                style: TextStyle(
                  color: _blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              const Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text('118', style: _vitalValueStyle),
                  Text(
                    ' /76',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  Text(' mmHg', style: _vitalUnitStyle),
                ],
              ),
              const Spacer(),
              const _StatusChip('Nominal'),
            ],
          ),
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: _lavender,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.shield_outlined,
                  color: _blue,
                  size: 14,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Microgravity fluid shift countermeasure active',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _labelInk,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Zero-G countermeasure card
// ---------------------------------------------------------------------------

class _ZeroGCountermeasureCard extends StatelessWidget {
  const _ZeroGCountermeasureCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: _whiteCard(),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _chipBlue,
              shape: BoxShape.circle,
            ),
            child: Transform.rotate(
              angle: 0.7,
              child: const Icon(
                Icons.fitness_center,
                color: _mutedBlue,
                size: 19,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Zero-G Countermeasure',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '45m Cycle • ARED & T2 Complete',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _grey,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: _chipBlue,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: _blue, size: 17),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sleep mode panel
// ---------------------------------------------------------------------------

class _SleepModePanel extends StatelessWidget {
  const _SleepModePanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[AppColors.white, Color(0xFFF1F6FF)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: _cardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _chipBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CustomPaint(painter: _CrescentPainter()),
                ),
                const SizedBox(width: 7),
                const Text(
                  'CIRCADIAN SYNC',
                  style: TextStyle(
                    color: _blue,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Sleep Mode',
            style: TextStyle(
              color: _ink,
              fontSize: 25,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Time to recharge for Orbit 413',
            style: TextStyle(
              color: _grey,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: <Widget>[
              Expanded(
                child: _SleepStat(
                  label: 'Target Duration',
                  value: '7h 45m',
                  valueColor: _ink,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _SleepStat(
                  label: 'Sleep Quality Index',
                  value: 'Excellent',
                  valueColor: _blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: _deepBlue,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x330755A8),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CustomPaint(painter: _CrescentPainter(color: AppColors.white)),
                ),
                SizedBox(width: 12),
                Text(
                  'Enter Sleep Mode',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(width: 14),
                Icon(Icons.arrow_forward, color: AppColors.white, size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SleepStat extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _SleepStat({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 63,
      padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
      decoration: BoxDecoration(
        color: _lavender,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _grey,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom navigation
// ---------------------------------------------------------------------------

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 74,
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x0F071D49),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          _NavItem(icon: Icons.home_outlined, label: 'Home'),
          _NavItem(icon: Icons.favorite_border, label: 'Health', active: true, health: true),
          _NavItem(icon: Icons.lightbulb_outline, label: 'AI Insights'),
          _NavItem(icon: Icons.person_outline, label: 'Profile'),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool health;

  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
    this.health = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = active ? _blue : _navGrey;
    return SizedBox(
      width: 76,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 23,
            height: 23,
            child: health
                ? Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Icon(icon, color: color, size: 23),
                      Icon(Icons.check, color: color, size: 11),
                    ],
                  )
                : Icon(icon, color: color, size: 23),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small vector drawings used by the reference (no external assets required)
// ---------------------------------------------------------------------------

class _EcgPainter extends CustomPainter {
  const _EcgPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = _deepBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final Path path = Path();
    final double y = size.height * 0.6;
    path.moveTo(0, y);
    path.lineTo(size.width * 0.34, y);
    path.lineTo(size.width * 0.40, y - size.height * 0.08);
    path.lineTo(size.width * 0.47, size.height * 0.12);
    path.lineTo(size.width * 0.54, size.height * 0.92);
    path.lineTo(size.width * 0.60, y);
    path.lineTo(size.width, y);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = _blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round;

    final Rect rect = Rect.fromLTWH(
      size.width * 0.10,
      size.height * 0.10,
      size.width * 0.80,
      size.height * 0.80,
    );
    canvas.drawArc(rect, 0.55, 5.20, false, paint);
    canvas.drawLine(
      Offset(size.width * 0.50, size.height * 0.55),
      Offset(size.width * 0.72, size.height * 0.28),
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.50, size.height * 0.55),
      size.width * 0.06,
      paint..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CrescentPainter extends CustomPainter {
  final Color color;

  const _CrescentPainter({this.color = _mutedBlue});

  @override
  void paint(Canvas canvas, Size size) {
    final Path outer = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width * 0.48, size.height * 0.50),
          radius: size.width * 0.40,
        ),
      );
    final Path inner = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width * 0.68, size.height * 0.40),
          radius: size.width * 0.36,
        ),
      );
    final Path crescent = Path.combine(PathOperation.difference, outer, inner);
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(crescent, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LungsPainter extends CustomPainter {
  const _LungsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Paint paint = Paint()
      ..color = _mutedBlue
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Trachea and bronchi.
    canvas.drawLine(Offset(w * 0.50, h * 0.02), Offset(w * 0.50, h * 0.32), paint);
    canvas.drawLine(Offset(w * 0.50, h * 0.30), Offset(w * 0.34, h * 0.45), paint);
    canvas.drawLine(Offset(w * 0.50, h * 0.30), Offset(w * 0.66, h * 0.45), paint);

    // Left lobe (mirrored for the right lobe).
    final Path lobe = Path();
    lobe.moveTo(w * 0.44, h * 0.30);
    lobe.quadraticBezierTo(w * 0.12, h * 0.28, w * 0.11, h * 0.62);
    lobe.quadraticBezierTo(w * 0.10, h * 0.95, w * 0.42, h * 0.95);
    lobe.quadraticBezierTo(w * 0.48, h * 0.70, w * 0.44, h * 0.42);
    lobe.lineTo(w * 0.44, h * 0.30);
    canvas.drawPath(lobe, paint);

    canvas.save();
    canvas.translate(w, 0);
    canvas.scale(-1, 1);
    canvas.drawPath(lobe, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StatusBarIconsPainter extends CustomPainter {
  const _StatusBarIconsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint grey = Paint()..color = const Color(0xFFD3D3D8);
    final Paint dark = Paint()..color = const Color(0xFF16161A);

    // Wi-Fi sector.
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(14, 2), radius: 12),
      1.57,
      1.57,
      true,
      grey,
    );

    // Cellular signal triangle.
    final Path signal = Path()
      ..moveTo(18, 15)
      ..lineTo(32, 2)
      ..lineTo(32, 15)
      ..close();
    canvas.drawPath(signal, dark);

    // Battery: light upper half, dark lower half and a small terminal.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(37, 2, 10, 14),
        const Radius.circular(2),
      ),
      grey,
    );
    canvas.drawRect(const Rect.fromLTWH(38, 8, 8, 7), dark);
    canvas.drawRect(const Rect.fromLTWH(40, 0, 4, 2), grey);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
