import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:html' as html; // ڈاؤن لوڈ اور لنکس کے لیے

// PremiumToast کے لیے امپورٹ (اپنے پاتھ کے حساب سے ایڈجسٹ کر لیں)
import '../auth/login_screen.dart'; 

class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({Key? key}) : super(key: key);
  @override
  _UsersManagementScreenState createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen> with TickerProviderStateMixin {
  String currentFilter = "All"; // All, Deployed, No Plan, Free, Basic, Pro
  bool isLoading = true;
  bool isActionLoading = false;
  
  List<Map<String, dynamic>> allUsers = [];
  
  // 🔥 لائیو سرچ اسٹیٹ ویری ایبلز
  bool isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // Detail View State
  Map<String, dynamic>? selectedUser;
  List<Map<String, dynamic>> userProjects = [];
  bool isLoadingDetails = false;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  @override
  void dispose() {
    _searchController.dispose(); // میموری لیک پروٹیکشن
    super.dispose();
  }

  // ============================================================================
  // --- REAL ADMIN APIs ---
  // ============================================================================

  Future<void> _fetchUsers() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse('/api/admin/users'));
      if (res.statusCode == 200) {
        setState(() {
          allUsers = List<Map<String, dynamic>>.from(jsonDecode(res.body));
        });
      }
    } catch (e) {
      PremiumToast.show(context, "Network Error fetching users", false);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _fetchUserDetails(Map<String, dynamic> user) async {
    setState(() {
      selectedUser = user;
      isLoadingDetails = true;
    });
    try {
      final res = await http.get(Uri.parse('/api/admin/users/${user['id']}'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          selectedUser = data['user_info']; 
          userProjects = List<Map<String, dynamic>>.from(data['projects']);
        });
      }
    } catch (e) {
      PremiumToast.show(context, "Failed to load user details", false);
      setState(() => selectedUser = null);
    } finally {
      if (mounted) setState(() => isLoadingDetails = false);
    }
  }

  Future<void> _handleUserAction(String action, {String? newPassword}) async {
    if (selectedUser == null) return;
    setState(() => isActionLoading = true);
    try {
      Map<String, dynamic> payload = {'action': action};
      if (newPassword != null) payload['new_password'] = newPassword;

      final res = await http.post(
        Uri.parse('/api/admin/users/${selectedUser!['id']}/action'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload)
      );
      final data = jsonDecode(res.body);
      
      if (res.statusCode == 200) {
        PremiumToast.show(context, data['message'], true);
        if (action == 'delete') {
          setState(() => selectedUser = null);
          _fetchUsers();
        } else if (action == 'reset_password') {
          _fetchUsers(); 
        } else {
          _fetchUserDetails(selectedUser!);
        }
      } else {
        PremiumToast.show(context, data['message'], false);
      }
    } catch (e) {
      PremiumToast.show(context, "Action Failed", false);
    } finally {
      if (mounted) setState(() => isActionLoading = false);
    }
  }

  Future<void> _handleProjectAction(String projectId, String action) async {
    setState(() => isActionLoading = true);
    try {
      final res = await http.post(
        Uri.parse('/api/admin/projects/$projectId/action'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': action})
      );
      final data = jsonDecode(res.body);
      
      if (res.statusCode == 200) {
        PremiumToast.show(context, data['message'], true);
        _fetchUserDetails(selectedUser!); 
      } else {
        PremiumToast.show(context, data['message'], false);
      }
    } catch (e) {
      PremiumToast.show(context, "Action Failed", false);
    } finally {
      if (mounted) setState(() => isActionLoading = false);
    }
  }

  void _downloadSourceCode(String projectId) {
    final downloadUrl = '/api/admin/projects/$projectId/download';
    html.window.open(downloadUrl, '_blank');
    PremiumToast.show(context, "Downloading Source Code...", true);
  }

  void _showPasswordResetDialog() {
    TextEditingController passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF140518),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.redAccent.withOpacity(0.5))),
          title: Text("Reset Password\n@${selectedUser!['username']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          content: TextField(
            controller: passCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Enter new password",
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white10)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.redAccent)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () {
                if (passCtrl.text.isNotEmpty && passCtrl.text.length >= 6) {
                  Navigator.pop(context);
                  _handleUserAction('reset_password', newPassword: passCtrl.text);
                } else {
                  PremiumToast.show(context, "Password must be at least 6 chars", false);
                }
              },
              child: const Text("Reset Now", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      }
    );
  }

  // 🔥 لائیو ٹیب کاؤنٹرز ہینڈلر (سرچ سے بلکل آزاد تاکہ مینیو پر کل کاؤنٹ نظر آئے)
  int _getUserCountByFilter(String filter) {
    if (filter == "All") return allUsers.length;
    if (filter == "Deployed") {
      return allUsers.where((u) => (int.tryParse(u['project_count'].toString()) ?? 0) > 0).length;
    }
    if (filter == "No Plan") {
      return allUsers.where((u) {
        final plan = u['plan']?.toString().toLowerCase() ?? '';
        return plan.isEmpty || plan.contains("no plan") || plan.contains("none");
      }).length;
    }
    String targetPlan = filter == "Free" ? "Free Tier" : filter == "Basic" ? "Basic Plan" : "Pro Plan";
    return allUsers.where((u) => u['plan'].toString().toLowerCase() == targetPlan.toLowerCase()).length;
  }

  // ============================================================================
  // --- SMART FILTER & LIVE SEARCH LOGIC (Fusion Engine) ---
  // ============================================================================
  List<Map<String, dynamic>> get filteredUsers {
    List<Map<String, dynamic>> list = List.from(allUsers);
    
    // 🔍 لائیو سرچ فلٹر پائپ لائن (Case-Insensitive Surgical Routing)
    if (isSearching && _searchController.text.isNotEmpty) {
      String query = _searchController.text.toLowerCase();
      list.retainWhere((u) => (u['username'] ?? '').toString().toLowerCase().contains(query));
    }

    if (currentFilter == "Deployed") {
      list.retainWhere((u) {
        final count = int.tryParse(u['project_count'].toString()) ?? 0;
        return count > 0;
      });
      list.sort((a, b) {
        final countA = int.tryParse(a['project_count'].toString()) ?? 0;
        final countB = int.tryParse(b['project_count'].toString()) ?? 0;
        return countB.compareTo(countA);
      });
      return list;
    }
    
    if (currentFilter == "No Plan") {
      list.retainWhere((u) {
        final plan = u['plan']?.toString().toLowerCase() ?? '';
        return plan.isEmpty || plan.contains("no plan") || plan.contains("none");
      });
      return list;
    }
    
    if (currentFilter == "All") return list;
    
    String targetPlan = currentFilter == "Free" ? "Free Tier" : currentFilter == "Basic" ? "Basic Plan" : "Pro Plan";
    list.retainWhere((u) => u['plan'].toString().toLowerCase() == targetPlan.toLowerCase());
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0xFF2A0815), Color(0xFF140518), Color(0xFF0A0A12)], radius: 1.5))),
          const Positioned.fill(child: AdminLiveBackground()),

          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: IndexedStack(
                    index: selectedUser == null ? 0 : 1,
                    children: [
                      _buildUsersListScreen(),
                      selectedUser == null ? const SizedBox() : _buildUserDetailsScreen(),
                    ],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // ============================================================================
  // --- INLINE EXPANDABLE SEARCH NAVBAR ---
  // ============================================================================
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Row(
        children: [
          if (selectedUser != null) ...[
            IconButton(icon: const Icon(Icons.arrow_back, color: Colors.redAccent), onPressed: () => setState(() => selectedUser = null)),
            const Icon(Icons.group_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            const Text("USERS MANAGEMENT", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
          ] else if (isSearching) ...[
            // 🔥 الٹرا اسمارٹ ان لائن ان پٹ باکس
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (val) => setState(() {}), // ٹائپنگ پر ریئل ٹائم ریفریش ٹریگر
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Search user by name...",
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                  filled: true,
                  fillColor: Colors.black.withOpacity(0.3),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent)),
                  prefixIcon: const Icon(Icons.search, color: Colors.redAccent, size: 20),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () {
                      if (_searchController.text.isNotEmpty) {
                        _searchController.clear(); // اگر ٹیکسٹ ہے تو مٹ جائے گا
                        setState(() {});
                      } else {
                        setState(() => isSearching = false); // اگر خالی ہے تو سرچ بار بند
                      }
                    },
                  ),
                ),
              ),
            ),
          ] else ...[
            // نارمل موڈ ریڈ آؤٹ
            const Icon(Icons.group_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            const Expanded(
              child: Text("USERS MANAGEMENT", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ),
            IconButton(
              icon: const Icon(Icons.search, color: Colors.redAccent, size: 26),
              onPressed: () => setState(() => isSearching = true), // سرچ پینل ٹریگر ہک
            ),
          ]
        ],
      ),
    );
  }

  // ============================================================================
  // --- VIEW 1: USERS LIST ---
  // ============================================================================
  Widget _buildUsersListScreen() {
    final users = filteredUsers;
    return Column(
      children: [
        _buildFilters(),
        Expanded(
          child: isLoading 
            ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
            : RefreshIndicator(
                color: Colors.redAccent, backgroundColor: const Color(0xFF140518),
                onRefresh: _fetchUsers,
                child: ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: users.length,
                  itemBuilder: (c, i) => _buildUserCard(users[i]),
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: ["All", "Deployed", "No Plan", "Free", "Basic", "Pro"].map((filter) {
          bool isSelected = currentFilter == filter;
          Color fColor = filter == "Deployed" ? Colors.amberAccent : filter == "No Plan" ? Colors.blueGrey : filter == "Pro" ? const Color(0xFFA855F7) : filter == "Basic" ? Colors.greenAccent : filter == "Free" ? Colors.blueAccent : Colors.redAccent;
          
          // لائیو گنتی فیچ کرنا
          int count = _getUserCountByFilter(filter);

          return GestureDetector(
            onTap: () => setState(() => currentFilter = filter),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300), margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: isSelected ? fColor.withOpacity(0.15) : Colors.transparent, borderRadius: BorderRadius.circular(20), border: Border.all(color: isSelected ? fColor : Colors.white10)),
              child: Row(
                children: [
                  Text(filter, style: TextStyle(color: isSelected ? fColor : Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  const SizedBox(width: 8),
                  
                  // 🔥 ٹیب ہوم کاؤنٹر بیج ڈیزائن (Real Count Badge)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: isSelected ? fColor.withOpacity(0.2) : Colors.white10, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      "$count", 
                      style: TextStyle(color: isSelected ? fColor : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    Color pColor = user['plan'] == 'Pro Plan' ? const Color(0xFFA855F7) : user['plan'] == 'Basic Plan' ? Colors.greenAccent : user['plan'] == 'Free Tier' ? Colors.blueAccent : Colors.grey;
    bool isSuspended = user['is_suspended'] ?? false;
    int pCount = int.tryParse(user['project_count'].toString()) ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(20), border: Border.all(color: isSuspended ? Colors.redAccent.withOpacity(0.5) : pColor.withOpacity(0.3))),
      child: Stack(
        children: [
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _ShatterPainter()))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.person, color: Colors.white54, size: 20), const SizedBox(width: 10),
                        Expanded(child: Text(user['username'], style: TextStyle(color: isSuspended ? Colors.redAccent : Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: pColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: pColor.withOpacity(0.3))), child: Text(user['plan'] ?? 'No Plan', style: TextStyle(color: pColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1))),
                ],
              ),
              const SizedBox(height: 8),
              
              Padding(padding: const EdgeInsets.only(left: 30), child: Text(user['email'] ?? '', style: const TextStyle(color: Colors.white38, fontSize: 13))),
              const SizedBox(height: 6),
              
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Row(
                  children: [
                    const Icon(Icons.vpn_key_rounded, color: Colors.redAccent, size: 12),
                    const SizedBox(width: 6),
                    Text(
                      "Pass: ${user['password'] ?? '********'}", 
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.bold)
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (pCount > 0)
                    Text("$pCount Projects Active", style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 15),
              
              GestureDetector(
                onTap: () => _fetchUserDetails(user),
                child: Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), border: Border.all(color: Colors.redAccent.withOpacity(0.5)), borderRadius: BorderRadius.circular(12)),
                  child: const Center(child: Text("MANAGE USER", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 2))),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // --- VIEW 2: USER DETAILS & PROJECTS ---
  // ============================================================================
  Widget _buildUserDetailsScreen() {
    if (isLoadingDetails) return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
    if (selectedUser == null) return const SizedBox();

    bool isSuspended = selectedUser!['is_suspended'] ?? false;
    Color pColor = selectedUser!['plan'] == 'Pro Plan' ? const Color(0xFFA855F7) : selectedUser!['plan'] == 'Basic Plan' ? Colors.greenAccent : selectedUser!['plan'] == 'Free Tier' ? Colors.blueAccent : Colors.grey;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(25), decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(20), border: Border.all(color: pColor.withOpacity(0.4))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(selectedUser!['username'], style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 5),
                        Text(selectedUser!['email'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 14)),
                        const SizedBox(height: 8),
                        
                        Row(
                          children: [
                            const Icon(Icons.lock_open_rounded, color: Colors.redAccent, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              "Password: ${selectedUser!['password'] ?? '********'}", 
                              style: const TextStyle(color: Colors.amberAccent, fontSize: 14, fontFamily: 'monospace', fontWeight: FontWeight.w900)
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _buildUserAdminMenu(isSuspended),
                ],
              ),
              const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider(color: Colors.white10)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text("ACTIVE PLAN", style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
                    const SizedBox(height: 5),
                    Text(selectedUser!['plan'] ?? 'No Plan', style: TextStyle(color: pColor, fontSize: 16, fontWeight: FontWeight.bold)),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text("EXPIRY DATE", style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
                    const SizedBox(height: 5),
                    Text(selectedUser!['plan_expiry'] ?? 'Lifetime', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  ]),
                ],
              )
            ],
          ),
        ),

        const SizedBox(height: 30),
        const Text("USER PROJECTS", style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),

        if (userProjects.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text("No projects deployed yet.", style: TextStyle(color: Colors.white38)))),
        
        ...userProjects.map((p) => _buildAdminProjectCard(p)).toList(),
        
        const SizedBox(height: 50),
      ],
    );
  }

  Widget _buildUserAdminMenu(bool isSuspended) {
    return Theme(
      data: Theme.of(context).copyWith(popupMenuTheme: PopupMenuThemeData(color: const Color(0xFF140518).withOpacity(0.95), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.redAccent.withOpacity(0.4), width: 1.5)))),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.settings_applications, color: Colors.redAccent, size: 28),
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(value: 'toggle_suspend', child: Row(children: [Icon(isSuspended ? Icons.play_circle_filled : Icons.block, size: 18, color: isSuspended ? Colors.greenAccent : Colors.amber), const SizedBox(width: 10), Text(isSuspended ? "Un-suspend Account" : "Suspend Account", style: const TextStyle(color: Colors.white))])),
          const PopupMenuItem<String>(value: 'cancel_plan', child: Row(children: [Icon(Icons.remove_shopping_cart, size: 18, color: Colors.orangeAccent), SizedBox(width: 10), Text("Cancel Plan", style: TextStyle(color: Colors.white))])),
          const PopupMenuItem<String>(value: 'reset_pass', child: Row(children: [Icon(Icons.lock_reset, size: 18, color: Colors.blueAccent), SizedBox(width: 10), Text("Reset Password", style: TextStyle(color: Colors.white))])),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(value: 'delete', child: Row(children: [Icon(Icons.delete_forever, size: 18, color: Colors.redAccent), SizedBox(width: 10), Text("Delete User Permanently", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))])),
        ],
        onSelected: (val) {
          if (val == 'toggle_suspend') _handleUserAction(isSuspended ? 'unsuspend' : 'suspend');
          else if (val == 'reset_pass') _showPasswordResetDialog();
          else _handleUserAction(val);
        },
      ),
    );
  }

  Widget _buildAdminProjectCard(Map<String, dynamic> p) {
    Color sColor = p['status'] == 'Online' ? Colors.greenAccent : p['status'] == 'Offline' ? Colors.white38 : Colors.redAccent;
    bool hasDomain = p['domain'] != null && p['domain'].toString().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(20), border: Border.all(color: sColor.withOpacity(0.3))),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _ShatterPainter())), 
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: sColor, boxShadow: [BoxShadow(color: sColor, blurRadius: 5)])), const SizedBox(width: 10), Text(p['name'], style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
                  _buildAdminProjectMenu(p),
                ],
              ),
              const SizedBox(height: 5),
              Text("Status: ${p['status']}", style: TextStyle(color: sColor, fontSize: 12)),
              
              if (hasDomain) ...[
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blueAccent.withOpacity(0.3))),
                  child: Row(
                    children: [
                      const Icon(Icons.language, color: Colors.blueAccent, size: 16), const SizedBox(width: 10),
                      Expanded(child: Text(p['domain'], style: const TextStyle(color: Colors.blueAccent, fontFamily: 'monospace', fontWeight: FontWeight.bold))),
                      GestureDetector(onTap: () => html.window.open("https://${p['domain']}", '_blank'), child: const Icon(Icons.open_in_new, color: Colors.blueAccent, size: 16)),
                    ],
                  ),
                )
              ]
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdminProjectMenu(Map<String, dynamic> p) {
    bool isOnline = p['status'] == 'Online';
    String pid = p['id'].toString();

    return Theme(
      data: Theme.of(context).copyWith(popupMenuTheme: PopupMenuThemeData(color: const Color(0xFF140518).withOpacity(0.95), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.redAccent.withOpacity(0.4), width: 1.5)))),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.white54),
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(value: isOnline ? 'stop' : 'start', child: Row(children: [Icon(isOnline ? Icons.stop_circle : Icons.play_circle_fill, size: 18, color: isOnline ? Colors.amber : Colors.greenAccent), const SizedBox(width: 10), Text(isOnline ? "Force Stop" : "Force Start", style: const TextStyle(color: Colors.white))])),
          const PopupMenuItem<String>(value: 'download', child: Row(children: [Icon(Icons.download_rounded, size: 18, color: Colors.blueAccent), SizedBox(width: 10), Text("Download Source Code", style: TextStyle(color: Colors.white))])),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.redAccent), SizedBox(width: 10), Text("Delete Project", style: TextStyle(color: Colors.redAccent))])),
        ],
        onSelected: (val) {
          if (val == 'download') _downloadSourceCode(pid);
          else _handleProjectAction(pid, val);
        },
      ),
    );
  }
}

// ============================================================================
// --- INDEPENDENT ADMIN PAINTERS ---
// ============================================================================
class AdminLiveBackground extends StatefulWidget { const AdminLiveBackground({Key? key}) : super(key: key); @override _AdminLiveBackgroundState createState() => _AdminLiveBackgroundState(); }
class _AdminLiveBackgroundState extends State<AdminLiveBackground> with SingleTickerProviderStateMixin {
  late AnimationController _c; @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _AdminWavePainter(_c.value)));
}
class _AdminWavePainter extends CustomPainter {
  final double progress; _AdminWavePainter(this.progress);
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.redAccent.withOpacity(0.02)..strokeWidth = 2.0..style = PaintingStyle.stroke;
    double offset = progress * (size.width * 2);
    for (double i = -size.height * 2; i < size.width * 2; i += 40) { canvas.drawLine(Offset(i + offset, 0), Offset(i - size.height + offset, size.height), p); }
  }
  @override bool shouldRepaint(covariant CustomPainter old) => true;
}
class _ShatterPainter extends CustomPainter {
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
