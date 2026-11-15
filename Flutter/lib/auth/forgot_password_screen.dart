import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_widgets.dart';
import '../core/models/orbitcare_models.dart';
import '../core/state/session_controller.dart';
import '../routes/app_routes.dart';
import 'auth_status_banner.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController emailController = TextEditingController();
  bool _isLoading = false;
  bool _showConfigAction = false;
  String? _errorMessage;

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Future<void> _openServerConfig() async {
    final saved = await Navigator.pushNamed(context, AppRoutes.serverConfig);
    if (saved == true && mounted) {
      setState(() {
        _errorMessage = null;
        _showConfigAction = false;
      });
    }
  }

  Future<void> _handleSendCode() async {
    final email = emailController.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() {
        _errorMessage = 'Please enter a valid email address.';
        _showConfigAction = false;
      });
      return;
    }

    final sessionController = SessionScope.maybeOf(context);
    if (sessionController == null) {
      setState(() {
        _errorMessage = 'Session service is unavailable.';
      });
      return;
    }

    await sessionController.ensureConfigLoaded();
    if (!mounted) return;

    if (!sessionController.isProductionApiConfigured) {
      setState(() {
        _errorMessage =
            'Backend server URL is not configured yet. Configure your server URL before requesting a reset code.';
        _showConfigAction = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _showConfigAction = false;
    });

    try {
      await sessionController.productionApiClient.sendOtp(
        email: email,
        purpose: 'reset_password',
      );
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        AppRoutes.otp,
        arguments: OtpRouteArgs(email: email, purpose: 'reset_password'),
      );
    } on OrbitCareApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to send reset code. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            Navigator.pop(context);
                          },
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: AppColors.navy,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'OrbitCare',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Center(child: OrbitLogo(height: 85)),
              const SizedBox(height: 26),
              const Center(
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'Enter the email address associated with your\naccount and we will send a 6-digit verification code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.grey,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 26),
              if (_errorMessage != null) ...[
                AuthStatusBanner(
                  isError: true,
                  message: _errorMessage!,
                  action: _showConfigAction
                      ? TextButton.icon(
                          onPressed: _isLoading ? null : _openServerConfig,
                          icon: const Icon(Icons.settings, size: 18),
                          label: const Text('Configure Server URL'),
                        )
                      : null,
                ),
                const SizedBox(height: 16),
              ],
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.navy.withValues(alpha: 0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    AppTextField(
                      label: 'Email Address',
                      hint: 'astronaut@orbitcare.local',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      controller: emailController,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 26),
                    PrimaryButton(
                      text: 'Send Verification Code',
                      icon: Icons.arrow_forward,
                      isLoading: _isLoading,
                      onPressed: _isLoading ? null : _handleSendCode,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Center(
                child: GestureDetector(
                  onTap: _isLoading
                      ? null
                      : () {
                          Navigator.pushReplacementNamed(
                            context,
                            AppRoutes.login,
                          );
                        },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_back,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Back to Log In',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
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
