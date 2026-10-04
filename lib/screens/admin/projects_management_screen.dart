import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// آپ کا افیشل ڈیزائن امپورٹ (PremiumToast کے لیے)
import '../auth/login_screen.dart'; 

class ProjectsManagementScreen extends StatefulWidget {
  const ProjectsManagementScreen({Key? key}) : super(key: key);
  @override
  _ProjectsManagementScreenState createState() => _ProjectsManagementScreenState();
}

class _ProjectsManagementScreenState extends State<ProjectsManagementScreen> with TickerProviderStateMixin {
  List<dynamic> _allProjects = [];
  bool _isLoading = true;
  late TabController _tabController;

  // لائیو سرچ مینیجر اسٹیٹ ویری ایبلز
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // ایکٹو ٹیب اسکوپ لسٹ
  final List<String> _tabScopes = ["all", "online", "crashed", "offline"];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // ٹیب سوئچ ہونے پر ویوز اور کاؤنٹرز کو فوراً ری-فلٹر کرنے کے لیے
    });
    _fetchClusterProjects();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose(); 
    super.dispose();
  }

  // ============================================================================
  // 📡 --- REAL CLUSTER ADMIN GLOBAL APIs ---
  // ============================================================================

  Future<void> _fetchClusterProjects() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final res = await http.get(Uri.parse('/api/admin/projects/list'));
      if (res.statusCode == 200) {
        setState(() {
          _allProjects = jsonDecode(res.body);
        });
      } else {
        PremiumToast.show(context, "Failed to synchronize cluster nodes!", false);
      }
    } catch (e) {
      PremiumToast.show(context, "Network exception connecting cluster telemetry", false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _executeSingleAction(int projectId, String action) async {
    try {
      final res = await http.post(
        Uri.parse('/api/admin/projects/action'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"project_id": projectId, "action": action}),
      );
      if (res.statusCode == 200) {
        PremiumToast.show(context, "Project execution '$action' successful!", true);
        _fetchClusterProjects(); 
      } else {
        PremiumToast.show(context, "Action execution failed on target jail sandbox.", false);
      }
    } catch (e) {
      PremiumToast.show(context, "Network error during surgical action execution", false);
    }
  }

  Future<void> _deleteProject(int projectId, String name) async {
    try {
      final res = await http.delete(
        Uri.parse('/api/admin/projects/delete'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"project_id": projectId}),
      );
      if (res.statusCode == 200) {
        PremiumToast.show(context, "Project '$name' cleared from infrastructure storage.", true);
        _fetchClusterProjects();
      } else {
        PremiumToast.show(context, "Jail elimination failed. Safe lock active.", false);
      }
    } catch (e) {
      PremiumToast.show(context, "Exception triggered during file system wipe sequence", false);
    }
  }

  Future<void> _executeBulkAction(String scope, String action) async {
    setState(() => _isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('/api/admin/projects/bulk-action'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"scope": scope, "action": action}),
      );
      if (res.statusCode == 200) {
        PremiumToast.show(context, "Bulk action '$action' broadcasted to scope '$scope' successfully.", true);
        _fetchClusterProjects();
      } else {
        PremiumToast.show(context, "Bulk operation rejected by cluster matrix manager.", false);
        setState(() => _isLoading = false);
      }
    } catch (e) {
      PremiumToast.show(context, "Network congestion processing async bulk array", false);
      setState(() => _isLoading = false);
    }
  }

  int _getProjectCountByScope(String scope) {
    if (scope == "all") return _allProjects.length;
    if (scope == "online") {
      return _allProjects.where((p) => p['status'] == "Online" || p['status'] == "Starting" || p['status'] == "Building").length;
    }
    if (scope == "crashed") {
      return _allProjects.where((p) => p['status'] == "Crashed").length;
    }
    if (scope == "offline") {
      return _allProjects.where((p) => p['status'] == "Offline").length;
    }
    return 0;
  }

  // ============================================================================
  // 🎨 --- CORE UI STRUCTURE ---
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, 
      appBar: AppBar(
        backgroundColor: const Color(0xFF140518).withOpacity(0.4),
        elevation: 0,
        leading: _isSearching 
            ? const Icon(Icons.search, color: Colors.blueAccent)
            : null,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (val) => setState(() {}), 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Search by project, user, or language...",
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                    onPressed: () {
                      if (_searchController.text.isNotEmpty) {
                        _searchController.clear(); 
                        setState(() {});
                      } else {
                        setState(() => _isSearching = false); 
                      }
                    },
                  ),
                ),
              )
            : const Text(
                "CLUSTER JAVELIN INTERFACE", 
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
        centerTitle: !_isSearching,
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search, color: Colors.blueAccent, size: 24),
              onPressed: () => setState(() => _isSearching = true), 
            ),
          
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.blueAccent, size: 26),
            color: const Color(0xFF140518), 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: const BorderSide(color: Colors.white10)),
            onSelected: (action) {
              String activeScope = _tabScopes[_tabController.index];
              _executeBulkAction(activeScope, action);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: "stop", child: Row(children: [Icon(Icons.stop_circle_outlined, color: Colors.redAccent, size: 18), SizedBox(width: 10), Text("Stop All in Tab", style: TextStyle(color: Colors.white, fontSize: 12))])),
              const PopupMenuItem(value: "start", child: Row(children: [Icon(Icons.play_circle_outline_rounded, color: Colors.greenAccent, size: 18), SizedBox(width: 10), Text("Start All in Tab", style: TextStyle(color: Colors.white, fontSize: 12))])),
              const PopupMenuItem(value: "build", child: Row(children: [Icon(Icons.bolt_rounded, color: Colors.amber, size: 18), SizedBox(width: 10), Text("Build & Start All in Tab", style: TextStyle(color: Colors.white, fontSize: 12))])),
            ],
          ),
          const SizedBox(width: 10),
        ],
        bottom: TabBar(
          controller: _tabController,
          // 🟢 فکس لاک لاجک: ان دونوں لائینز کی وجہ سے اب مینیو کبھی نہیں چھپے گا اور کاؤنٹنگ 100٪ نظر آئے گی
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: Colors.blueAccent,
          labelColor: Colors.blueAccent,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          tabs: [
            Tab(text: "ALL (${_getProjectCountByScope('all')})"),
            Tab(text: "ONLINE (${_getProjectCountByScope('online')})"),
            Tab(text: "CRASHED (${_getProjectCountByScope('crashed')})"),
            Tab(text: "OFFLINE (${_getProjectCountByScope('offline')})"),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildProjectTabList("all"),
                _buildProjectTabList("online"),
                _buildProjectTabList("crashed"),
                _buildProjectTabList("offline"),
              ],
            ),
    );
  }

  // ============================================================================
  // 📋 --- FILTERED & SEARCHABLE LIST BUILDER ---
  // ============================================================================
  Widget _buildProjectTabList(String scope) {
    List<dynamic> filteredList = [];
    
    if (scope == "all") {
      filteredList = List.from(_allProjects);
    } else if (scope == "online") {
      filteredList = _allProjects.where((p) => p['status'] == "Online" || p['status'] == "Starting" || p['status'] == "Building").toList();
    } else if (scope == "crashed") {
      filteredList = _allProjects.where((p) => p['status'] == "Crashed").toList();
    } else if (scope == "offline") {
      filteredList = _allProjects.where((p) => p['status'] == "Offline").toList();
    }

    if (_isSearching && _searchController.text.isNotEmpty) {
      String query = _searchController.text.toLowerCase();
      filteredList.retainWhere((p) {
        final pName = (p['name'] ?? '').toString().toLowerCase();
        final uName = (p['username'] ?? '').toString().toLowerCase();
        final lang = (p['language'] ?? '').toString().toLowerCase();
        return pName.contains(query) || uName.contains(query) || lang.contains(query);
      });
    }

    if (filteredList.isEmpty) {
      return Center(
        child: Text(
          "No node configurations mapped in '${scope.toUpperCase()}' matrix.",
          style: const TextStyle(color: Colors.white24, fontSize: 11, fontFamily: 'monospace'),
        ),
      );
    }

    return RefreshIndicator(
      color: Colors.blueAccent,
      backgroundColor: const Color(0xFF140518),
      onRefresh: _fetchClusterProjects,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        itemCount: filteredList.length,
        itemBuilder: (context, index) {
          return _buildProjectRowItem(filteredList[index]);
        },
      ),
    );
  }

  // ============================================================================
  // 🗄️ --- PRODUCTION LINE-BY-LINE CARD ITEM DESIGN ---
  // ============================================================================
  Widget _buildProjectRowItem(Map<String, dynamic> project) {
    int id = project['id'] ?? 0;
    String name = project['name'] ?? "Unnamed App";
    String username = project['username'] ?? "unknown-user";
    String language = (project['language'] ?? "text").toString().toUpperCase();
    String status = project['status'] ?? "Offline";
    String planType = (project['plan_type'] ?? "free").toString().toUpperCase();

    // 🟢 لائیو اسٹیٹس ڈاٹس کنٹرول میٹرکس (پروفیشنل لینوکس انڈیکیٹرز)
    Color dotColor = Colors.white24;
    bool exhibitorsGlow = true;
    
    if (status == "Online") { 
      dotColor = Colors.greenAccent; 
    } else if (status == "Crashed") { 
      dotColor = Colors.redAccent; 
    } else if (status == "Building" || status == "Starting") { 
      dotColor = Colors.amber; 
    } else { 
      dotColor = Colors.white24; // Offline پر بغیر کلر والا ڈل گرے ڈاٹ
      exhibitorsGlow = false; 
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.01),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: dotColor.withOpacity(0.15), width: 1),
      ),
      child: Row(
        children: [
          // چمکتا ہوا فکسڈ سائز اسٹیٹس ڈاٹ مینو
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              boxShadow: exhibitorsGlow ? [
                BoxShadow(color: dotColor.withOpacity(0.6), blurRadius: 8, spreadRadius: 1)
              ] : [],
            ),
          ),
          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.account_circle, color: Colors.white38, size: 12),
                    const SizedBox(width: 5),
                    Text(
                      username,
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                      child: Text(planType, style: const TextStyle(color: Colors.blueAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // لینگویج بیج سسٹم
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
            ),
            child: Text(
              language,
              style: const TextStyle(color: Color(0xFF45F3FF), fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(width: 10),

          // ایکشن مینیو پاپ اپ (شیر آئیکنز لسٹ)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white38, size: 20),
            color: const Color(0xFF140518), 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white10)),
            onSelected: (value) {
              if (value == "delete") {
                _showWipeConfirmationDialog(id, name);
              } else {
                _executeSingleAction(id, value);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: "start", child: Row(children: [Icon(Icons.play_arrow_rounded, color: Colors.greenAccent, size: 16), SizedBox(width: 8), Text("Start Sandbox", style: TextStyle(color: Colors.white, fontSize: 11))])),
              const PopupMenuItem(value: "stop", child: Row(children: [Icon(Icons.stop_rounded, color: Colors.redAccent, size: 16), SizedBox(width: 8), Text("Stop Sandbox", style: TextStyle(color: Colors.white, fontSize: 11))])),
              const PopupMenuItem(value: "build", child: Row(children: [Icon(Icons.refresh_rounded, color: Colors.amber, size: 16), SizedBox(width: 8), Text("Rebuild & Start", style: TextStyle(color: Colors.white, fontSize: 11))])),
              const PopupMenuDivider(height: 1),
              const PopupMenuItem(value: "delete", child: Row(children: [Icon(Icons.delete_forever_rounded, color: Colors.red, size: 16), SizedBox(width: 8), Text("Wipe Sandbox", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11))])),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // --- DELETION CONFIRMATION DIALOG MATRIX ---
  // ============================================================================
  void _showWipeConfirmationDialog(int projectId, String projectName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF140518),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.redAccent, width: 1)),
          title: const Row(
            children: [
              Icon(Icons.gavel_rounded, color: Colors.redAccent, size: 20),
              SizedBox(width: 8),
              Text("CRITICAL ELIMINATION SEQUENCE", style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ],
          ),
          content: Text("Are you absolutely sure you want to permanently delete and wipe the project '$projectName' from the cluster storage arrays?", style: const TextStyle(color: Colors.white70, fontSize: 12)),
          actions: [
            TextButton(
              child: const Text("CANCEL", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("WIPE DATA", style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteProject(projectId, projectName);
              },
            ),
          ],
        );
      },
    );
  }
}
