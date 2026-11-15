import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_widgets.dart';
import '../core/models/orbitcare_models.dart';
import '../core/state/session_controller.dart';
import '../routes/app_routes.dart';
import 'auth_status_banner.dart';

class OtpScreen extends StatefulWidget {
  final OtpRouteArgs? initialArgs;

  const OtpScreen({
    super.key,
    this.initialArgs,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> focusNodes = List.generate(6, (_) => FocusNode());

  Timer? timer;
  int remainingSeconds = 60;
  bool _isLoading = false;
  bool _isResending = false;
  String? _errorMessage;
  String? _infoMessage;

  OtpRouteArgs _resolveArgs(BuildContext context) {
    if (widget.initialArgs != null) return widget.initialArgs!;
    final rawArgs = ModalRoute.of(context)?.settings.arguments;
    if (rawArgs is OtpRouteArgs) return rawArgs;
    if (rawArgs is String && rawArgs.trim().isNotEmpty) {
      return OtpRouteArgs(email: rawArgs.trim(), purpose: 'signup');
    }
    return const OtpRouteArgs(email: '', purpose: 'signup');
  }

  @override
  void initState() {
    super.initState();
    startCountdown();
  }

  void startCountdown() {
    timer?.cancel();
    setState(() {
      remainingSeconds = 60;
    });

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (remainingSeconds > 0) {
        setState(() {
          remainingSeconds--;
        });
      } else {
        t.cancel();
      }
    });
  }

  String get formattedTime {
    final minutes = (remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (remainingSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String get otpCode => controllers.map((c) => c.text.trim()).join();

  Future<void> _handleVerify(OtpRouteArgs args) async {
    final code = otpCode;
    if (args.email.isEmpty) {
      setState(() {
        _errorMessage =
            'Missing email context for OTP verification. Please restart the flow.';
      });
      return;
    }

    if (code.length != 6) {
      setState(() {
        _errorMessage = 'Please enter all 6 digits of your verification code.';
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
      _infoMessage = null;
    });

    try {
      final session = await sessionController.apiClient.verifyOtp(
        email: args.email,
        otp: code,
        purpose: args.purpose,
      );

      if (!mounted) return;

      if (args.isSignup) {
        if (session == null) {
          setState(() {
            _errorMessage = 'Verification succeeded, but no session was returned.';
          });
          return;
        }
        await sessionController.establishSession(session);
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.home,
          (_) => false,
        );
      } else {
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.resetPassword,
          arguments: ResetPasswordRouteArgs(email: args.email, otp: code),
        );
      }
    } on OrbitCareApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to verify OTP right now. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleResend(OtpRouteArgs args) async {
    if (args.email.isEmpty || _isResending) return;
    final sessionController = SessionScope.maybeOf(context);
    if (sessionController == null) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final msg = await sessionController.apiClient.sendOtp(
        email: args.email,
        purpose: args.purpose,
      );
      if (!mounted) return;
      startCountdown();
      setState(() {
        _infoMessage = msg;
      });
    } on OrbitCareApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    for (final c in controllers) {
      c.dispose();
    }
    for (final f in focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = _resolveArgs(context);
    final subtitleEmail = args.email.isNotEmpty ? args.email : 'your email';

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
              const Center(child: OrbitLogo(height: 80)),
              const SizedBox(height: 22),
              Center(
                child: Text(
                  args.isSignup
                      ? 'Verify Your Email'
                      : 'Verify Reset Code',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'Enter the 6-digit verification code sent to\n$subtitleEmail.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: AppColors.grey,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              if (_infoMessage != null) ...[
                AuthStatusBanner(isError: false, message: _infoMessage!),
                const SizedBox(height: 14),
              ],
              if (_errorMessage != null) ...[
                AuthStatusBanner(isError: true, message: _errorMessage!),
                const SizedBox(height: 14),
              ],
              Container(
                padding: const EdgeInsets.all(20),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(
                        6,
                        (index) => SizedBox(
                          width: 44,
                          height: 54,
                          child: TextField(
                            key: Key('otp_digit_$index'),
                            controller: controllers[index],
                            focusNode: focusNodes[index],
                            enabled: !_isLoading,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            maxLength: 1,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                              color: AppColors.navy,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              filled: true,
                              fillColor: AppColors.lightBackground,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: AppColors.border,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: AppColors.border,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: AppColors.primary,
                                  width: 1.8,
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
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Didn't receive code? ",
                          style: TextStyle(
                            color: AppColors.grey,
                            fontSize: 14,
                          ),
                        ),
                        if (remainingSeconds > 0)
                          Text(
                            'Resend in $formattedTime',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          )
                        else
                          GestureDetector(
                            onTap: _isResending
                                ? null
                                : () => _handleResend(args),
                            child: Text(
                              _isResending ? 'Sending...' : 'Resend Code',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      text: 'Verify Code',
                      icon: Icons.arrow_forward,
                      isLoading: _isLoading,
                      onPressed:
                          _isLoading ? null : () => _handleVerify(args),
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
