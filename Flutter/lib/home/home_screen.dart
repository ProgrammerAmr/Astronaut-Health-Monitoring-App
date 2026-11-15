import 'package:flutter/material.dart';

import '../cognitive_state/models/cognitive_state_models.dart';
import '../cognitive_state/services/cognitive_state_api_client.dart';
import '../cognitive_state/widgets/cognitive_state_research_card.dart';
import '../constants/app_colors.dart';

class HomeScreen extends StatelessWidget {
  final CognitiveStateApiClient? csmApiClient;
  final String? authToken;
  final CognitiveStateUiSnapshot? initialCsmSnapshot;
  final bool autoFetchCsmStatus;

  const HomeScreen({
    super.key,
    this.csmApiClient,
    this.authToken,
    this.initialCsmSnapshot,
    this.autoFetchCsmStatus = true,
  });

  @override
  Widget build(BuildContext context) {
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
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Crew Research Dashboard',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Non-diagnostic research workspace for DEC-001 Cognitive State Monitoring.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.grey,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              CognitiveStateResearchCard(
                apiClient: csmApiClient,
                authToken: authToken,
                initialSnapshot: initialCsmSnapshot,
                autoFetchStatus: autoFetchCsmStatus,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
