import 'package:flutter/material.dart';

class AuthStatusBanner extends StatelessWidget {
  final String message;
  final bool isError;
  final Widget? action;

  const AuthStatusBanner({
    super.key,
    required this.message,
    this.isError = true,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isError ? const Color(0xFFFEF3F2) : const Color(0xFFEFF6FF);
    final borderColor =
        isError ? const Color(0xFFFDA29B) : const Color(0xFF93C5FD);
    final fgColor = isError ? const Color(0xFFB42318) : const Color(0xFF1E40AF);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.info_outline,
                color: fgColor,
                size: 19,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: fgColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 8),
            action!,
          ],
        ],
      ),
    );
  }
}
