
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_widgets.dart';
import '../routes/app_routes.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState
    extends State<ForgotPasswordScreen> {
  final emailController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  void sendCode() {
    final email = emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address.'),
        ),
      );
      return;
    }

    Navigator.pushNamed(
      context,
      AppRoutes.otp,
      arguments: {
        'email': email,
        'isPasswordReset': true,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 15),

              // Header
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back_ios,
                      color: AppColors.navy,
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Forgot Password',
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

              const SizedBox(height: 45),

              // Illustration
              const Center(
                child: Icon(
                  Icons.lock_reset_rounded,
                  size: 95,
                  color: AppColors.primary,
                ),
              ),

              const SizedBox(height: 30),

              // Title
              const Center(
                child: Text(
                  'Forgot Password?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
              ),

              const SizedBox(height: 15),

              // Description
              const Text(
                'Don’t worry! It happens. Please enter '
                'the email address associated with your '
                'account and we will send you a verification code.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.7,
                  color: AppColors.grey,
                ),
              ),

              const SizedBox(height: 45),

              // Email field
              const SectionLabel(
                text: 'Registered Email Address',
                icon: Icons.email_outlined,
              ),

              const SizedBox(height: 10),

              AppTextField(
                label: 'Email Address',
                hint: 'astronaut@nasa.gov',
                icon: Icons.alternate_email,
                keyboardType: TextInputType.emailAddress,
                controller: emailController,
              ),

              const SizedBox(height: 15),

              const Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: AppColors.teal,
                    size: 17,
                  ),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Your account information is securely protected.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.grey,
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              // Send verification code
              PrimaryButton(
                text: 'Send Verification Code',
                icon: Icons.arrow_forward,
                onPressed: sendCode,
              ),

              const SizedBox(height: 20),

              // Back to login
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.pushReplacementNamed(
                      context,
                      AppRoutes.login,
                    );
                  },
                  child: const Text(
                    'Back to Login',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
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
