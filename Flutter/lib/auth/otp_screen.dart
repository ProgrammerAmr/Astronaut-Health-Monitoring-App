
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/app_colors.dart';
import '../constants/app_widgets.dart';
import '../routes/app_routes.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );

  final focusNodes = List.generate(
    6,
    (_) => FocusNode(),
  );

  static const int initialSeconds = 47;

  int remainingSeconds = initialSeconds;
  Timer? countdownTimer;

  bool get canResend => remainingSeconds == 0;

  @override
  void initState() {
    super.initState();
    startTimer();
  }

  void startTimer() {
    countdownTimer?.cancel();

    setState(() {
      remainingSeconds = initialSeconds;
    });

    countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (remainingSeconds > 0) {
          setState(() {
            remainingSeconds--;
          });
        } else {
          timer.cancel();
        }
      },
    );
  }

  String get formattedTime {
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  void resendCode() {
    if (!canResend) return;

    for (final controller in controllers) {
      controller.clear();
    }

    focusNodes[0].requestFocus();

    startTimer();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'A new verification code has been requested.',
        ),
      ),
    );
  }

  @override
  void dispose() {
    countdownTimer?.cancel();

    for (final controller in controllers) {
      controller.dispose();
    }

    for (final node in focusNodes) {
      node.dispose();
    }

    super.dispose();
  }

  void verifyCode() {
    final code = controllers.map((e) => e.text).join();

    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the 6-digit code'),
        ),
      );
      return;
    }

    if (canResend) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Verification code expired. Please request a new one.',
          ),
        ),
      );
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      AppRoutes.resetPassword,
    );
  }

  Widget otpBox(int index) {
    return SizedBox(
      width: 43,
      height: 58,
      child: TextField(
        controller: controllers[index],
        focusNode: focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.navy,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppColors.border,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppColors.primary,
              width: 2,
            ),
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            focusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            focusNodes[index - 1].requestFocus();
          }
        },
      ),
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
            children: [
              const SizedBox(height: 15),

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
                      'OTP',
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

              const SizedBox(height: 35),

              const Icon(
                Icons.mark_email_read_outlined,
                size: 95,
                color: AppColors.primary,
              ),

              const SizedBox(height: 30),

              const Text(
                'Verify Your Email',
                style: TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkText,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                "We've sent a 6-digit verification code to your registered station address:",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: AppColors.darkText,
                ),
              ),

              const SizedBox(height: 15),

              const Text(
                'dr.elara@station.space',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.navy,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 55),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  6,
                  (index) => otpBox(index),
                ),
              ),

              const SizedBox(height: 35),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.access_time,
                    size: 19,
                    color: canResend
                        ? Colors.red
                        : AppColors.navy,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    canResend
                        ? 'Code expired'
                        : 'Resend Code in $formattedTime',
                    style: TextStyle(
                      color: canResend
                          ? Colors.red
                          : AppColors.navy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Didn't receive code? "),
                  GestureDetector(
                    onTap: canResend ? resendCode : null,
                    child: Text(
                      'Resend Code',
                      style: TextStyle(
                        color: canResend
                            ? AppColors.primary
                            : AppColors.grey,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              PrimaryButton(
                text: 'Verify Code',
                icon: Icons.verified_outlined,
                onPressed: verifyCode,
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}