import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart'; 
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart'; 

import 'ai_assistant_screen.dart';
import 'auth/login_screen.dart'; 
import 'help_support_screen.dart';
import 'privacy_policy_screen.dart';
import 'billing_screen.dart';
import 'create_project_screen.dart';
import 'admin/admin_dashboard_screen.dart';
import 'project_dashboard_screen.dart'; 

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  String activeTab = "home"; 
  bool isListView = false; 
  bool isSearchVisible = false;
  String searchQuery = "";
  String currentFilter = "All";
  
  bool isDrawerOpen = false;

  bool isEditingProfile = false;
  bool isEditingPassword = false;
  bool isActionLoading = false; 
  
  List<Map<String, dynamic>> projects = [];
  bool isLoading = true;
  Map profileData = {"username": "Loading...", "email": "Loading...", "plan": "No Plan", "role": "user", "plan_expiry": null};

  bool isMaintenanceMode = false;
  bool _hasShownBroadcast = false;

  Timer? _countdownTicker; 

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _oldPassController = TextEditingController();
  final TextEditingController _newPassController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchRealData();
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && activeTab == "home" && profileData['plan_expiry'] != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    _searchController.dispose();
    _userController.dispose();
    _emailController.dispose();
    _oldPassController.dispose();
    _newPassController.dispose();
    super.dispose();
  }

  String _getSubscriptionCountdown() {
    if (profileData['plan_expiry'] == null) return "No Expiry Limits";
    try {
      DateTime expiryTime = DateTime.parse(profileData['plan_expiry']);
      Duration difference = expiryTime.difference(DateTime.now());
      
      if (difference.isNegative) {
        return "Plan Expired";
      }
      
      String days = difference.inDays.toString().padLeft(2, '0');
      String hours = (difference.inHours % 24).toString().padLeft(2, '0');
      String minutes = (difference.inMinutes % 60).toString().padLeft(2, '0');
      String seconds = (difference.inSeconds % 60).toString().padLeft(2, '0');
      
      return "${days}d : ${hours}h : ${minutes}m : ${seconds}s";
    } catch (e) {
      return "Lifetime Locked";
    }
  }

  Future<void> _fetchRealData() async {
    setState(() => isLoading = true);
    try {
      final profileRes = await http.get(Uri.parse('/api/user/profile'));
      if (profileRes.statusCode == 200) {
        final pData = jsonDecode(profileRes.body);
        
        if (pData['role'] == 'admin') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const AdminDashboardScreen()));
          return;
        }

        setState(() {
          profileData = pData;
          _userController.text = pData['username'];
          _emailController.text = pData['email'];
          isMaintenanceMode = pData['maintenance_mode'] ?? false;
        });

        String announcement = pData['announcement_msg'] ?? "";
        if (announcement.isNotEmpty && !_hasShownBroadcast && !isMaintenanceMode) {
          _hasShownBroadcast = true;
          _showBroadcastDialog(announcement);
        }

      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const LoginScreen()));
        return;
      }

      if (!isMaintenanceMode) {
        final projectsRes = await http.get(Uri.parse('/api/user/projects'));
        if (projectsRes.statusCode == 200) {
          setState(() {
            projects = List<Map<String, dynamic>>.from(jsonDecode(projectsRes.body));
          });
        }
      }
    } catch (e) {
      PremiumToast.show(context, "Network Error!", false);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    try {
      await http.post(Uri.parse('/api/logout'));
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const LoginScreen()));
    } catch (e) {
      PremiumToast.show(context, "Logout failed. Please check connection.", false);
    }
  }

  Future<void> _handleProjectAction(String projectId, String action) async {
    try {
      PremiumToast.show(context, "Processing...", true);
      final res = await http.post(Uri.parse('/api/project/$projectId/action'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'action': action}));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) { 
        PremiumToast.show(context, data['message'], true); 
        _fetchRealData();
      } 
      else { PremiumToast.show(context, data['message'], false); }
    } catch (e) { PremiumToast.show(context, "Action Failed!", false); }
  }

  Future<void> _updateProfile() async {
    setState(() => isActionLoading = true);
    try {
      final res = await http.post(Uri.parse('/api/settings/update'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'update_type': 'profile', 'new_username': _userController.text, 'new_email': _emailController.text}));
      final data = jsonDecode(res.body);
      PremiumToast.show(context, data['message'], res.statusCode == 200);
      if (res.statusCode == 200) { setState(() => isEditingProfile = false); _fetchRealData(); }
    } catch (e) { PremiumToast.show(context, "Update Failed!", false); } finally { setState(() => isActionLoading = false); }
  }

  Future<void> _updatePassword() async {
    if (_oldPassController.text.isEmpty || _newPassController.text.isEmpty) { PremiumToast.show(context, "Both passwords are required!", false); return; }
    setState(() => isActionLoading = true);
    try {
      final res = await http.post(Uri.parse('/api/settings/update'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'update_type': 'password', 'old_password': _oldPassController.text, 'new_password': _newPassController.text}));
      final data = jsonDecode(res.body);
      PremiumToast.show(context, data['message'], res.statusCode == 200);
      if (res.statusCode == 200) { setState(() { isEditingPassword = false; _oldPassController.clear(); _newPassController.clear(); }); }
    } catch (e) { PremiumToast.show(context, "Update Failed!", false); } finally { setState(() => isActionLoading = false); }
  }

  List<Map<String, dynamic>> get filteredProjects {
    List<Map<String, dynamic>> filtered = projects;
    if (currentFilter != "All") filtered = filtered.where((p) => p['status'] == currentFilter).toList();
    if (searchQuery.isNotEmpty) filtered = filtered.where((p) => p['name'].toString().toLowerCase().contains(searchQuery.toLowerCase())).toList();
    return filtered;
  }

  List<InlineSpan> _parseMessageWithLinks(String text) {
    List<InlineSpan> spans = [];
    final RegExp linkRegExp = RegExp(r'\{([^}]+)\s*\(([^)]+)\)\}|((?:https?:\/\/|t\.me\/|tg:\/\/)[^\s]+)');
    
    int lastMatchEnd = 0;
    for (final match in linkRegExp.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.6),
        ));
      }
      
      String? customTitle = match.group(1);
      String? customUrl = match.group(2);
      String? standaloneUrl = match.group(3);
      
      String urlToLaunch = customUrl ?? standaloneUrl ?? match.group(0)!;
      String textToShow = customTitle ?? standaloneUrl ?? match.group(0)!;
      
      if (!urlToLaunch.startsWith('http') && !urlToLaunch.startsWith('tg:')) {
        urlToLaunch = 'https://' + urlToLaunch.replaceAll(RegExp(r'^https?:\/\/'), '');
      }
      
      spans.add(TextSpan(
        text: textToShow,
        style: const TextStyle(
          color: Color(0xFF45F3FF), 
          fontSize: 15, 
          height: 1.6, 
          fontWeight: FontWeight.bold, 
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFF45F3FF)
        ),
        recognizer: TapGestureRecognizer()..onTap = () async {
          final uri = Uri.parse(urlToLaunch);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            await launchUrl(uri);
          }
        },
      ));
      
      lastMatchEnd = match.end;
    }
    
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.6),
      ));
    }
    
    return spans;
  }

  void _showBroadcastDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xFF082236).withOpacity(0.85),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16), 
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 25), 
          decoration: BoxDecoration(
            color: const Color(0xFF45F3FF).withOpacity(0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.3), width: 1.5),
            boxShadow: [BoxShadow(color: const Color(0xFF45F3FF).withOpacity(0.1), blurRadius: 20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min, 
            children: [
              const Icon(Icons.campaign_rounded, color: Color(0xFF45F3FF), size: 45),
              const SizedBox(height: 15),
              const Text(
                "ADMIN ANNOUNCEMENT", 
                style: TextStyle(color: Color(0xFF45F3FF), fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(children: _parseMessageWithLinks(message)),
              ),
              
              const SizedBox(height: 30),
              
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF45F3FF).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF45F3FF)),
                  ),
                  child: const Center(child: Text("UNDERSTOOD", style: TextStyle(color: Color(0xFF45F3FF), fontWeight: FontWeight.bold, letterSpacing: 2))),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (profileData['role'] == 'admin') return const Scaffold(backgroundColor: Color(0xFF0A0A10), body: Center(child: CircularProgressIndicator(color: Colors.redAccent)));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A10),
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0xFF0F3B57), Color(0xFF082236), Color(0xFF020E18)], radius: 1.5))),
          const Positioned.fill(child: LiveCyberBackground()),
          const Positioned.fill(child: IgnorePointer(child: FullScreenWaveSheen())), 
          
          SafeArea(
            child: isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF45F3FF)))
              : isMaintenanceMode 
                  ? _buildMaintenanceScreen() 
                  : Column(
                      children: [
                        _buildTopNavbar(),
                        Expanded(child: activeTab == "home" ? _buildHomeTab() : _buildSettingsTab()),
                      ],
                    ),
          ),
          if (!isMaintenanceMode) _buildCustomDrawer(),
        ],
      ),
    );
  }

  Widget _buildMaintenanceScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.build_circle_outlined, color: Color(0xFF45F3FF), size: 100),
          const SizedBox(height: 25),
          const AnimatedGradientText(text: "UNDER MAINTENANCE"),
          const SizedBox(height: 15),
          const Text("We are upgrading our cloud infrastructure.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 16, height: 1.5)),
          const Text("Please check back shortly.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 14)),
          const SizedBox(height: 50),
          
          GestureDetector(
            onTap: _fetchRealData,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 30),
              decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.5))),
              child: const Text("RETRY CONNECTION", style: TextStyle(color: Color(0xFF45F3FF), fontWeight: FontWeight.bold, letterSpacing: 2)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTopNavbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.menu_open_rounded, color: Color(0xFF45F3FF), size: 32), onPressed: () => setState(() => isDrawerOpen = true)),
          const AnimatedGradientText(text: "SILENT HOSTING"),
          Container(width: 42, height: 42, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.5), width: 1.5), color: Colors.white.withOpacity(0.05), image: const DecorationImage(image: AssetImage("assets/logo.png"), fit: BoxFit.cover)), child: const Center(child: Icon(Icons.person, color: Colors.white24, size: 20))),
        ],
      ),
    );
  }

  Widget _buildCustomDrawer() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
      top: 0, bottom: 0, left: isDrawerOpen ? 0 : -300, width: 280,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(color: const Color(0xFF082236).withOpacity(0.95), border: const Border(right: BorderSide(color: Color(0xFF45F3FF), width: 1.5)), boxShadow: [BoxShadow(color: const Color(0xFF45F3FF).withOpacity(0.2), blurRadius: 30)]),
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _RealisticShatterPainter())), 
                SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("MENU", style: TextStyle(color: Color(0xFF45F3FF), fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3)), IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => setState(() => isDrawerOpen = false))])),
                      const Divider(color: Colors.white10),
                      
                      _drawerItem(Icons.home_filled, "Dashboard", () { _fetchRealData(); setState(() { isDrawerOpen = false; activeTab = 'home'; }); }),
                      _drawerItem(Icons.add_box, "Create New Project", () { setState(() => isDrawerOpen = false); Navigator.push(context, MaterialPageRoute(builder: (c) => const CreateProjectScreen())); }),
                      
                      _drawerItem(Icons.auto_awesome, "Silent AI", () { 
                        setState(() => isDrawerOpen = false); 
                        Navigator.push(context, MaterialPageRoute(builder: (c) => const AiAssistantScreen())); 
                      }), 
                      
                      _drawerItem(Icons.person, "Profile Settings", () { setState(() { isDrawerOpen = false; activeTab = 'settings'; }); }),
                      _drawerItem(Icons.credit_card, "Billing & Plans", () { setState(() => isDrawerOpen = false); Navigator.push(context, MaterialPageRoute(builder: (c) => const BillingScreen())); }),
                      _drawerItem(Icons.security, "Privacy & Policy", () { setState(() => isDrawerOpen = false); Navigator.push(context, MaterialPageRoute(builder: (c) => const PrivacyPolicyScreen())); }),
                      _drawerItem(Icons.help_outline, "Help & Support", () { setState(() => isDrawerOpen = false); Navigator.push(context, MaterialPageRoute(builder: (c) => const HelpSupportScreen())); }),
                      
                      const Spacer(),
                      
                      if (profileData['role'] == 'admin') ...[
                        const Divider(color: Colors.redAccent),
                        _drawerItem(Icons.admin_panel_settings, "GOD MODE (Admin)", () { 
                          setState(() => isDrawerOpen = false); 
                          Navigator.push(context, MaterialPageRoute(builder: (c) => const AdminDashboardScreen())); 
                        }, color: Colors.redAccent),
                      ],
                      
                      const Divider(color: Colors.white10),
                      _drawerItem(Icons.logout, "Logout", _handleLogout, color: Colors.redAccent),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawerItem(IconData icon, String text, VoidCallback onTap, {Color color = const Color(0xFF45F3FF)}) {
    return ListTile(leading: RotatingIcon(icon: icon, color: color), title: Text(text, style: TextStyle(color: color == Colors.redAccent ? Colors.redAccent : Colors.white, fontWeight: FontWeight.bold)), onTap: onTap, contentPadding: const EdgeInsets.only(left: 25, right: 25, top: 5, bottom: 5));
  }

  Widget _buildHomeTab() {
    return GestureDetector(
      onTap: () { if (isDrawerOpen) setState(() => isDrawerOpen = false); }, 
      child: RefreshIndicator( 
        color: const Color(0xFF45F3FF), backgroundColor: const Color(0xFF082236),
        onRefresh: _fetchRealData,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const SizedBox(height: 10),
            _buildSubscriptionLine(),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildViewToggle(), 
                Row(
                  children: [
                    if (!isSearchVisible) ...[
                      IconButton(icon: const Icon(Icons.search, color: Colors.white60), onPressed: () => setState(() => isSearchVisible = true)),
                      IconButton(icon: const Icon(Icons.add_box_outlined, color: Color(0xFF45F3FF)), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (c) => const CreateProjectScreen())); }),
                    ] else ...[
                      _buildAnimatedSearchBar(),
                    ]
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildStatusFilters(),
            const SizedBox(height: 25),
            
            filteredProjects.isEmpty 
              ? const Center(child: Text("No projects found", style: TextStyle(color: Colors.white38)))
              : isListView ? _buildProjectList() : _buildProjectGrid(),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscriptionLine() {
    String planName = profileData['plan'] ?? "No Plan";
    bool hasActivePlan = planName != "No Plan" && (profileData['plan_type'] == 'pro' || profileData['plan_type'] == 'basic' || profileData['plan_type'] == 'free');
    
    Color tierColor = planName.contains("Pro") 
        ? const Color(0xFF45F3FF) 
        : planName.contains("Basic") 
            ? Colors.blueAccent 
            : planName.contains("Free") 
                ? Colors.amber 
                : Colors.white38;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: tierColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: tierColor.withOpacity(0.2), width: 1.2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(hasActivePlan ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: tierColor, size: 16),
              const SizedBox(width: 8),
              Text(
                planName.toUpperCase(),
                style: TextStyle(color: tierColor, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ],
          ),
          Text(
            hasActivePlan ? _getSubscriptionCountdown() : "",
            style: TextStyle(
              color: hasActivePlan ? Colors.greenAccent : Colors.redAccent,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilters() {
    int countAll = projects.length;
    int countOnline = projects.where((p) => p['status'] == 'Online').length;
    int countOffline = projects.where((p) => p['status'] == 'Offline').length;
    int countCrashed = projects.where((p) => p['status'] == 'Crashed').length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterBadge("All", countAll, const Color(0xFF45F3FF)),
          const SizedBox(width: 10),
          _filterBadge("Online", countOnline, Colors.greenAccent),
          const SizedBox(width: 10),
          _filterBadge("Offline", countOffline, Colors.white54),
          const SizedBox(width: 10),
          _filterBadge("Crashed", countCrashed, Colors.redAccent),
        ],
      ),
    );
  }

  Widget _filterBadge(String status, int count, Color color) {
    bool isSelected = currentFilter == status;
    return GestureDetector(
      onTap: () => setState(() => currentFilter = status),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.only(left: 15, right: 15, top: 8, bottom: 8),
        decoration: BoxDecoration(color: isSelected ? color.withOpacity(0.15) : Colors.transparent, borderRadius: BorderRadius.circular(20), border: Border.all(color: isSelected ? color : Colors.white10)),
        child: Row(children: [Text(status, style: TextStyle(color: isSelected ? color : Colors.white54, fontWeight: FontWeight.bold, fontSize: 13)), const SizedBox(width: 6), Container(padding: const EdgeInsets.only(left: 6, right: 6, top: 2, bottom: 2), decoration: BoxDecoration(color: isSelected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)), child: Text(count.toString(), style: TextStyle(color: isSelected ? color : Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)))]),
      ),
    );
  }

  Widget _buildAnimatedSearchBar() {
    return Container(
      width: MediaQuery.of(context).size.width * 0.55, height: 45, padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.5))),
      child: TextField(controller: _searchController, autofocus: true, onChanged: (v) => setState(() => searchQuery = v), style: const TextStyle(color: Colors.white, fontSize: 14), decoration: InputDecoration(hintText: "Search...", hintStyle: const TextStyle(color: Colors.white24), border: InputBorder.none, suffixIcon: IconButton(icon: const Icon(Icons.close, size: 18, color: Colors.redAccent), onPressed: () => setState(() { isSearchVisible = false; searchQuery = ""; _searchController.clear(); })))),
    );
  }

  Widget _buildViewToggle() {
    return Container(
      padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        _toggleBtn(Icons.grid_view_rounded, !isListView, () => setState(() => isListView = false)),
        _toggleBtn(Icons.list_rounded, isListView, () => setState(() => isListView = true)),
      ]),
    );
  }

  Widget _toggleBtn(IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: active ? const Color(0xFF45F3FF).withOpacity(0.15) : Colors.transparent, borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 20, color: active ? const Color(0xFF45F3FF) : Colors.white24)));
  }

  Widget _buildProjectCard(Map<String, dynamic> p) {
    Color statusColor = p['status'] == 'Online' ? Colors.greenAccent : p['status'] == 'Offline' ? Colors.white38 : p['status'] == 'Starting' || p['status'] == 'Building' ? Colors.amber : Colors.redAccent;
    
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => ProjectDashboardScreen(projectId: p['id'].toString(), projectName: p['name']))),
      child: Container(
        decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.03), borderRadius: BorderRadius.circular(20), border: Border.all(color: statusColor.withOpacity(0.3))),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _LightShatterPainter())), 
            Padding(
              padding: const EdgeInsets.all(15.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Icon(Icons.terminal, color: statusColor), _buildProjectMenu(p)]),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['name'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 5),
                      Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor, boxShadow: [BoxShadow(color: statusColor, blurRadius: 5)])), const SizedBox(width: 6), Text(p['status'], style: TextStyle(color: statusColor, fontSize: 12))]),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectMenu(Map<String, dynamic> p) {
    bool isOnline = p['status'] == 'Online';
    String pid = p['id'].toString(); 
    
    return Theme(
      data: Theme.of(context).copyWith(popupMenuTheme: PopupMenuThemeData(color: const Color(0xFF082236).withOpacity(0.95), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: const Color(0xFF45F3FF).withOpacity(0.4), width: 1.5)))),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.white54),
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(value: isOnline ? 'stop' : 'start', child: Row(children: [Icon(isOnline ? Icons.stop_circle : Icons.play_circle_fill, size: 18, color: isOnline ? Colors.amber : Colors.greenAccent), const SizedBox(width: 10), Text(isOnline ? "Stop Project" : "Start Project", style: const TextStyle(color: Colors.white))])),
          const PopupMenuItem<String>(value: 'redeploy', child: Row(children: [Icon(Icons.refresh, size: 18, color: Colors.blueAccent), SizedBox(width: 10), Text("Re-deploy", style: TextStyle(color: Colors.white))])),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.redAccent), SizedBox(width: 10), Text("Delete Project", style: TextStyle(color: Colors.redAccent))])),
        ],
        onSelected: (val) => _handleProjectAction(pid, val),
      ),
    );
  }

  Widget _buildProjectGrid() { return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1.1), itemCount: filteredProjects.length, itemBuilder: (c, i) => _buildProjectCard(filteredProjects[i])); }
  Widget _buildProjectList() { return ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: filteredProjects.length, itemBuilder: (c, i) => Padding(padding: const EdgeInsets.only(bottom: 10), child: _buildProjectCard(filteredProjects[i]))); }

  Widget _buildSettingsTab() {
    return GestureDetector(
      onTap: () { if (isDrawerOpen) setState(() => isDrawerOpen = false); },
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSettingsSection("CURRENT PLAN", [Text(profileData['plan'], style: const TextStyle(color: Color(0xFF45F3FF), fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2))]),
          const SizedBox(height: 20),
          _buildSettingsSection("PROFILE INFO", [
            _buildBlockedInput("Username", _userController, isEditingProfile), const SizedBox(height: 15), _buildBlockedInput("Email Address", _emailController, isEditingProfile),
            if (isEditingProfile) Padding(padding: const EdgeInsets.only(top: 15), child: Center(child: CompactShatteredButton(text: isActionLoading ? "WAIT..." : "UPDATE PROFILE", onPressed: _updateProfile))),
          ], isEditing: isEditingProfile, onEditToggle: () => setState(() { isEditingProfile = !isEditingProfile; if (!isEditingProfile) { _userController.text = profileData['username']; _emailController.text = profileData['email']; } })),
          const SizedBox(height: 20),
          _buildSettingsSection("SECURITY", [
            if (isEditingPassword) ...[ _buildBlockedInput("Old Password", _oldPassController, true, isPass: true), const SizedBox(height: 15) ],
            _buildBlockedInput("New Password", _newPassController, isEditingPassword, isPass: true),
            if (isEditingPassword) Padding(padding: const EdgeInsets.only(top: 15), child: Center(child: CompactShatteredButton(text: isActionLoading ? "WAIT..." : "UPDATE PASSWORD", onPressed: _updatePassword))),
          ], isEditing: isEditingPassword, onEditToggle: () => setState(() { isEditingPassword = !isEditingPassword; _oldPassController.clear(); _newPassController.clear(); })),
          const SizedBox(height: 30),
          _buildSettingsSection("DANGER ZONE", [
            const Text("Deleting your account is permanent. All your projects will be destroyed.", style: TextStyle(color: Colors.white30, fontSize: 12)),
            const SizedBox(height: 15),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.1), side: const BorderSide(color: Colors.redAccent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: _showDeleteAccountDialog, child: const Text("DELETE ACCOUNT", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)))
          ]),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(String title, List<Widget> children, {bool isEditing = false, VoidCallback? onEditToggle}) {
    return Container(
      padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.02), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)), if (onEditToggle != null) IconButton(icon: Icon(isEditing ? Icons.close : Icons.edit_note, color: isEditing ? Colors.redAccent : const Color(0xFF45F3FF), size: 22), onPressed: onEditToggle)]), const SizedBox(height: 15), ...children]),
    );
  }

  Widget _buildBlockedInput(String label, TextEditingController controller, bool isUnlocked, {bool isPass = false}) {
    return TextField(controller: controller, enabled: isUnlocked, obscureText: isPass, style: TextStyle(color: isUnlocked ? Colors.white : Colors.white60), decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(color: Colors.white24, fontSize: 12), filled: true, fillColor: isUnlocked ? Colors.white.withOpacity(0.05) : Colors.transparent, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isUnlocked ? const Color(0xFF45F3FF) : Colors.white10)), disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10))));
  }

  void _showDeleteAccountDialog() {
    TextEditingController confirmEmail = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF082236), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25), side: BorderSide(color: Colors.redAccent.withOpacity(0.3), width: 1)),
        title: const Text("Confirm Deletion", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [const Text("To confirm, please type your email below.", style: TextStyle(color: Colors.white60, fontSize: 13)), const SizedBox(height: 15), TextField(controller: confirmEmail, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: profileData['email'], hintStyle: const TextStyle(color: Colors.white10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.white38))), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), onPressed: () async { if (confirmEmail.text == profileData['email']) { Navigator.pop(context); setState(() => isActionLoading = true); try { final res = await http.post(Uri.parse('/api/settings/delete-account'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'email': confirmEmail.text})); final data = jsonDecode(res.body); PremiumToast.show(context, data['message'], res.statusCode == 200); if (res.statusCode == 200) Future.delayed(const Duration(seconds: 2), () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const LoginScreen()))); } catch(e) { PremiumToast.show(context, "Network Error", false); } finally { setState(() => isActionLoading = false); } } }, child: const Text("CONFIRM"))],
      ),
    );
  }
}

