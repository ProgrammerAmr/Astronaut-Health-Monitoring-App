
import 'package:flutter/material.dart';

import '../screens/splash_screen.dart';
import '../screens/onboarding_screen.dart';

import '../auth/login_screen.dart';
import '../auth/signup_screen.dart';
import '../auth/forgot_password_screen.dart';
import '../auth/otp_screen.dart';
import '../auth/reset_password_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String forgotPassword = '/forgot-password';
  static const String otp = '/otp';
  static const String resetPassword = '/reset-password';

  static Map<String, WidgetBuilder> routes = {
    splash: (context) => const SplashScreen(),
    onboarding: (context) => const OnboardingScreen(),
    login: (context) => const LoginScreen(),
    signup: (context) => const SignupScreen(),
    forgotPassword: (context) => const ForgotPasswordScreen(),
    otp: (context) => const OtpScreen(),
    resetPassword: (context) => const ResetPasswordScreen(),
  };
}
