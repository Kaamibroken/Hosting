import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'screens/auth/login_screen.dart';
import 'screens/dashboard_screen.dart'; 

void main() {
  runApp(const SilentHostingApp());
}

class SilentHostingApp extends StatelessWidget {
  const SilentHostingApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Silent Hosting',
      debugShowCheckedModeBanner: false, 
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0A0A10),
        brightness: Brightness.dark,
        fontFamily: 'Roboto', 
      ),
      // اب ایپ سیدھی سیشن چیکر سے سٹارٹ ہوگی، کوئی سپلیش سکرین نہیں
      home: const SessionChecker(), 
    );
  }
}

// ============================================================================
// --- SESSION CHECKER (The Silent Gateway) ---
// ============================================================================
class SessionChecker extends StatefulWidget {
  const SessionChecker({Key? key}) : super(key: key);

  @override
  _SessionCheckerState createState() => _SessionCheckerState();
}

class _SessionCheckerState extends State<SessionChecker> {

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    try {
      // رسٹ (Rust) بیک اینڈ سے سیشن چیک کریں
      final response = await http.get(Uri.parse('/api/user/profile'));
      
      if (response.statusCode == 200) {
        // سیشن موجود ہے، سیدھا ڈیش بورڈ
        if (mounted) {
          Navigator.pushReplacement(context, PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const DashboardScreen(),
            transitionDuration: Duration.zero, // کوئی اینیمیشن نہیں، ڈائریکٹ کھلے گا
          ));
        }
      } else {
        // سیشن نہیں ہے، لاگ ان پر جائیں
        if (mounted) {
          Navigator.pushReplacement(context, PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
            transitionDuration: Duration.zero,
          ));
        }
      }
    } catch (e) {
      // نیٹ ورک ایرر پر لاگ ان دکھائیں
      if (mounted) {
        Navigator.pushReplacement(context, PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
          transitionDuration: Duration.zero,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // جب تک API کا جواب آتا ہے، ہم ایک بالکل سادہ بلیک سکرین دکھائیں گے (جس کے پیچھے HTML لوڈر ہوگا)
    // چونکہ یہ ملی سیکنڈز میں ہو جائے گا، اس لیے یوزر کو فیل بھی نہیں ہوگا۔
    return const Scaffold(
      backgroundColor: Color(0xFF0A0A10), // آپ کی تھیم کا بیک گراؤنڈ
    );
  }
}
