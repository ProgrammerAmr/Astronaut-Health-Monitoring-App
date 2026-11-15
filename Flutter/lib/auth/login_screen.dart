import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_widgets.dart';
import '../routes/app_routes.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool rememberMe = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void login() {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email and password')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Login UI completed. Backend is not connected yet.'),
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
            children: [
              const SizedBox(height: 15),

              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, AppRoutes.splash);
                    },
                    icon: const Icon(
                      Icons.arrow_back_ios,
                      color: AppColors.navy,
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Log In',
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

              const OrbitLogo(height: 95),

              const SizedBox(height: 35),

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
                'Sign in to continue monitoring your health.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: AppColors.darkText),
              ),

              const SizedBox(height: 55),

              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SectionLabel(text: 'Email'),
                  Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: AppColors.teal,
                        size: 17,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'ENCRYPTED',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              AppTextField(
                label: '',
                hint: 'astronaut@nasa.gov',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                controller: emailController,
              ),

              const SizedBox(height: 28),

              AppTextField(
                label: 'Password',
                hint: 'Enter your password',
                icon: Icons.lock_outline,
                isPassword: true,
                controller: passwordController,
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  Checkbox(
                    value: rememberMe,
                    activeColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    onChanged: (value) {
                      setState(() {
                        rememberMe = value ?? false;
                      });
                    },
                  ),
                  const Text(
                    'Remember Me',
                    style: TextStyle(color: AppColors.darkText, fontSize: 14),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, AppRoutes.forgotPassword);
                    },
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              PrimaryButton(
                text: 'Login',
                icon: Icons.arrow_forward,
                onPressed: login,
              ),

              const SizedBox(height: 25),

              const Row(
                children: [
                  Expanded(child: Divider(color: AppColors.border)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR CONTINUE WITH',
                      style: TextStyle(
                        color: AppColors.grey,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: AppColors.border)),
                ],
              ),

              const SizedBox(height: 25),

              TextButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Google Sign-In needs Firebase configuration.',
                      ),
                    ),
                  );
                },
                icon: Image.asset(
                  'assets/images/google_logo.jpg',
                  width: 36,
                  height: 36,
                ),
                label: const Text(
                  'Continue with Google',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),

              const SizedBox(height: 25),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? "),
                  GestureDetector(
                    onTap: () {
                      Navigator.pushNamed(context, AppRoutes.signup);
                    },
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 25),
            ],
          ),
        ),
      ),
    );
  }
}

// Google Logo

class GoogleLogo extends StatelessWidget {
  final double size;

  const GoogleLogo({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: GoogleLogoPainter()),
    );
  }
}

class GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      size.width * 0.08,
      size.height * 0.08,
      size.width * 0.84,
      size.height * 0.84,
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.17
      ..strokeCap = StrokeCap.butt;

    // Red
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, -1.57, 1.57, false, paint);

    // Yellow
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 0, 1.57, false, paint);

    // Green
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 1.57, 1.57, false, paint);

    // Blue
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, 3.14, 1.57, false, paint);

    // Google horizontal line
    paint
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = size.width * 0.16;

    canvas.drawLine(
      Offset(size.width * 0.52, size.height * 0.5),
      Offset(size.width * 0.95, size.height * 0.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
