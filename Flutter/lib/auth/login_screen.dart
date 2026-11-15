import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_widgets.dart';
import '../core/models/orbitcare_models.dart';
import '../core/state/session_controller.dart';
import '../routes/app_routes.dart';
import 'auth_status_banner.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isSendingVerifyOtp = false;
  bool _showVerifyEmailAction = false;
  bool _showConfigAction = false;
  String? _errorMessage;
  String? _infoNotice;
  bool _checkedStartup = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_checkedStartup) {
      _checkedStartup = true;
      final sessionController = SessionScope.maybeOf(context);
      final notice = sessionController?.consumeNotice();
      if (notice != null && notice.trim().isNotEmpty) {
        _infoNotice = notice;
      }
      sessionController?.ensureConfigLoaded();
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
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

  Future<void> _handleEnterDemoMode() async {
    final sessionController = SessionScope.maybeOf(context);
    if (sessionController == null || _isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await sessionController.enterDemoMode();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.home,
        (_) => false,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to open Demo Mode right now. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleLogin() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (!_isValidEmail(email)) {
      setState(() {
        _errorMessage = 'Please enter a valid email address.';
        _showVerifyEmailAction = false;
        _showConfigAction = false;
      });
      return;
    }

    if (password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your password.';
        _showVerifyEmailAction = false;
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
            'Backend server URL is not configured yet. Configure your server connection, or tap "Continue as Demo User" to explore OrbitCare offline.';
        _showConfigAction = true;
        _showVerifyEmailAction = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoNotice = null;
      _showVerifyEmailAction = false;
      _showConfigAction = false;
    });

    try {
      await sessionController.login(email: email, password: password);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.home,
        (_) => false,
      );
    } on OrbitCareApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _showVerifyEmailAction = e.isUnverified;
        _showConfigAction = e.isConfigError || e.isNetworkError;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to sign in right now. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendVerificationOtpAndOpen() async {
    final email = emailController.text.trim();
    final sessionController = SessionScope.maybeOf(context);
    if (sessionController == null || !_isValidEmail(email)) return;

    await sessionController.ensureConfigLoaded();
    if (!mounted) return;

    setState(() {
      _isSendingVerifyOtp = true;
    });

    try {
      await sessionController.productionApiClient.sendOtp(
        email: email,
        purpose: 'signup',
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
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSendingVerifyOtp = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionController = SessionScope.maybeOf(context);
    final apiConfigured = sessionController?.isProductionApiConfigured ?? false;
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
                  key: const Key('configure_server_url_btn'),
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
              const OrbitLogo(height: 95),
              const SizedBox(height: 18),
              const Text(
                'Welcome Back',
                style: TextStyle(
                  fontSize: 31,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Sign in to continue monitoring astronaut\nhealth metrics and vitals.',
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
                      'Backend server URL is not configured yet. Configure and test your server before signing in.',
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
                AuthStatusBanner(
                  isError: false,
                  message: _infoNotice!,
                ),
                const SizedBox(height: 16),
              ],
              if (_errorMessage != null) ...[
                AuthStatusBanner(
                  isError: true,
                  message: _errorMessage!,
                  action: _showVerifyEmailAction
                      ? TextButton.icon(
                          onPressed: _isSendingVerifyOtp
                              ? null
                              : _sendVerificationOtpAndOpen,
                          icon: const Icon(
                            Icons.verified_user_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _isSendingVerifyOtp
                                ? 'Sending OTP...'
                                : 'Send Verification OTP',
                          ),
                        )
                      : (_showConfigAction
                          ? TextButton.icon(
                              onPressed:
                                  _isLoading ? null : _openServerConfig,
                              icon: const Icon(Icons.settings, size: 18),
                              label: const Text('Configure Server URL'),
                            )
                          : null),
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
                    const SizedBox(height: 24),
                    AppTextField(
                      label: 'Password',
                      hint: 'Enter your password',
                      icon: Icons.lock_outline,
                      isPassword: true,
                      controller: passwordController,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.pushNamed(
                                  context,
                                  AppRoutes.forgotPassword,
                                );
                              },
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrimaryButton(
                      text: 'Log In',
                      icon: Icons.arrow_forward,
                      isLoading: _isLoading,
                      onPressed: _isLoading ? null : _handleLogin,
                    ),
                    const SizedBox(height: 14),
                    const Row(
                      children: [
                        Expanded(child: Divider(color: AppColors.border)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'OR',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.grey,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: AppColors.border)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        key: const Key('continue_demo_user_btn'),
                        onPressed: _isLoading ? null : _handleEnterDemoMode,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.navy,
                          side: const BorderSide(
                            color: AppColors.primary,
                            width: 1.4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        icon: const Icon(
                          Icons.science_outlined,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        label: const Text(
                          'Continue as Demo User',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Offline Demo Mode • Uses local synthetic astronaut data (no backend required)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(
                      color: AppColors.grey,
                      fontSize: 15,
                    ),
                  ),
                  GestureDetector(
                    onTap: _isLoading
                        ? null
                        : () {
                            Navigator.pushNamed(context, AppRoutes.signup);
                          },
                    child: const Text(
                      'Sign Up',
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
