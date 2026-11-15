
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_widgets.dart';
import '../routes/app_routes.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
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
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  Widget requirement(String text, bool valid) {
    return Row(
      children: [
        Icon(
          valid ? Icons.check_circle : Icons.circle_outlined,
          color: valid ? AppColors.teal : AppColors.navy,
          size: 17,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.navy,
          ),
        ),
      ],
    );
  }

  void createAccount() {
    if (nameController.text.trim().isEmpty ||
        emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty ||
        confirmController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all fields'),
        ),
      );
      return;
    }

    if (!hasLength || !hasUppercase || !hasNumber || !hasSymbol) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password does not meet all requirements'),
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

    Navigator.pushNamed(
      context,
      AppRoutes.otp,
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
            children: [
              const SizedBox(height: 10),

              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios),
                  ),
                  const Expanded(
                    child: Text(
                      'Sign Up',
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

              const OrbitLogo(height: 75),

              const SizedBox(height: 15),

              const Text(
                'Create Your Account',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navy,
                ),
              ),

              const SizedBox(height: 10),

              const Text(
                'Join Astronaut Health to monitor your health during your mission.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: AppColors.darkText,
                ),
              ),

              const SizedBox(height: 20),

              const SectionLabel(
                text: 'Secure Telemetry Uplink : Encrypted',
                icon: Icons.circle,
              ),

              const SizedBox(height: 28),

              AppTextField(
                label: 'Full Name',
                hint: 'Alex Vance',
                icon: Icons.badge_outlined,
                controller: nameController,
              ),

              const SizedBox(height: 18),

              AppTextField(
                label: 'Email Address',
                hint: 'alex.vance@agency.space',
                icon: Icons.alternate_email,
                keyboardType: TextInputType.emailAddress,
                controller: emailController,
              ),

              const SizedBox(height: 18),

              AppTextField(
                label: 'Password',
                hint: 'Create strong password',
                icon: Icons.lock_outline,
                isPassword: true,
                controller: passwordController,
              ),

              const SizedBox(height: 15),

              AnimatedBuilder(
                animation: passwordController,
                builder: (context, child) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      requirement('8+ Chars', hasLength),
                      requirement('Uppercase', hasUppercase),
                      requirement('Num', hasNumber),
                      requirement('Symbol', hasSymbol),
                    ],
                  );
                },
              ),

              const SizedBox(height: 22),

              AppTextField(
                label: 'Confirm Password',
                hint: 'Re-enter password',
                icon: Icons.verified_user_outlined,
                isPassword: true,
                controller: confirmController,
              ),

              const SizedBox(height: 30),

              PrimaryButton(
                text: 'Create Account',
                icon: Icons.person_add_alt_1,
                onPressed: createAccount,
              ),

              const SizedBox(height: 28),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already have an account? '),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushReplacementNamed(
                        context,
                        AppRoutes.login,
                      );
                    },
                    child: const Text(
                      'Login',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
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
