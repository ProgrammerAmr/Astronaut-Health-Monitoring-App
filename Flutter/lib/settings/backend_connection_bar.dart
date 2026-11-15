import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../core/config/api_config.dart';
import '../core/config/backend_config.dart';
import '../routes/app_routes.dart';

/// Slim, always-visible indicator of the backend the app is talking to.
///
/// Tapping it opens the connection settings screen where the URL can be
/// tested and changed at runtime — the fastest way to diagnose
/// "the app cannot reach the backend / login does not work".
class BackendConnectionBar extends StatelessWidget {
  final BackendConfig? config;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const BackendConnectionBar({
    super.key,
    this.config,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
  });

  @override
  Widget build(BuildContext context) {
    final backendConfig = config ?? BackendConfig.instance;

    return ListenableBuilder(
      listenable: backendConfig,
      builder: (context, _) {
        final url = backendConfig.effectiveBaseUrl;
        final isOverride =
            backendConfig.source == ApiBaseUrlSource.runtimeOverride;

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap ??
              () {
                Navigator.pushNamed(context, AppRoutes.connectionSettings);
              },
          child: Container(
            width: double.infinity,
            padding: padding,
            decoration: BoxDecoration(
              color: AppColors.lightBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(
                  isOverride ? Icons.tune : Icons.dns_outlined,
                  size: 17,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BACKEND',
                        style: TextStyle(
                          color: AppColors.grey,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        url.isEmpty ? 'not configured' : url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: AppColors.grey,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
