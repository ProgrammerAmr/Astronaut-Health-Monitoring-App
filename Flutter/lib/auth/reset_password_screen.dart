import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_widgets.dart';
import '../core/models/orbitcare_models.dart';
import '../core/state/session_controller.dart';
import '../routes/app_routes.dart';
import 'auth_status_banner.dart';

class ResetPasswordScreen extends StatefulWidget {
  final ResetPasswordRouteArgs? initialArgs;

  const ResetPasswordScreen({
    super.key,
    this.initialArgs,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  ResetPasswordRouteArgs? _resolveArgs(BuildContext context) {
    if (widget.initialArgs != null) return widget.initialArgs!;
    final raw = ModalRoute.of(context)?.settings.arguments;
    if (raw is ResetPasswordRouteArgs) return raw;
    return null;
  }

  @override
  void dispose() {
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleReset(ResetPasswordRouteArgs? args) async {
    final newPassword = passwordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (args == null || args.email.isEmpty || args.otp.isEmpty) {
      setState(() {
        _errorMessage =
            'Reset session details are missing. Please restart Forgot Password.';
      });
      return;
    }

    if (newPassword.length < 8) {
      setState(() {
        _errorMessage = 'Password must be at least 8 characters long.';
      });
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() {
        _errorMessage = 'Passwords do not match.';
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

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await sessionController.apiClient.resetPassword(
        email: args.email,
        otp: args.otp,
        newPassword: newPassword,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset successfully. Please sign in.'),
        ),
      );
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.login,
        (_) => false,
      );
    } on OrbitCareApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to reset password right now. Please try again.';
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
    final args = _resolveArgs(context);

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
              const SizedBox(height: 18),
              const Center(child: OrbitLogo(height: 85)),
              const SizedBox(height: 22),
              const Center(
                child: Text(
                  'Reset Password',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  args != null
                      ? 'Create a new password for ${args.email}.'
                      : 'Create a strong new password for your\nOrbitCare account.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.grey,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null) ...[
                AuthStatusBanner(isError: true, message: _errorMessage!),
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
                      label: 'New Password',
                      hint: 'Minimum 8 characters',
                      icon: Icons.lock_outline,
                      isPassword: true,
                      controller: passwordController,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 22),
                    AppTextField(
                      label: 'Confirm Password',
                      hint: 'Re-enter new password',
                      icon: Icons.lock_outline,
                      isPassword: true,
                      controller: confirmPasswordController,
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 28),
                    PrimaryButton(
                      text: 'Update Password',
                      icon: Icons.check_circle_outline,
                      isLoading: _isLoading,
                      onPressed:
                          _isLoading ? null : () => _handleReset(args),
                    ),
                  ],
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
