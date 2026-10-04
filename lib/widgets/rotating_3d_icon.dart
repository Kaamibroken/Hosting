import 'dart:math';
import 'package:flutter/material.dart';
import '../core/colors.dart';

class Rotating3DIcon extends StatefulWidget {
  final IconData icon;
  const Rotating3DIcon({Key? key, required this.icon}) : super(key: key);

  @override
  _Rotating3DIconState createState() => _Rotating3DIconState();
}

class _Rotating3DIconState extends State<Rotating3DIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // یہ ائیکن کو مسلسل 3D میں گھمائے گا
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
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
        return Transform(
          // یہ لائن جادو ہے! یہ 2D ائیکن کو 3D بنا کر Y-Axis پر گھماتی ہے
          transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(_controller.value * 2 * pi),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.neonAqua.withOpacity(0.4), blurRadius: 10)],
            ),
            child: Icon(widget.icon, color: Colors.white, size: 26),
          ),
        );
      },
    );
  }
}
