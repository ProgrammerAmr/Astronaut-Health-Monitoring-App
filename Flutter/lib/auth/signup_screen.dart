import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_widgets.dart';
import '../core/models/orbitcare_models.dart';
import '../core/state/session_controller.dart';
import '../routes/app_routes.dart';
import 'auth_status_banner.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool _isLoading = false;
  bool _checkedStartup = false;
  bool _showConfigAction = false;
  String? _errorMessage;
  String? _infoNotice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_checkedStartup) {
      _checkedStartup = true;
      SessionScope.maybeOf(context)?.ensureConfigLoaded();
    }
  }

  @override
  void dispose() {
    fullNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _openServerConfig() async {
    final sessionController = SessionScope.maybeOf(context);
    final saved = await Navigator.pushNamed(context, AppRoutes.serverConfig);
    if (saved == true && mounted && sessionController != null) {
      setState(() {
        _errorMessage = null;
        _showConfigAction = false;
        _infoNotice = 'Backend server set to ${sessionController.apiBaseUrl}';
      });
    }
  }

  Future<void> _handleSignup() async {
    final fullName = fullNameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (fullName.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your full name.';
        _showConfigAction = false;
      });
      return;
    }

    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() {
        _errorMessage = 'Please enter a valid email address.';
        _showConfigAction = false;
      });
      return;
    }

    if (password.length < 8) {
      setState(() {
        _errorMessage = 'Password must be at least 8 characters long.';
        _showConfigAction = false;
      });
      return;
    }

    if (password != confirmPassword) {
      setState(() {
        _errorMessage = 'Passwords do not match.';
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

    if (!sessionController.apiClient.isConfigured) {
      setState(() {
        _errorMessage =
            'Backend server URL is not configured yet. Configure and test your server connection before creating an account.';
        _showConfigAction = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoNotice = null;
      _showConfigAction = false;
    });

    try {
      await sessionController.apiClient.register(
        fullName: fullName,
        email: email,
        password: password,
      );
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        AppRoutes.otp,
        arguments: OtpRouteArgs(email: email, purpose: 'signup'),
      );
    } on OrbitCareApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _showConfigAction = e.isConfigError || e.isNetworkError;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to create account right now. Please try again.';
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
    final sessionController = SessionScope.maybeOf(context);
    final apiConfigured = sessionController?.apiClient.isConfigured ?? false;
    final activeBaseUrl = sessionController?.apiBaseUrl ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 20,
          ),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const Key('signup_configure_server_url_btn'),
                  onPressed: _isLoading ? null : _openServerConfig,
                  icon: Icon(
                    apiConfigured ? Icons.cloud_done_outlined : Icons.settings,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  label: Text(
                    apiConfigured ? 'Server Settings' : 'Configure Server URL',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const OrbitLogo(height: 85),
              const SizedBox(height: 16),
              const Text(
                'Create Account',
                style: TextStyle(
                  fontSize: 31,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Join OrbitCare to start monitoring astronaut\nhealth vitals and receive alerts.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.grey,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              if (!apiConfigured) ...[
                AuthStatusBanner(
                  isError: false,
                  message:
                      'Backend server URL is not configured yet. Configure and test your server connection before creating an account.',
                  action: TextButton.icon(
                    onPressed: _isLoading ? null : _openServerConfig,
                    icon: const Icon(Icons.dns_outlined, size: 18),
                    label: const Text('Configure Server URL'),
                  ),
                ),
                const SizedBox(height: 16),
              ] else if (activeBaseUrl.isNotEmpty && _infoNotice == null) ...[
                Text(
                  'Server: $activeBaseUrl',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.grey,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_infoNotice != null) ...[
                AuthStatusBanner(isError: false, message: _infoNotice!),
                const SizedBox(height: 16),
              ],
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
                      label: 'Full Name',
                      hint: 'Alex Vance',
                      icon: Icons.person_outline,
                      controller: fullNameController,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 20),
                    AppTextField(
                      label: 'Email Address',
                      hint: 'astronaut@orbitcare.local',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      controller: emailController,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 20),
                    AppTextField(
                      label: 'Password',
                      hint: 'Minimum 8 characters',
                      icon: Icons.lock_outline,
                      isPassword: true,
                      controller: passwordController,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 20),
                    AppTextField(
                      label: 'Confirm Password',
                      hint: 'Re-enter your password',
                      icon: Icons.lock_outline,
                      isPassword: true,
                      controller: confirmPasswordController,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 26),
                    PrimaryButton(
                      text: 'Create Account',
                      icon: Icons.arrow_forward,
                      isLoading: _isLoading,
                      onPressed: _isLoading ? null : _handleSignup,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Already have an account? ',
                    style: TextStyle(
                      color: AppColors.grey,
                      fontSize: 15,
                    ),
                  ),
                  GestureDetector(
                    onTap: _isLoading
                        ? null
                        : () {
                            Navigator.pushReplacementNamed(
                              context,
                              AppRoutes.login,
                            );
                          },
                    child: const Text(
                      'Log In',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
