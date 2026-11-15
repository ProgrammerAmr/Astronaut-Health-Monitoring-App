import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_widgets.dart';
import '../core/state/session_controller.dart';
import '../routes/app_routes.dart';

class SplashScreen extends StatefulWidget {
  final Duration splashDelay;

  const SplashScreen({
    super.key,
    this.splashDelay = const Duration(milliseconds: 600),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_bootstrapped) {
      _bootstrapped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _bootstrapSession();
      });
    }
  }

  Future<void> _bootstrapSession() async {
    final sessionController = SessionScope.maybeOf(context);
    final delayFuture = widget.splashDelay > Duration.zero
        ? Future<void>.delayed(widget.splashDelay)
        : Future<void>.value();

    bool restored = false;
    if (sessionController != null) {
      restored = await sessionController.restoreSession();
    }

    await delayFuture;
    if (!mounted) return;

    if (restored) {
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    } else if (sessionController?.sessionNotice != null) {
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.onboarding);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const OrbitLogo(height: 110),
                const SizedBox(height: 22),
                const Text(
                  'OrbitCare',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'ASTRONAUT HEALTH MONITORING',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w500,
                    color: AppColors.grey,
                  ),
                ),
                const SizedBox(height: 28),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
