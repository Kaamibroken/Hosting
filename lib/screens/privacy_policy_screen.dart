import 'dart:math';
import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A10),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF45F3FF)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF34D399), size: 22),
            SizedBox(width: 10),
            Text("PRIVACY & POLICY",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    fontSize: 16,
                    color: Colors.white)),
          ],
        ),
      ),
      body: Stack(
        children: [
          // پریمیم بیک گراؤنڈ
          Container(
              decoration: const BoxDecoration(
                  gradient: RadialGradient(
                      colors: [Color(0xFF0F3B57), Color(0xFF082236), Color(0xFF020E18)],
                      radius: 1.5))),
          
          // لائیو ترچھی لہریں
          const Positioned.fill(child: LiveCyberBackgroundP()),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("TERMS OF SERVICE & DATA PRIVACY",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900, // ERROR FIXED HERE
                          letterSpacing: 2)),
                  const SizedBox(height: 10),
                  const Text("Last Updated: April 2026",
                      style: TextStyle(
                          color: Color(0xFF45F3FF),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                  const SizedBox(height: 30),

                  _buildPolicySection(
                    "1. Data Collection & Anonymity",
                    "Silent Hosting is built on the principle of absolute privacy. We collect only the minimum required information (Username, Email) to maintain your account. We DO NOT track your IP address, browser fingerprint, or deployment history beyond what is necessary to keep your containers running.",
                  ),
                  
                  _buildPolicySection(
                    "2. Source Code Protection",
                    "Your intellectual property remains yours. All code uploaded to our Railway-backed volumes is sandboxed within your specific user ID directory. No other user, and no automated script from our side, can access, read, or copy your source code. It is encrypted at rest.",
                  ),

                  _buildPolicySection(
                    "3. Ephemeral Storage & Wipes",
                    "When you hit the 'Delete' button on a project or your account, the data is instantly and permanently eradicated from our NVMe drives. We do not keep 'soft backups' or 'hidden copies'. Once it's gone, it's gone forever.",
                  ),

                  _buildPolicySection(
                    "4. Fair Usage & Zero Tolerance Policy",
                    "While we give you unrestricted terminal access via the silent.run engine, we maintain a strict Zero Tolerance Policy against:\n\n• Hosting Phishing Pages\n• Executing DDoS Scripts or Botnets\n• Child Exploitation Material\n• Crypto-mining scripts on free tiers\n\nDetection of such activities will result in an immediate, unappealable hardware ban and data wipe.",
                  ),

                  _buildPolicySection(
                    "5. Cookies & Session Security",
                    "We use strict, HttpOnly, encrypted cookies (JWT) to manage your session. This ensures that even if you encounter a cross-site scripting (XSS) attempt on an external site, your Silent Hosting session remains impenetrable.",
                  ),

                  const SizedBox(height: 40),
                  
                  // Accept Button (Visual only)
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF45F3FF).withOpacity(0.1),
                        border: Border.all(color: const Color(0xFF45F3FF)),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Center(
                          child: Text("I UNDERSTAND AND AGREE",
                              style: TextStyle(
                                  color: Color(0xFF45F3FF),
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2))),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPolicySection(String title, String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: const Color(0xFF45F3FF).withOpacity(0.02),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.2)),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _LightShatterPainterP())), // دراڑیں
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Color(0xFF45F3FF),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              const SizedBox(height: 15),
              Text(content,
                  style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.6)),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// --- INTERNAL PAINTERS ---
// ============================================================================

class LiveCyberBackgroundP extends StatefulWidget {
  const LiveCyberBackgroundP({Key? key}) : super(key: key);
  @override
  _LiveCyberBackgroundPState createState() => _LiveCyberBackgroundPState();
}

class _LiveCyberBackgroundPState extends State<LiveCyberBackgroundP> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
  }
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _DiagonalWavePainterP(_c.value)));
}

class _DiagonalWavePainterP extends CustomPainter {
  final double progress;
  _DiagonalWavePainterP(this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF45F3FF).withOpacity(0.03)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    double offset = progress * 100;
    for (double i = -size.height; i < size.width + size.height; i += 40) {
      canvas.drawLine(Offset(i + offset, 0), Offset(i - size.height + offset, size.height), p);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

class _LightShatterPainterP extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    final path = Path();
    path.moveTo(size.width * 0.7, 0);
    path.lineTo(size.width, size.height * 0.4);
    path.moveTo(0, size.height * 0.6);
    path.lineTo(size.width * 0.4, size.height);
    canvas.drawPath(path, p);
  }
  @override
  bool shouldRepaint(CustomPainter old) => false;
}
