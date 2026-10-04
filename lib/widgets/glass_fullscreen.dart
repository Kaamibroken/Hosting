import 'dart:ui';
import 'package:flutter/material.dart';

class FullScreenGlass extends StatelessWidget {
  final Widget child;

  const FullScreenGlass({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // فل سکرین بلر ایفیکٹ (پیور شیشہ)
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30), // بلر بڑھا دیا گیا ہے
            child: Container(
              decoration: BoxDecoration(
                // شیشے کی چمک کے لیے ہلکا سا گریڈینٹ
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.05),
                    Colors.white.withOpacity(0.01),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
              ),
            ),
          ),
        ),
        // اس کے اوپر آپ کا کنٹینٹ آئے گا
        Positioned.fill(child: child),
      ],
    );
  }
}