class LiveCyberBackground extends StatefulWidget { const LiveCyberBackground({Key? key}) : super(key: key); @override _LiveCyberBackgroundState createState() => _LiveCyberBackgroundState(); }
class _LiveCyberBackgroundState extends State<LiveCyberBackground> with SingleTickerProviderStateMixin {
  late AnimationController _c; @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _DiagonalWavePainter(_c.value)));
}
class _DiagonalWavePainter extends CustomPainter {
  final double progress; _DiagonalWavePainter(this.progress);
  @override void paint(Canvas canvas, Size size) { 
    final p = Paint()..color = const Color(0xFF45F3FF).withOpacity(0.04)..strokeWidth = 1.5..style = PaintingStyle.stroke; 
    double offset = progress * (size.width * 2); 
    for (double i = -size.height * 2; i < size.width * 2; i += 40) { canvas.drawLine(Offset(i + offset, 0), Offset(i - size.height + offset, size.height), p); } 
  }
  @override bool shouldRepaint(covariant CustomPainter old) => true;
}
class RotatingIcon extends StatefulWidget { final IconData icon; final Color color; const RotatingIcon({Key? key, required this.icon, required this.color}) : super(key: key); @override _RotatingIconState createState() => _RotatingIconState(); }
class _RotatingIconState extends State<RotatingIcon> with SingleTickerProviderStateMixin {
  late AnimationController _c; @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, __) => Transform.rotate(angle: _c.value * 2 * pi, child: Icon(widget.icon, color: widget.color, size: 20)));
}
class CompactShatteredButton extends StatefulWidget { final String text; final VoidCallback onPressed; const CompactShatteredButton({Key? key, required this.text, required this.onPressed}) : super(key: key); @override _CompactShatteredButtonState createState() => _CompactShatteredButtonState(); }
class _CompactShatteredButtonState extends State<CompactShatteredButton> with SingleTickerProviderStateMixin {
  late AnimationController _wave; @override void initState() { super.initState(); _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(); }
  @override void dispose() { _wave.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) { return GestureDetector(onTap: widget.onPressed, child: ClipRRect(borderRadius: BorderRadius.circular(15), child: Container(width: 180, height: 45, decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.7))), child: Stack(children: [CustomPaint(size: const Size(180, 45), painter: _RealisticShatterPainter()), AnimatedBuilder(animation: _wave, builder: (_, __) => Positioned(left: -100 + (_wave.value * 400), top: -50, bottom: -50, child: Transform.rotate(angle: 0.4, child: Container(width: 10, decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), boxShadow: [BoxShadow(color: const Color(0xFF45F3FF), blurRadius: 20)]))))), Center(child: Text(widget.text, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2)))])))); }
}
class AnimatedGradientText extends StatefulWidget { final String text; const AnimatedGradientText({Key? key, required this.text}) : super(key: key); @override _AnimatedGradientTextState createState() => _AnimatedGradientTextState(); }
class _AnimatedGradientTextState extends State<AnimatedGradientText> with SingleTickerProviderStateMixin {
  late AnimationController _c; @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, __) => ShaderMask(shaderCallback: (r) => LinearGradient(colors: const [Color(0xFFA855F7), Color(0xFF22D3EE), Color(0xFF3B82F6)], stops: [0.0, 0.5 + (sin(_c.value * 2 * pi) * 0.2), 1.0]).createShader(r), child: Text(widget.text, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2))));
}
class _LightShatterPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) { final p = Paint()..color = Colors.white.withOpacity(0.05)..strokeWidth = 0.8..style = PaintingStyle.stroke; final path = Path(); path.moveTo(size.width * 0.7, 0); path.lineTo(size.width, size.height * 0.4); path.moveTo(0, size.height * 0.6); path.lineTo(size.width * 0.4, size.height); canvas.drawPath(path, p); }
  @override bool shouldRepaint(covariant CustomPainter old) => false;
}
class _RealisticShatterPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) { final p = Paint()..color = Colors.white.withOpacity(0.2)..strokeWidth = 1.0..style = PaintingStyle.stroke; final path = Path(); for (int i = 0; i < 10; i++) { double cx = Random(i).nextDouble() * size.width; double cy = Random(i+1).nextDouble() * size.height; for (int j = 0; j < 5; j++) { double a = (j * 45) * (pi / 180); path.moveTo(cx, cy); path.lineTo(cx + cos(a) * 30, cy + sin(a) * 30); } } canvas.drawPath(path, p); }
  @override bool shouldRepaint(CustomPainter old) => false;
}

class FullScreenWaveSheen extends StatefulWidget {
  const FullScreenWaveSheen({Key? key}) : super(key: key);
  @override
  _FullScreenWaveSheenState createState() => _FullScreenWaveSheenState();
}

class _FullScreenWaveSheenState extends State<FullScreenWaveSheen> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    double screenHeight = MediaQuery.of(context).size.height;
    
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(-screenWidth + (_c.value * screenWidth * 2.5), 0),
          child: Transform.rotate(
            angle: 0.5, 
            child: Container(
              width: 50,
              height: screenHeight * 2, 
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.white.withOpacity(0.25), 
                    Colors.transparent
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}