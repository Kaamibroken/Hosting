import 'package:flutter/material.dart';

class LiquidGlassButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;

  const LiquidGlassButton({Key? key, required this.text, required this.onPressed}) : super(key: key);

  @override
  _LiquidGlassButtonState createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton> with SingleTickerProviderStateMixin {
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    // یہ کنٹرولر پانی کی لہر کو مسلسل چلائے گا
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(); // لامتناہی (Infinite) لوپ
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 60,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05), // شیشے کی بیس
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
            boxShadow: [
              BoxShadow(color: const Color(0xFF45F3FF).withOpacity(0.3), blurRadius: 20, spreadRadius: -5)
            ],
          ),
          child: Stack(
            children: [
              // لہر (Wave / Light Reflection) کی اینیمیشن
              AnimatedBuilder(
                animation: _waveController,
                builder: (context, child) {
                  return Positioned(
                    left: -200 + (_waveController.value * 500), // لیفٹ سے رائٹ موومنٹ
                    top: -50,
                    bottom: -50,
                    child: Transform.rotate(
                      angle: 0.5, // لہر کو ترچھا (Diagonal) کرنے کے لیے
                      child: Container(
                        width: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              Colors.white.withOpacity(0.4), // چمک (Glow)
                              Colors.transparent,
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              // بٹن کا ٹیکسٹ
              Center(
                child: Text(
                  widget.text,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2,
                    shadows: [Shadow(color: Color(0xFF45F3FF), blurRadius: 10)], // ٹیکسٹ کا اپنا گلو
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
