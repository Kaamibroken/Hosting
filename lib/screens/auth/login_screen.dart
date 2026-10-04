import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'signup_screen.dart';
import '../dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  
  // فارگیٹ پاسورڈ فلو کنٹرولرز
  final TextEditingController _recoverIdentityController = TextEditingController();
  final List<TextEditingController> _recoveryOtpControllers = List.generate(5, (_) => TextEditingController());
  final List<FocusNode> _recoveryOtpFocusNodes = List.generate(5, (_) => FocusNode());
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String _currentView = "login"; // login, forgot_identify, forgot_reset
  int _secondsRemaining = 60;
  Timer? _countdownTimer;
  Timer? _userDebounce;
  Widget? _userSuffixIcon;

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    _recoverIdentityController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _countdownTimer?.cancel();
    _userDebounce?.cancel();
    for (var c in _recoveryOtpControllers) { c.dispose(); }
    for (var f in _recoveryOtpFocusNodes) { f.dispose(); }
    super.dispose();
  }

  void _startTimer() {
    setState(() { _secondsRemaining = 60; });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) { setState(() { _secondsRemaining--; }); } 
      else { _countdownTimer?.cancel(); }
    });
  }

  void _checkUserExists(String text) {
    if (text.isEmpty) { setState(() => _userSuffixIcon = null); return; }
    if (_userDebounce?.isActive ?? false) _userDebounce!.cancel();
    setState(() => _userSuffixIcon = const Padding(padding: EdgeInsets.all(15.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF45F3FF)))));

    _userDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final response = await http.post(Uri.parse('/api/check-user'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'field_type': text.contains('@') ? 'email' : 'username', 'value': text}));
        final data = jsonDecode(response.body);
        bool exists = data['exists'];
        setState(() => _userSuffixIcon = Icon(exists ? Icons.check_circle : Icons.cancel, color: exists ? Colors.greenAccent : Colors.red));
      } catch (e) { setState(() => _userSuffixIcon = null); }
    });
  }

  Future<void> _handleLogin() async {
    if (_userController.text.isEmpty || _passController.text.isEmpty) {
      PremiumToast.show(context, "Please enter credentials!", false);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await http.post(Uri.parse('/api/login'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'username_or_email': _userController.text, 'password': _passController.text}));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        PremiumToast.show(context, "Login Successful!", true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const DashboardScreen()));
        });
      } else { PremiumToast.show(context, data['message'] ?? "Invalid credentials", false); }
    } catch (e) { PremiumToast.show(context, "Network Error!", false); }
    finally { setState(() => _isLoading = false); }
  }

  Future<void> _sendRecoveryOtp() async {
    String identity = _recoverIdentityController.text.trim();
    if (identity.isEmpty) {
      PremiumToast.show(context, "Please enter username or email!", false);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await http.post(Uri.parse('/api/forgot-password'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'action': 'send_otp', 'identity': identity}));
      if (response.statusCode == 200) {
        PremiumToast.show(context, "OTP Sent Successfully!", true);
        _startTimer();
      } else {
        final data = jsonDecode(response.body);
        PremiumToast.show(context, data['message'] ?? "Account not found", false);
      }
    } catch (e) { PremiumToast.show(context, "Network Error!", false); }
    finally { setState(() => _isLoading = false); }
  }

  Future<void> _verifyRecoveryOtp() async {
    String combinedOtp = _recoveryOtpControllers.map((c) => c.text).join().trim();
    if (combinedOtp.length < 5) return;

    setState(() => _isLoading = true);
    try {
      final response = await http.post(Uri.parse('/api/forgot-password'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'action': 'verify_otp', 'identity': _recoverIdentityController.text.trim(), 'otp': combinedOtp}));
      if (response.statusCode == 200) {
        PremiumToast.show(context, "OTP Verified Successfully!", true);
        setState(() { _currentView = "forgot_reset"; });
      } else {
        PremiumToast.show(context, "Invalid OTP Code!", false);
        for (var c in _recoveryOtpControllers) { c.clear(); }
        FocusScope.of(context).requestFocus(_recoveryOtpFocusNodes[0]);
      }
    } catch (e) { PremiumToast.show(context, "Network Error!", false); }
    finally { setState(() => _isLoading = false); }
  }

  Future<void> _submitNewPassword() async {
    String newPass = _newPasswordController.text;
    if (newPass.isEmpty || _confirmPasswordController.text.isEmpty) {
      PremiumToast.show(context, "Please fill all fields!", false);
      return;
    }
    if (newPass != _confirmPasswordController.text) {
      PremiumToast.show(context, "Passwords do not match!", false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      String combinedOtp = _recoveryOtpControllers.map((c) => c.text).join().trim();
      final response = await http.post(Uri.parse('/api/forgot-password'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'action': 'reset_password', 'identity': _recoverIdentityController.text.trim(), 'otp': combinedOtp, 'new_password': newPass}));
      if (response.statusCode == 200) {
        PremiumToast.show(context, "Password Reset Successfully!", true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() {
              _currentView = "login";
              _userController.clear(); _passController.clear();
              _recoverIdentityController.clear(); _newPasswordController.clear(); _confirmPasswordController.clear();
              for (var c in _recoveryOtpControllers) { c.clear(); }
            });
          }
        });
      } else { PremiumToast.show(context, "Session expired or invalid operations", false); }
    } catch (e) { PremiumToast.show(context, "Network Error!", false); }
    finally { setState(() => _isLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    double formWidth = MediaQuery.of(context).size.width > 600 ? 400 : MediaQuery.of(context).size.width * 0.85;
    return Scaffold(
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0xFF0F3B57), Color(0xFF082236), Color(0xFF020E18)], radius: 1.5, center: Alignment(-0.3, -0.5)))),
          Center(
            child: SingleChildScrollView(
              child: SizedBox(
                width: formWidth,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.cloud_done_rounded, size: 75, color: Color(0xFF45F3FF)),
                    const SizedBox(height: 15),
                    ShatteredIntegratedText(text: _currentView == "login" ? "SILENT HOSTING" : (_currentView == "forgot_identify" ? "RECOVER" : "NEW PASSWORD")),
                    const SizedBox(height: 55),
                    
                    if (_currentView == "login") ...[
                      GlowingInputField(hint: "Username / Email", icon: Icons.person_outline, controller: _userController, onChanged: _checkUserExists, suffixIcon: _userSuffixIcon),
                      const SizedBox(height: 35),
                      GlowingInputField(hint: "Password", icon: Icons.lock_outline, isPassword: true, controller: _passController),
                      Padding(
                        padding: const EdgeInsets.only(top: 15, right: 4),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: () => setState(() { _currentView = "forgot_identify"; }),
                            child: const Text("Forgot Password?", style: TextStyle(color: Color(0xFF45F3FF), fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 45), 
                      SevereShatteredButton(text: "LOGIN", isLoading: _isLoading, onPressed: _handleLogin),
                      const SizedBox(height: 45),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Don't have an account? ", style: TextStyle(color: Colors.white70)),
                          GestureDetector(onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SignupScreen())), child: const Text("Sign Up", style: TextStyle(color: Color(0xFF45F3FF), fontWeight: FontWeight.bold, fontSize: 16)))
                        ],
                      )
                    ] else if (_currentView == "forgot_identify") ...[
                      GlowingInputField(hint: "Username or Email Address", icon: Icons.mark_email_read_outlined, controller: _recoverIdentityController),
                      const SizedBox(height: 30),
                      const Text("Please Enter Your OTP", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(5, (index) {
                          return SizedBox(
                            width: 55,
                            child: Container(
                              decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.02), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.6), width: 1.5)),
                              child: TextField(
                                controller: _recoveryOtpControllers[index],
                                focusNode: _recoveryOtpFocusNodes[index],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                maxLength: 1,
                                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(border: InputBorder.none, counterText: ""),
                                onChanged: (value) {
                                  if (value.isNotEmpty) {
                                    if (index < 4) {
                                      FocusScope.of(context).requestFocus(_recoveryOtpFocusNodes[index + 1]);
                                    } else {
                                      _recoveryOtpFocusNodes[index].unfocus();
                                      _verifyRecoveryOtp(); // پانچواں نمبر آتے ہی لائیو رن
                                    }
                                  } else if (value.isEmpty && index > 0) {
                                    FocusScope.of(context).requestFocus(_recoveryOtpFocusNodes[index - 1]);
                                  }
                                },
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 35),
                      SevereShatteredButton(text: "SEND OTP", isLoading: _isLoading, onPressed: _sendRecoveryOtp),
                      const SizedBox(height: 25),
                      Center(
                        child: _secondsRemaining > 0
                            ? Text("Resend OTP in $_secondsRemaining s", style: const TextStyle(color: Colors.white54, fontSize: 14))
                            : TextButton(onPressed: _sendRecoveryOtp, child: const Text("Resend OTP", style: TextStyle(color: Color(0xFF45F3FF), fontWeight: FontWeight.bold))),
                      ),
                      TextButton(onPressed: () => setState(() { _currentView = "login"; }), child: const Text("Back to Login", style: TextStyle(color: Colors.white54))),
                    ] else if (_currentView == "forgot_reset") ...[
                      GlowingInputField(hint: "New Password", icon: Icons.lock_reset_rounded, isPassword: true, controller: _newPasswordController),
                      const SizedBox(height: 25),
                      GlowingInputField(hint: "Confirm Password", icon: Icons.gpp_good_rounded, isPassword: true, controller: _confirmPasswordController),
                      const SizedBox(height: 45),
                      SevereShatteredButton(text: "SUBMIT", isLoading: _isLoading, onPressed: _submitNewPassword),
                    ]
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PremiumToast {
  static void show(BuildContext context, String message, bool isSuccess) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 50.0, 
        left: MediaQuery.of(context).size.width * 0.1,
        width: MediaQuery.of(context).size.width * 0.8,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 100.0, end: 0.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, value),
                child: Container(
                  padding: const EdgeInsets.only(left: 20, right: 20, top: 15, bottom: 15),
                  decoration: BoxDecoration(
                    color: const Color(0xFF082236).withOpacity(0.95),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isSuccess ? Colors.greenAccent.withOpacity(0.8) : Colors.red.withOpacity(0.8), width: 1.5),
                    boxShadow: [BoxShadow(color: isSuccess ? Colors.greenAccent.withOpacity(0.3) : Colors.red.withOpacity(0.3), blurRadius: 20, spreadRadius: 2)],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(isSuccess ? Icons.check_circle_outline : Icons.error_outline, color: isSuccess ? Colors.greenAccent : Colors.red, size: 28),
                      const SizedBox(width: 12),
                      Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), textAlign: TextAlign.center)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 3), () => overlayEntry.remove());
  }
}

