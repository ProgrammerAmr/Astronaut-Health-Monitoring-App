
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_assets.dart';
import '../constants/app_widgets.dart';
import '../routes/app_routes.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() =>
      _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController controller = PageController();

  int currentPage = 0;

  final List<Map<String, dynamic>> pages = [
    {
      'image': AppAssets.astronaut,
      'title': 'Your Health,\nBeyond Earth.',
      'label': 'MISSION PHASE: PRE-FLIGHT',
      'description': 'TELEM-SYNC ACTIVE',
      'button': 'Continue to Vitals Setup',
    },
    {
      'image': AppAssets.vitals,
      'title': 'Monitor Every\nVital Sign.',
      'label': 'CONTINUOUS TELEMETRY',
      'description': 'CARDIOPULMONARY ARRAY',
      'button': 'Next',
    },
    {
      'image': AppAssets.aiInsights,
      'title': 'Smart Health Insights',
      'label': 'TELEMETRY ANALYSIS',
      'description': 'AUTONOMOUS MODE',
      'button': 'Get Started',
    },
  ];

  void nextPage() {
    if (currentPage < 2) {
      controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.login,
      );
    }
  }

  void previousPage() {
    if (currentPage > 0) {
      controller.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 14,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'OrbitCare',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(
                        context,
                        AppRoutes.login,
                      );
                    },
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: PageView.builder(
                controller: controller,
                itemCount: pages.length,
                onPageChanged: (index) {
                  setState(() {
                    currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  final page = pages[index];

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),

                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.teal,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              page['description'],
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                                color: AppColors.navy,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        Expanded(
                          flex: 6,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.asset(
                              page['image'],
                              width: double.infinity,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.monitor_heart_outlined,
                              color: AppColors.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              page['label'],
                              style: const TextStyle(
                                color: AppColors.navy,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 22),

                        Text(
                          page['title'],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.darkText,
                            fontSize: 29,
                            height: 1.35,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const Spacer(),

                        if (index == 0)
                          const Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              _VitalValue(
                                title: 'PULSE RATE',
                                value: '68 bpm',
                                icon: Icons.favorite,
                              ),
                              SizedBox(width: 25),
                              _VitalValue(
                                title: 'SpO2',
                                value: '99%',
                                icon: Icons.air,
                              ),
                            ],
                          ),

                        if (index == 1)
                          const Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceAround,
                            children: [
                              _VitalValue(
                                title: 'RESP RATE',
                                value: '14 br/min',
                                icon: Icons.air,
                              ),
                              _VitalValue(
                                title: 'ARTERIAL BP',
                                value: '120/80 mmHg',
                                icon: Icons.monitor_heart,
                              ),
                            ],
                          ),

                        if (index == 2)
                          const Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceAround,
                            children: [
                              _VitalValue(
                                title: 'CARDIO STRAIN',
                                value: '-4.2%',
                                icon: Icons.show_chart,
                              ),
                              _VitalValue(
                                title: 'UPLINK',
                                value: '1.28 Gbps',
                                icon: Icons.cloud_done,
                              ),
                            ],
                          ),

                        const Spacer(),

                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: List.generate(
                            3,
                            (dotIndex) => AnimatedContainer(
                              duration: const Duration(
                                milliseconds: 250,
                              ),
                              margin: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              width: currentPage == dotIndex
                                  ? 27
                                  : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: currentPage == dotIndex
                                    ? AppColors.primary
                                    : AppColors.border,
                                borderRadius:
                                    BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 15),

                        if (index == 1)
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: previousPage,
                                icon: const Icon(
                                  Icons.arrow_back,
                                  color: AppColors.navy,
                                ),
                                label: const Text(
                                  'Back',
                                  style: TextStyle(
                                    color: AppColors.navy,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: PrimaryButton(
                                  text: page['button'],
                                  icon: Icons.arrow_forward,
                                  onPressed: nextPage,
                                ),
                              ),
                            ],
                          )
                        else
                          PrimaryButton(
                            text: page['button'],
                            icon: Icons.arrow_forward,
                            onPressed: nextPage,
                          ),

                        const SizedBox(height: 20),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VitalValue extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _VitalValue({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          color: AppColors.primary,
          size: 21,
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.navy,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
