import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// PremiumToast کے لیے امپورٹ کریں
import '../auth/login_screen.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({Key? key}) : super(key: key);
  @override
  _AdminSettingsScreenState createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> with TickerProviderStateMixin {
  bool isLoading = true;
  bool isCredsLoading = false;
  bool isBroadcastLoading = false;
  
  // Links State Variables
  bool isLoadingLinks = true;
  bool isSavingLinks = false;
  List<Map<String, dynamic>> customLinks = [];
  
  // Add Link Form State
  bool showAddForm = false;
  final TextEditingController _newLinkNameCtrl = TextEditingController();
  final TextEditingController _newLinkUrlCtrl = TextEditingController();

  // Edit Link Form State
  int? editingIndex;
  final TextEditingController _editNameCtrl = TextEditingController();
  final TextEditingController _editUrlCtrl = TextEditingController();

  // State Variables
  bool maintenanceMode = false;
  DateTime? selectedExpiryDate;

  // Controllers
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _oldPassCtrl = TextEditingController();
  final TextEditingController _newPassCtrl = TextEditingController();
  final TextEditingController _msgCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchAdminSettings();
    _fetchCustomLinks();
  }

  // ============================================================================
  // --- REAL ADMIN APIs ---
  // ============================================================================

  // 1. Fetch Current Settings
  Future<void> _fetchAdminSettings() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse('/api/admin/settings'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _userCtrl.text = data['username'] ?? '';
          maintenanceMode = data['maintenance_mode'] ?? false;
          _msgCtrl.text = data['announcement_msg'] ?? '';
          if (data['announcement_expiry'] != null) {
            selectedExpiryDate = DateTime.tryParse(data['announcement_expiry']);
          }
        });
      }
    } catch (e) {
      PremiumToast.show(context, "Network Error fetching settings", false);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // 2. Fetch Custom Purchase Links
  Future<void> _fetchCustomLinks() async {
    setState(() => isLoadingLinks = true);
    try {
      final res = await http.get(Uri.parse('/api/billing/key-links'));
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        setState(() {
          customLinks = data.map((e) => {"name": e["name"], "url": e["url"]}).toList();
        });
      }
    } catch (e) {
      // Ignore or show silent error
    } finally {
      if (mounted) setState(() => isLoadingLinks = false);
    }
  }

  // 3. Save Custom Links to Backend
  Future<void> _saveAllLinksToBackend() async {
    setState(() => isSavingLinks = true);
    try {
      final res = await http.post(
        Uri.parse('/api/admin/settings/links'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'links': customLinks})
      );
      if (res.statusCode == 200) {
        PremiumToast.show(context, "Links Updated Successfully!", true);
      } else {
        PremiumToast.show(context, "Failed to save links", false);
      }
    } catch (e) {
      PremiumToast.show(context, "Network Error while saving links", false);
    } finally {
      if (mounted) setState(() => isSavingLinks = false);
    }
  }

  // --- Links Helpers ---
  void _addNewLink() {
    if (_newLinkNameCtrl.text.isEmpty || _newLinkUrlCtrl.text.isEmpty) {
      PremiumToast.show(context, "Please fill both fields", false);
      return;
    }
    setState(() {
      customLinks.add({"name": _newLinkNameCtrl.text, "url": _newLinkUrlCtrl.text});
      showAddForm = false;
      _newLinkNameCtrl.clear();
      _newLinkUrlCtrl.clear();
    });
    _saveAllLinksToBackend();
  }

  void _saveEditedLink(int index) {
    if (_editNameCtrl.text.isEmpty || _editUrlCtrl.text.isEmpty) {
      PremiumToast.show(context, "Fields cannot be empty", false);
      return;
    }
    setState(() {
      customLinks[index] = {"name": _editNameCtrl.text, "url": _editUrlCtrl.text};
      editingIndex = null;
    });
    _saveAllLinksToBackend();
  }

  void _confirmDeleteLink(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF140518),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.redAccent, width: 1)),
        title: const Text("Delete Link?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to remove this purchase link?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => customLinks.removeAt(index));
              _saveAllLinksToBackend();
            }, 
            child: const Text("DELETE", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))
          ),
        ],
      )
    );
  }

  // 4. Update Credentials
  Future<void> _updateCredentials() async {
    if (_userCtrl.text.isEmpty) {
      PremiumToast.show(context, "Username cannot be empty", false);
      return;
    }
    setState(() => isCredsLoading = true);
    try {
      final res = await http.post(
        Uri.parse('/api/admin/settings/credentials'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'new_username': _userCtrl.text,
          'old_password': _oldPassCtrl.text,
          'new_password': _newPassCtrl.text
        })
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        PremiumToast.show(context, "Admin Credentials Updated!", true);
        _oldPassCtrl.clear(); _newPassCtrl.clear();
      } else {
        PremiumToast.show(context, data['message'], false);
      }
    } catch (e) {
      PremiumToast.show(context, "Update Failed", false);
    } finally {
      if (mounted) setState(() => isCredsLoading = false);
    }
  }

  // 5. Toggle Maintenance Mode
  Future<void> _toggleMaintenance(bool value) async {
    setState(() => maintenanceMode = value); 
    try {
      final res = await http.post(
        Uri.parse('/api/admin/settings/maintenance'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'enabled': value})
      );
      if (res.statusCode == 200) {
        PremiumToast.show(context, value ? "SYSTEM LOCKED: Maintenance ON" : "SYSTEM LIVE: Maintenance OFF", value);
      } else {
        setState(() => maintenanceMode = !value); 
        PremiumToast.show(context, "Failed to toggle mode", false);
      }
    } catch (e) {
      setState(() => maintenanceMode = !value);
      PremiumToast.show(context, "Network Error", false);
    }
  }

  // 6. Update Broadcast Message
  Future<void> _broadcastMessage() async {
    if (_msgCtrl.text.isNotEmpty && selectedExpiryDate == null) {
      PremiumToast.show(context, "Please select an expiry date for the broadcast.", false);
      return;
    }
    setState(() => isBroadcastLoading = true);
    try {
      final res = await http.post(
        Uri.parse('/api/admin/settings/announcement'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': _msgCtrl.text,
          'expiry_date': selectedExpiryDate?.toIso8601String()
        })
      );
      if (res.statusCode == 200) {
        PremiumToast.show(context, _msgCtrl.text.isEmpty ? "Broadcast Cleared!" : "Broadcast Sent to all users!", true);
      } else {
        PremiumToast.show(context, "Failed to broadcast", false);
      }
    } catch (e) {
      PremiumToast.show(context, "Broadcast Failed", false);
    } finally {
      if (mounted) setState(() => isBroadcastLoading = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedExpiryDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.amber, onPrimary: Colors.black, surface: Color(0xFF140518), onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != selectedExpiryDate) {
      setState(() { selectedExpiryDate = picked; });
    }
  }

  // ============================================================================
  // --- UI BUILDING ---
  // ============================================================================

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
                _buildHeader(),
                Expanded(
                  child: isLoading 
                    ? const Center(child: CircularProgressIndicator(color: Colors.purpleAccent))
                    : ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          _buildSystemStatusSection(),
                          const SizedBox(height: 30),
                          _buildBroadcastSection(),
                          const SizedBox(height: 30),
                          _buildCredentialsSection(),
                          const SizedBox(height: 30),
                          _buildCustomLinksSection(), // 🔥 New Section Added Here
                          const SizedBox(height: 50),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: const Row(
        children: [
          Icon(Icons.admin_panel_settings, color: Colors.purpleAccent, size: 28),
          SizedBox(width: 10),
          Text("SYSTEM SETTINGS", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // 🔥 NEW: CUSTOM LINKS SECTION 🔥
  // ---------------------------------------------------------
  Widget _buildCustomLinksSection() {
    return _buildGlassCard(
      color: Colors.cyanAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(children: [Icon(Icons.link_rounded, color: Colors.cyanAccent, size: 20), SizedBox(width: 10), Text("CUSTOM PURCHASE LINKS", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w900, letterSpacing: 2))]),
              if (isSavingLinks) const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(color: Colors.cyanAccent, strokeWidth: 2))
            ]
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider(color: Colors.white10)),
          
          if (isLoadingLinks)
            const Center(child: Padding(padding: EdgeInsets.all(20.0), child: CircularProgressIndicator(color: Colors.cyanAccent)))
          else if (customLinks.isEmpty && !showAddForm)
            const Center(child: Padding(padding: EdgeInsets.all(15.0), child: Text("No custom links added yet.", style: TextStyle(color: Colors.white38))))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: customLinks.length,
              itemBuilder: (context, index) {
                final link = customLinks[index];
                final isEditing = editingIndex == index;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(bottom: 15),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: isEditing ? Colors.cyanAccent.withOpacity(0.5) : Colors.white10)
                  ),
                  child: isEditing 
                    ? _buildInlineEditForm(index) 
                    : _buildLinkDisplay(index, link['name'], link['url']),
                );
              },
            ),

          // Add New Form (Animated Expansion)
          AnimatedSize(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutBack,
            child: showAddForm 
              ? Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 20),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: Colors.cyanAccent.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.cyanAccent.withOpacity(0.3))),
                  child: Column(
                    children: [
                      _buildInput("BUTTON NAME", _newLinkNameCtrl, "e.g. Buy on Telegram", false),
                      const SizedBox(height: 15),
                      _buildInput("URL LINK", _newLinkUrlCtrl, "e.g. https://t.me/...", false),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Expanded(child: GestureDetector(onTap: () => setState(() => showAddForm = false), child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)), child: const Center(child: Text("CANCEL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))))),
                          const SizedBox(width: 10),
                          Expanded(child: GestureDetector(onTap: _addNewLink, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.cyanAccent.withOpacity(0.2), border: Border.all(color: Colors.cyanAccent), borderRadius: BorderRadius.circular(10)), child: const Center(child: Text("SAVE LINK", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)))))),
                        ],
                      )
                    ],
                  ),
                )
              : const SizedBox.shrink(),
          ),

          // Main Add Button
          if (!showAddForm)
            Center(
              child: GestureDetector(
                onTap: () => setState(() => showAddForm = true),
                child: Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(color: Colors.cyanAccent.withOpacity(0.1), border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), style: BorderStyle.solid), borderRadius: BorderRadius.circular(12)),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_circle_outline, color: Colors.cyanAccent, size: 20), SizedBox(width: 10),
                    Text("ADD CUSTOM LINK", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  ]),
                ),
              ),
            )
        ],
      ),
    );
  }

  Widget _buildLinkDisplay(int index, String name, String url) {
    return Row(
      children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.cyanAccent.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.link, color: Colors.cyanAccent, size: 18)),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 3),
              Text(url, style: const TextStyle(color: Colors.white54, fontSize: 11), overflow: TextOverflow.ellipsis, maxLines: 1),
            ],
          ),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.edit_note_rounded, color: Colors.amber, size: 24),
              onPressed: () {
                setState(() {
                  editingIndex = index;
                  _editNameCtrl.text = name;
                  _editUrlCtrl.text = url;
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 22),
              onPressed: () => _confirmDeleteLink(index),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildInlineEditForm(int index) {
    return Column(
      children: [
        TextField(
          controller: _editNameCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(labelText: "Button Name", labelStyle: TextStyle(color: Colors.cyanAccent, fontSize: 12), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent))),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _editUrlCtrl,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
          decoration: const InputDecoration(labelText: "URL Link", labelStyle: TextStyle(color: Colors.cyanAccent, fontSize: 12), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)), focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent))),
        ),
        const SizedBox(height: 15),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: () => setState(() => editingIndex = null), child: const Text("CANCEL", style: TextStyle(color: Colors.white54, fontSize: 12))),
            const SizedBox(width: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent.withOpacity(0.2), shadowColor: Colors.transparent, side: const BorderSide(color: Colors.cyanAccent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () => _saveEditedLink(index), 
              child: const Text("UPDATE", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12))
            ),
          ],
        )
      ],
    );
  }
  // ---------------------------------------------------------

  // Other Existing Sections...
  Widget _buildSystemStatusSection() {
    return _buildGlassCard(
      color: Colors.redAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20), SizedBox(width: 10), Text("CORE SYSTEM STATUS", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, letterSpacing: 2))]),
          const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider(color: Colors.white10)),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("MAINTENANCE MODE", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 5),
                  Text("Lock dashboard & halt deployments", style: TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
              Switch(
                value: maintenanceMode,
                onChanged: _toggleMaintenance,
                activeColor: Colors.redAccent,
                activeTrackColor: Colors.redAccent.withOpacity(0.3),
                inactiveThumbColor: Colors.white38,
                inactiveTrackColor: Colors.white10,
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildBroadcastSection() {
    return _buildGlassCard(
      color: Colors.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [Icon(Icons.campaign_rounded, color: Colors.amber, size: 20), SizedBox(width: 10), Text("GLOBAL BROADCAST POPUP", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, letterSpacing: 2))]),
          const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider(color: Colors.white10)),
          
          const Text("ANNOUNCEMENT MESSAGE", style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
          const SizedBox(height: 10),
          TextField(
            controller: _msgCtrl, maxLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(hintText: "Enter message to show all users upon login... (Leave empty to clear)", hintStyle: const TextStyle(color: Colors.white24, fontSize: 12), filled: true, fillColor: Colors.black.withOpacity(0.3), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.amber))),
          ),
          
          const SizedBox(height: 20),
          
          const Text("EXPIRY DATE", style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _selectDate(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15), decoration: BoxDecoration(color: Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(selectedExpiryDate == null ? "Select Expiry Date" : "${selectedExpiryDate!.day}/${selectedExpiryDate!.month}/${selectedExpiryDate!.year}", style: TextStyle(color: selectedExpiryDate == null ? Colors.white24 : Colors.white, fontWeight: FontWeight.bold)),
                const Icon(Icons.calendar_month, color: Colors.amber, size: 18),
              ]),
            ),
          ),
          
          const SizedBox(height: 25),
          Center(
            child: GestureDetector(
              onTap: isBroadcastLoading ? null : _broadcastMessage,
              child: Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), border: Border.all(color: Colors.amber), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.1), blurRadius: 15)]),
                child: Center(child: isBroadcastLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2)) : const Text("SET BROADCAST", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, letterSpacing: 2))),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCredentialsSection() {
    return _buildGlassCard(
      color: const Color(0xFFA855F7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [Icon(Icons.manage_accounts, color: Color(0xFFA855F7), size: 20), SizedBox(width: 10), Text("MASTER CREDENTIALS", style: TextStyle(color: Color(0xFFA855F7), fontWeight: FontWeight.w900, letterSpacing: 2))]),
          const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider(color: Colors.white10)),
          
          _buildInput("ADMIN USERNAME", _userCtrl, "e.g. aflovevip", false),
          const SizedBox(height: 15),
          _buildInput("CURRENT PASSWORD", _oldPassCtrl, "Enter current password to authorize", true),
          const SizedBox(height: 15),
          _buildInput("NEW PASSWORD", _newPassCtrl, "Leave empty to keep current password", true),
          
          const SizedBox(height: 25),
          Center(
            child: GestureDetector(
              onTap: isCredsLoading ? null : _updateCredentials,
              child: Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(color: const Color(0xFFA855F7).withOpacity(0.15), border: Border.all(color: const Color(0xFFA855F7)), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: const Color(0xFFA855F7).withOpacity(0.1), blurRadius: 15)]),
                child: Center(child: isCredsLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFFA855F7), strokeWidth: 2)) : const Text("UPDATE CREDENTIALS", style: TextStyle(color: Color(0xFFA855F7), fontWeight: FontWeight.w900, letterSpacing: 2))),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: color.withOpacity(0.02), borderRadius: BorderRadius.circular(25), border: Border.all(color: color.withOpacity(0.3))),
      child: Stack(
        children: [
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _AdminShatterPainterX()))),
          child,
        ],
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController controller, String hint, bool isPass) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        TextField(
          controller: controller, obscureText: isPass,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.white24, fontSize: 12), filled: true, fillColor: Colors.black.withOpacity(0.3), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.cyanAccent))),
        ),
      ],
    );
  }
}

// ============================================================================
// --- INTERNAL ADMIN PAINTERS ---
// ============================================================================

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
class _AdminShatterPainterX extends CustomPainter {
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
