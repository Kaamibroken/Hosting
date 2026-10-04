import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// تمام امپورٹس (پروفیشنل آئیسولیشن)
import '../auth/login_screen.dart'; // PremiumToast اور لاگ ان کے لیے
import 'users_management_screen.dart';
import 'billing_management_screen.dart';
import 'keys_management_screen.dart';
import 'projects_management_screen.dart'; // 🔥 فکسڈ: نیو کلستر اسکرین کی فائل یہاں امپورٹ کر دی ہے
import 'admin_settings_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({Key? key}) : super(key: key);
  @override
  _AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with TickerProviderStateMixin {
  String activeTab = "dashboard"; 
  bool isDrawerOpen = false;
  bool isLoading = true;

  // Real Data Maps (API سے بھرے جائیں گے)
  Map sysStats = { "ram_total": 0, "ram_used": 0, "cpu_usage": 0, "storage_total": 0, "storage_used": 0 };
  Map userStats = { "total": 0, "free": 0, "basic": 0, "pro": 0 };
  Map projStats = { "total": 0, "online": 0, "offline": 0, "crashed": 0 };

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  // ============================================================================
  // --- REAL ADMIN APIs ---
  // ============================================================================

  Future<void> _fetchDashboardData() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse('/api/admin/dashboard/stats'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          sysStats = data['sys_stats'] ?? sysStats;
          userStats = data['user_stats'] ?? userStats;
          projStats = data['proj_stats'] ?? projStats;
        });
      } else {
        PremiumToast.show(context, "Unauthorized access or Session Expired!", false);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const LoginScreen()));
      }
    } catch (e) {
      PremiumToast.show(context, "Network Error loading stats", false);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    try {
      await http.post(Uri.parse('/api/logout'));
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const LoginScreen()));
      }
    } catch (e) {
      PremiumToast.show(context, "Logout failed. Please check connection.", false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12), 
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0xFF2A0815), Color(0xFF140518), Color(0xFF0A0A12)], radius: 1.5))),
          const Positioned.fill(child: AdminLiveBackgroundX()),

          SafeArea(
            child: Column(
              children: [
                _buildTopNavbar(),
                Expanded(child: _buildActiveTab()),
              ],
            ),
          ),

          _buildAdminDrawer(),
        ],
      ),
    );
  }

  Widget _buildActiveTab() {
    switch (activeTab) {
      case "dashboard": return _buildHomeDashboard();
      case "users": return const UsersManagementScreen();
      case "billing": return const BillingManagementScreen();
      case "keys": return const KeysManagementScreen();
      case "projects": return const ProjectsManagementScreen(); // 🔗 اب یہ دوسری فائل سے افیشل لوڈ ہوگا
      case "settings": return const AdminSettingsScreen();
      default: return _buildHomeDashboard();
    }
  }

  // ============================================================================
  // --- TOP NAVBAR ---
  // ============================================================================
  Widget _buildTopNavbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.menu_open_rounded, color: Colors.redAccent, size: 32), onPressed: () => setState(() => isDrawerOpen = true)),
          const AdminGlowingText(text: "GOD MODE"),
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1.5), color: Colors.white.withOpacity(0.05), image: const DecorationImage(image: AssetImage("assets/logo.png"), fit: BoxFit.cover)),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // --- ADMIN VIP DRAWER (3-LINE MENU) ---
  // ============================================================================
  Widget _buildAdminDrawer() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
      top: 0, bottom: 0, left: isDrawerOpen ? 0 : -300, width: 280,
      child: Container(
        decoration: BoxDecoration(color: const Color(0xFF140518).withOpacity(0.95), border: const Border(right: BorderSide(color: Colors.redAccent, width: 1.5)), boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.2), blurRadius: 30)]),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _ShatterPainterX())), 
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.all(20), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("COMMAND", style: TextStyle(color: Colors.redAccent, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3)), IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => setState(() => isDrawerOpen = false))])),
                  const Divider(color: Colors.white10),
                  
                  _drawerItem(Icons.dashboard_rounded, "Overview", "dashboard", Colors.white),
                  _drawerItem(Icons.group_rounded, "Users Management", "users", const Color(0xFF45F3FF)),
                  _drawerItem(Icons.receipt_long_rounded, "Billing Requests", "billing", Colors.greenAccent),
                  _drawerItem(Icons.vpn_key_rounded, "Access Keys", "keys", Colors.amber),
                  
                  // 🎛️ پروجیکٹس کلسٹر پینل آپشن بالکل سیٹ ہے
                  _drawerItem(Icons.dns_rounded, "Projects Cluster", "projects", Colors.blueAccent),
                  
                  _drawerItem(Icons.admin_panel_settings, "Admin Settings", "settings", Colors.purpleAccent),
                  
                  const Spacer(),
                  const Divider(color: Colors.white10),
                  
                  ListTile(
                    leading: const Icon(Icons.power_settings_new, color: Colors.redAccent), 
                    title: const Text("Terminate Session", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)), 
                    onTap: _handleLogout
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String text, String tab, Color color) {
    bool isActive = activeTab == tab;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(color: isActive ? color.withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(icon, color: isActive ? color : Colors.white38, size: 22),
        title: Text(text, style: TextStyle(color: isActive ? color : Colors.white54, fontWeight: FontWeight.bold, fontSize: 13)),
        onTap: () => setState(() { activeTab = tab; isDrawerOpen = false; }),
      ),
    );
  }

  double _parseValue(dynamic val, double fallback) {
    if (val == null) return fallback;
    if (val is num) return val.toDouble();
    String cleanStr = val.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleanStr) ?? fallback;
  }

  // ============================================================================
  // --- HOME DASHBOARD (REAL SYSTEM & STATS) ---
  // ============================================================================
  Widget _buildHomeDashboard() {
    return GestureDetector(
      onTap: () { if (isDrawerOpen) setState(() => isDrawerOpen = false); },
      child: RefreshIndicator(
        color: Colors.redAccent, backgroundColor: const Color(0xFF140518),
        onRefresh: _fetchDashboardData, 
        child: isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              children: [
                const Text("SYSTEM RESOURCES", style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                
                _buildGlassCard(
                  borderColor: Colors.redAccent,
                  child: Column(
                    children: [
                      _buildResourceBar("RAM USAGE", _parseValue(sysStats['ram_used'], 0.0), _parseValue(sysStats['ram_total'], 1.0), "GB", Colors.purpleAccent),
                      const SizedBox(height: 20),
                      _buildResourceBar("CPU LOAD", _parseValue(sysStats['cpu_usage'], 0.0), 100.0, "%", Colors.redAccent),
                      const SizedBox(height: 20),
                      _buildResourceBar("NVMe STORAGE", _parseValue(sysStats['storage_used'], 0.0), _parseValue(sysStats['storage_total'], 1.0), "GB", Colors.amber),
                    ],
                  ),
                ),

                const SizedBox(height: 30),
                const Text("NETWORK STATISTICS", style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),

                GridView(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1.1),
                  children: [
                    _buildStatBox("Total Users", (userStats['total'] ?? 0).toString(), Icons.group, const Color(0xFF45F3FF)),
                    
                    GestureDetector(
                      onTap: () => setState(() => activeTab = "projects"),
                      child: _buildStatBox("Total Projects", (projStats['total'] ?? 0).toString(), Icons.dns, Colors.blueAccent),
                    ),
                    
                    _buildStatBox("Pro Users", (userStats['pro'] ?? 0).toString(), Icons.diamond, const Color(0xFFA855F7)),
                    
                    GestureDetector(
                      onTap: () => setState(() => activeTab = "projects"),
                      child: _buildStatBox("Crashed Apps", (projStats['crashed'] ?? 0).toString(), Icons.warning_rounded, Colors.redAccent),
                    ),
                  ],
                ),

                const SizedBox(height: 30),
                const Text("PLAN BREAKDOWN", style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),

                _buildGlassCard(
                  borderColor: Colors.white10,
                  child: Column(
                    children: [
                      _buildPlanRow("Free Tier (Keys)", userStats['free'] ?? 0, const Color(0xFF45F3FF)),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(color: Colors.white10)),
                      _buildPlanRow("Basic Plan", userStats['basic'] ?? 0, Colors.greenAccent),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(color: Colors.white10)),
                      _buildPlanRow("Pro Plan (VIP)", userStats['pro'] ?? 0, const Color(0xFFA855F7)),
                    ],
                  ),
                ),
                const SizedBox(height: 50),
              ],
            ),
      ),
    );
  }

  // --- UI HELPERS ---
  Widget _buildGlassCard({required Widget child, required Color borderColor}) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(25), border: Border.all(color: borderColor.withOpacity(0.3))),
      child: Stack(children: [ Positioned.fill(child: CustomPaint(painter: _ShatterPainterX())), child ]),
    );
  }

  Widget _buildResourceBar(String title, num used, num total, String unit, Color color) {
    double percentage = total > 0 ? (used / total) : 0;
    if (percentage > 1.0) percentage = 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
            Text("$used / $total $unit", style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(height: 10, width: double.infinity, decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(5))),
            AnimatedContainer(duration: const Duration(seconds: 1), height: 10, width: MediaQuery.of(context).size.width * 0.75 * percentage, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5), boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 10)])),
          ],
        )
      ],
    );
  }

  Widget _buildStatBox(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color.withOpacity(0.5), size: 28),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
              Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildPlanRow(String title, int count, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color, blurRadius: 5)])), const SizedBox(width: 15), Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))]),
        Text("$count Users", style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

// ============================================================================
// --- ADMIN SPECIFIC PAINTERS ---
// ============================================================================

class AdminGlowingText extends StatefulWidget {
  final String text; const AdminGlowingText({Key? key, required this.text}) : super(key: key);
  @override _AdminGlowingTextState createState() => _AdminGlowingTextState();
}
class _AdminGlowingTextState extends State<AdminGlowingText> with SingleTickerProviderStateMixin {
  late AnimationController _c; @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, __) => ShaderMask(shaderCallback: (r) => LinearGradient(colors: const [Colors.redAccent, Colors.orangeAccent, Colors.redAccent], stops: [0.0, 0.5 + (sin(_c.value * 2 * pi) * 0.2), 1.0]).createShader(r), child: Text(widget.text, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3))));
}

