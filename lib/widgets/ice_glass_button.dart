import 'package:flutter/material.dart';

class IceGlassButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;

  const IceGlassButton({Key? key, required this.text, required this.onPressed}) : super(key: key);

  @override
  _IceGlassButtonState createState() => _IceGlassButtonState();
}

class _IceGlassButtonState extends State<IceGlassButton> with SingleTickerProviderStateMixin {
  late AnimationController _glintController;

  @override
  void initState() {
    super.initState();
    _glintController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _glintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onPressed,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(15)),
          // ٹوٹے شیشے یا برف جیسی ریفلیکشن کے لیے شارپ گریڈینٹ
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.05),
              const Color(0xFF45F3FF).withOpacity(0.1),
              Colors.white.withOpacity(0.2), // برف کی چمک
              const Color(0xFF45F3FF).withOpacity(0.05),
            ],
            stops: const [0.0, 0.4, 0.5, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.4), width: 1),
          boxShadow: [
            BoxShadow(color: const Color(0xFF45F3FF).withOpacity(0.2), blurRadius: 15, spreadRadius: 1)
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // لائیو لہر جو شیشے کے اندر سے گزرے گی
            AnimatedBuilder(
              animation: _glintController,
              builder: (context, child) {
                return Positioned(
                  left: -100 + (_glintController.value * 500),
                  child: Transform.rotate(
                    angle: 0.8,
                    child: Container(
                      width: 50,
                      height: 150,
                      color: Colors.white.withOpacity(0.3),
                    ),
                  ),
                );
              },
            ),
            Text(
              widget.text,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2),
            ),
          ],
        ),
      ),
    );
  }
}
