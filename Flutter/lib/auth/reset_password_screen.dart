
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_widgets.dart';
import '../routes/app_routes.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState
    extends State<ResetPasswordScreen> {
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();

  bool get hasLength => passwordController.text.length >= 8;
  bool get hasUppercase =>
      RegExp(r'[A-Z]').hasMatch(passwordController.text);
  bool get hasNumber =>
      RegExp(r'[0-9]').hasMatch(passwordController.text);
  bool get hasSymbol =>
      RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(
        passwordController.text,
      );

  @override
  void dispose() {
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  Widget requirement(String text, bool valid) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            valid ? Icons.check_circle : Icons.circle_outlined,
            color: valid ? AppColors.cyan : AppColors.navy,
            size: 19,
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }

  void resetPassword() {
    if (passwordController.text.isEmpty ||
        confirmController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete both password fields'),
        ),
      );
      return;
    }

    if (!hasLength || !hasUppercase || !hasNumber || !hasSymbol) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password does not meet requirements'),
        ),
      );
      return;
    }

    if (passwordController.text != confirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match'),
        ),
      );
      return;
    }

    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (route) => false,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Password UI completed. Connect backend to save it.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios),
                  ),
                  const Expanded(
                    child: Text(
                      'Reset Password',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),

              const SizedBox(height: 25),

              const Center(
                child: Icon(
                  Icons.verified_user,
                  size: 65,
                  color: AppColors.primary,
                ),
              ),

              const SizedBox(height: 20),

              const Center(
                child: Text(
                  '● BIOMETRIC AUTH CONFIRMED',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),

              const SizedBox(height: 25),

              const Center(
                child: Text(
                  'Create New Password',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
              ),

              const SizedBox(height: 45),

              AppTextField(
                label: 'New Password',
                hint: 'Enter new password',
                icon: Icons.lock_outline,
                isPassword: true,
                controller: passwordController,
              ),

              const SizedBox(height: 28),

              AppTextField(
                label: 'Confirm New Password',
                hint: 'Confirm new password',
                icon: Icons.lock_reset_outlined,
                isPassword: true,
                controller: confirmController,
              ),

              const SizedBox(height: 35),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'CIPHER INTEGRITY PROTOCOL',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  AnimatedBuilder(
                    animation: passwordController,
                    builder: (context, child) {
                      final score = [
                        hasLength,
                        hasUppercase,
                        hasNumber,
                        hasSymbol,
                      ].where((e) => e).length;

                      final labels = [
                        'WEAK',
                        'FAIR',
                        'GOOD',
                        'STRONG',
                        'STRONG',
                      ];

                      return Text(
                        labels[score],
                        style: const TextStyle(
                          color: AppColors.teal,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 15),

              AnimatedBuilder(
                animation: passwordController,
                builder: (context, child) {
                  return Column(
                    children: [
                      requirement(
                        'At least 8 characters',
                        hasLength,
                      ),
                      requirement(
                        'At least one uppercase letter',
                        hasUppercase,
                      ),
                      requirement(
                        'At least one number',
                        hasNumber,
                      ),
                      requirement(
                        'At least one special character',
                        hasSymbol,
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 40),

              PrimaryButton(
                text: 'Reset Password',
                icon: Icons.vpn_key_outlined,
                onPressed: resetPassword,
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
