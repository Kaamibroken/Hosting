import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'login_screen.dart'; // تمام ڈیزائن ویجٹس اور PremiumToast یہاں سے آ رہے ہیں

class SignupScreen extends StatefulWidget {
  const SignupScreen({Key? key}) : super(key: key);
  @override
  _SignupScreenState createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  // 5 الگ الگ او ٹی پی باکسز کے کنٹرولرز اور فوکس نوڈز
  final List<TextEditingController> _otpControllers = List.generate(5, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(5, (_) => FocusNode());
  
  bool _isLoading = false;
  bool _isOtpSent = false;
  int _secondsRemaining = 60; // پروفیشنل لائیو الٹا ٹائمر ونڈو
  Timer? _countdownTimer;

  Timer? _userDebounce;
  Widget? _userSuffixIcon;
  Timer? _emailDebounce;
  Widget? _emailSuffixIcon;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _countdownTimer?.cancel();
    for (var c in _otpControllers) { c.dispose(); }
    for (var f in _otpFocusNodes) { f.dispose(); }
    super.dispose();
  }

  void _startTimer() {
    setState(() { _secondsRemaining = 60; });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() { _secondsRemaining--; });
      } else {
        _countdownTimer?.cancel();
      }
    });
  }

  void _checkField(String text, String fieldType) {
    String cleanText = text.trim();
    if (cleanText.isEmpty) {
      setState(() { if (fieldType == 'username') _userSuffixIcon = null; else _emailSuffixIcon = null; });
      return;
    }
    if (fieldType == 'username' && !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(cleanText)) {
      setState(() { _userSuffixIcon = const Icon(Icons.cancel, color: Colors.red); });
      return;
    }

    Timer? activeTimer = fieldType == 'username' ? _userDebounce : _emailDebounce;
    if (activeTimer?.isActive ?? false) activeTimer!.cancel();

    setState(() {
      Widget loader = const Padding(padding: EdgeInsets.only(left: 15, right: 15, top: 15, bottom: 15), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF45F3FF))));
      if (fieldType == 'username') _userSuffixIcon = loader; else _emailSuffixIcon = loader;
    });

    activeTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final response = await http.post(Uri.parse('/api/check-user'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'field_type': fieldType == 'username' ? 'username' : 'email', 'value': cleanText}));
        final data = jsonDecode(response.body);
        bool exists = data['exists'];
        setState(() {
          Icon statusIcon = Icon(exists ? Icons.cancel : Icons.check_circle, color: exists ? Colors.red : Colors.greenAccent);
          if (fieldType == 'username') _userSuffixIcon = statusIcon; else _emailSuffixIcon = statusIcon;
        });
      } catch (e) {
        setState(() { if (fieldType == 'username') _userSuffixIcon = null; else _emailSuffixIcon = null; });
      }
    });
    if (fieldType == 'username') _userDebounce = activeTimer; else _emailDebounce = activeTimer;
  }

  Future<void> _initiateSignupSequence() async {
    if (_nameController.text.trim().isEmpty || _usernameController.text.trim().isEmpty || _emailController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      PremiumToast.show(context, "Please fill all fields!", false);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await http.post(Uri.parse('/api/register'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'name': _nameController.text.trim(), 'username': _usernameController.text.trim().toLowerCase(), 'email': _emailController.text.trim().toLowerCase(), 'password': _passwordController.text, 'action': 'send_otp'}));
      if (response.statusCode == 200 || response.statusCode == 201) {
        PremiumToast.show(context, "OTP Sent Successfully!", true);
        setState(() { _isOtpSent = true; });
        _startTimer();
      } else {
        final data = jsonDecode(response.body);
        PremiumToast.show(context, data['message'] ?? "Registration failed", false);
      }
    } catch (e) { PremiumToast.show(context, "Network Error!", false); }
    finally { setState(() => _isLoading = false); }
  }

  Future<void> _verifyOtpAndCompleteRegistry() async {
    String combinedOtp = _otpControllers.map((c) => c.text).join().trim();
    if (combinedOtp.length < 5) return;

    setState(() => _isLoading = true);
    try {
      final response = await http.post(Uri.parse('/api/register'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'username': _usernameController.text.trim().toLowerCase(), 'email': _emailController.text.trim().toLowerCase(), 'otp': combinedOtp, 'action': 'verify'}));
      if (response.statusCode == 200 || response.statusCode == 201) {
        PremiumToast.show(context, "Account Created Successfully!", true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
        });
      } else {
        PremiumToast.show(context, "Invalid OTP Code!", false);
        for (var c in _otpControllers) { c.clear(); }
        FocusScope.of(context).requestFocus(_otpFocusNodes[0]);
      }
    } catch (e) { PremiumToast.show(context, "Network Error!", false); }
    finally { if (mounted) setState(() => _isLoading = false); }
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
                    ShatteredIntegratedText(text: _isOtpSent ? "ENTER OTP" : "CREATE ACCOUNT"),
                    const SizedBox(height: 45),
                    if (!_isOtpSent) ...[
                      GlowingInputField(hint: "Full Name", icon: Icons.badge_outlined, controller: _nameController),
                      const SizedBox(height: 25),
                      GlowingInputField(hint: "Username", icon: Icons.person, controller: _usernameController, onChanged: (v) => _checkField(v, 'username'), suffixIcon: _userSuffixIcon),
                      const SizedBox(height: 25),
                      GlowingInputField(hint: "Email Address", icon: Icons.email_outlined, controller: _emailController, onChanged: (v) => _checkField(v, 'email'), suffixIcon: _emailSuffixIcon),
                      const SizedBox(height: 25),
                      GlowingInputField(hint: "Password", icon: Icons.lock_outline, isPassword: true, controller: _passwordController),
                      const SizedBox(height: 45),
                      SevereShatteredButton(text: "SIGN UP", isLoading: _isLoading, onPressed: _initiateSignupSequence),
                    ] else ...[
                      const Text("Please Enter Your OTP", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(5, (index) {
                          return SizedBox(
                            width: 55,
                            child: Container(
                              decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.02), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.6), width: 1.5)),
                              child: TextField(
                                controller: _otpControllers[index],
                                focusNode: _otpFocusNodes[index],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                maxLength: 1,
                                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(border: InputBorder.none, counterText: ""),
                                onChanged: (value) {
                                  if (value.isNotEmpty) {
                                    if (index < 4) {
                                      FocusScope.of(context).requestFocus(_otpFocusNodes[index + 1]);
                                    } else {
                                      _otpFocusNodes[index].unfocus();
                                      _verifyOtpAndCompleteRegistry(); // پانچواں ہندسہ آتے ہی آٹو رن
                                    }
                                  } else if (value.isEmpty && index > 0) {
                                    FocusScope.of(context).requestFocus(_otpFocusNodes[index - 1]);
                                  }
                                },
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 35),
                      Center(
                        child: _secondsRemaining > 0
                            ? Text("Resend OTP in $_secondsRemaining s", style: const TextStyle(color: Colors.white54, fontSize: 14))
                            : TextButton.icon(
                                onPressed: () { _initiateSignupSequence(); },
                                icon: const Icon(Icons.refresh, color: Color(0xFF45F3FF), size: 16),
                                label: const Text("Resend OTP", style: TextStyle(color: Color(0xFF45F3FF), fontWeight: FontWeight.bold)),
                              ),
                      ),
                    ],
                    const SizedBox(height: 40),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Already have an account? ", style: TextStyle(color: Colors.white70)),
                        GestureDetector(onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen())), child: const Text("Login", style: TextStyle(color: Color(0xFF45F3FF), fontWeight: FontWeight.bold, fontSize: 16)))
                      ],
                    )
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}