class ShatteredIntegratedText extends StatefulWidget {
  final String text;
  const ShatteredIntegratedText({Key? key, required this.text}) : super(key: key);
  @override _ShatteredIntegratedTextState createState() => _ShatteredIntegratedTextState();
}
class _ShatteredIntegratedTextState extends State<ShatteredIntegratedText> with TickerProviderStateMixin {
  late AnimationController _waveController;
  @override void initState() { super.initState(); _waveController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500))..repeat(); }
  @override void dispose() { _waveController.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) => Center(
        child: Stack(alignment: Alignment.center, children: [
          // 🔥 VIP FIX: text.toUpperCase() کو بدل کر widget.text.toUpperCase() کر دیا گیا ہے
          Text(widget.text.toUpperCase(), textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4, foreground: Paint()..shader = LinearGradient(colors: [Colors.white, const Color(0xFF45F3FF), Colors.white], stops: [0.0, 0.1 + (_waveController.value * 0.8), 0.2 + (_waveController.value * 0.8)], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(const Rect.fromLTWH(0, 0, 400, 70)), shadows: [BoxShadow(color: const Color(0xFF45F3FF).withOpacity(0.6), blurRadius: 20)])),
          Positioned.fill(child: CustomPaint(painter: _TextFracturePainter())),
        ]),
      ),
    );
  }
}

