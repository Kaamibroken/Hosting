import 'package:flutter/material.dart';
import '../core/colors.dart';

class LiveNeonIcon extends StatefulWidget {
  final IconData icon;
  const LiveNeonIcon({Key? key, required this.icon}) : super(key: key);

  @override
  _LiveNeonIconState createState() => _LiveNeonIconState();
}

class _LiveNeonIconState extends State<LiveNeonIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // یہ ائیکن کو مسلسل اینیمیٹ کرنے کے لیے ہے
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_controller.value * 0.15), // ہلکا سا زوم ان اور آؤٹ
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.neonAqua.withOpacity(0.3 * _controller.value),
                  blurRadius: 15,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Icon(widget.icon, color: AppColors.neonAqua, size: 24),
          ),
        );
      },
    );
  }
}
