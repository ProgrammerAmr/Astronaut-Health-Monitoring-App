import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFFF9F9FF);
  static const Color white = Color(0xFFFFFFFF);

  static const Color primary = Color(0xFF075BE8);
  static const Color blue = Color(0xFF087BFA);
  static const Color lightBlue = Color(0xFF42B9F5);

  static const Color navy = Color(0xFF071D49);
  static const Color darkText = Color(0xFF101828);
  static const Color grey = Color(0xFF7A8499);

  static const Color cyan = Color(0xFF36DCE5);
  static const Color teal = Color(0xFF009D9A);

  static const Color border = Color(0xFFE5EAF3);
  static const Color lightBackground = Color(0xFFF1F6FF);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [
      primary,
      Color(0xFF42C5E8),
    ],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}