class AdminLiveBackgroundX extends StatefulWidget { const AdminLiveBackgroundX({Key? key}) : super(key: key); @override _AdminLiveBackgroundXState createState() => _AdminLiveBackgroundXState(); }
class _AdminLiveBackgroundXState extends State<AdminLiveBackgroundX> with SingleTickerProviderStateMixin {
  late AnimationController _c; @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _AdminWavePainterX(_c.value)));
}
class _AdminWavePainterX extends CustomPainter {
  final double progress; _AdminWavePainterX(this.progress);
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.redAccent.withOpacity(0.02)..strokeWidth = 2.0..style = PaintingStyle.stroke;
    double offset = progress * (size.width * 2);
    for (double i = -size.height * 2; i < size.width * 2; i += 40) { canvas.drawLine(Offset(i + offset, 0), Offset(i - size.height + offset, size.height), p); }
  }
  @override bool shouldRepaint(covariant CustomPainter old) => true;
}

class _ShatterPainterX extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.03)..strokeWidth = 1.0..style = PaintingStyle.stroke;
    final path = Path();
    for (int i = 0; i < 8; i++) {
      double cx = Random(i).nextDouble() * size.width; double cy = Random(i+1).nextDouble() * size.height;
      for (int j = 0; j < 3; j++) { double a = (j * 45) * (pi / 180); path.moveTo(cx, cy); path.lineTo(cx + cos(a) * 40, cy + sin(a) * 40); }
    }
    canvas.drawPath(path, p);
  }
  @override bool shouldRepaint(CustomPainter old) => false;
}