class _TextFracturePainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF0F3B57).withOpacity(0.6)..strokeWidth = 1.0..style = PaintingStyle.stroke;
    final path = Path();
    for (double i = 0; i < size.width; i += 15.0) { path.moveTo(i, 0); path.lineTo(i + Random(i.toInt()).nextDouble() * 20 - 10, size.height); }
    for (double i = 0; i < size.height; i += 15.0) { path.moveTo(0, i); path.lineTo(size.width, i + Random(i.toInt()).nextDouble() * 20 - 10); }
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GlowingInputField extends StatefulWidget {
  final String hint; final IconData icon; final bool isPassword; final TextEditingController controller; final Function(String)? onChanged; final Widget? suffixIcon;
  const GlowingInputField({Key? key, required this.hint, required this.icon, required this.controller, this.isPassword = false, this.onChanged, this.suffixIcon}) : super(key: key);
  @override _GlowingInputFieldState createState() => _GlowingInputFieldState();
}
class _GlowingInputFieldState extends State<GlowingInputField> with TickerProviderStateMixin {
  late AnimationController _spinController;
  @override void initState() { super.initState(); _spinController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(); }
  @override void dispose() { _spinController.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.02), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.6), width: 1.5), boxShadow: [BoxShadow(color: const Color(0xFF45F3FF).withOpacity(0.35), blurRadius: 25, spreadRadius: 4), BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))]),
      child: TextField(
        controller: widget.controller, obscureText: widget.isPassword, onChanged: widget.onChanged, style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(prefixIcon: Padding(padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 12), child: AnimatedBuilder(animation: _spinController, builder: (context, child) => Transform(transform: Matrix4.identity()..setEntry(3, 2, 0.002)..rotateY(_spinController.value * 2 * pi), alignment: Alignment.center, child: Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.4), width: 1), color: const Color(0xFF45F3FF).withOpacity(0.1)), padding: const EdgeInsets.only(left: 6, right: 6, top: 6, bottom: 6), child: Icon(widget.icon, color: const Color(0xFF45F3FF), size: 22))))), suffixIcon: widget.suffixIcon, hintText: widget.hint, hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)), border: InputBorder.none, contentPadding: const EdgeInsets.only(left: 10, right: 10, top: 22, bottom: 22)),
      ),
    );
  }
}

class SevereShatteredButton extends StatefulWidget {
  final String text; final bool isLoading; final VoidCallback onPressed;
  const SevereShatteredButton({Key? key, required this.text, required this.isLoading, required this.onPressed}) : super(key: key);
  @override _SevereShatteredButtonState createState() => _SevereShatteredButtonState();
}
class _SevereShatteredButtonState extends State<SevereShatteredButton> with TickerProviderStateMixin {
  late AnimationController _wave; late AnimationController _glow;
  @override void initState() { super.initState(); _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(); _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true); }
  @override void dispose() { _wave.dispose(); _glow.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.isLoading ? null : widget.onPressed,
      child: AnimatedBuilder(animation: _glow, builder: (context, child) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity, height: 65, decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.7), width: 1.5), boxShadow: [BoxShadow(color: const Color(0xFF45F3FF).withOpacity(0.3 + (_glow.value * 0.2)), blurRadius: 20 + (_glow.value * 10), spreadRadius: 3 + (_glow.value * 2)), BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5))]),
          child: Stack(children: [
            CustomPaint(size: const Size(double.infinity, 65), painter: _RealisticShatterPainter()),
            if (!widget.isLoading) AnimatedBuilder(animation: _wave, builder: (context, child) => Positioned(left: -150 + (_wave.value * 700), top: -50, bottom: -50, child: Transform.rotate(angle: 0.4, child: Container(width: 12, decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.9), blurRadius: 20, spreadRadius: 5), BoxShadow(color: const Color(0xFF45F3FF).withOpacity(1.0), blurRadius: 30, spreadRadius: 8)]))))),
            Center(child: widget.isLoading ? const SizedBox(width: 25, height: 25, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) : Text(widget.text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 5, shadows: [Shadow(color: Color(0xFF45F3FF), blurRadius: 20)]))),
          ]),
        ),
      )),
    );
  }
}

class _RealisticShatterPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.3)..strokeWidth = 1.0..style = PaintingStyle.stroke;
    final path = Path();
    for (int i = 0; i < 15; i++) {
      double cx = Random(i).nextDouble() * size.width; double cy = Random(i+1).nextDouble() * size.height;
      for (int j = 0; j < 8; j++) { double a = (j * 45) * (pi / 180); path.moveTo(cx, cy); path.lineTo(cx + cos(a) * 40, cy + sin(a) * 40); }
    }
    canvas.drawPath(path, p);
  }
  @override bool shouldRepaint(CustomPainter old) => false;
}
