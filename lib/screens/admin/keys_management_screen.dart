import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard کے لیے
import 'package:http/http.dart' as http;

// PremiumToast کے لیے امپورٹ کریں
import '../auth/login_screen.dart'; 

class KeysManagementScreen extends StatefulWidget {
  const KeysManagementScreen({Key? key}) : super(key: key);
  @override
  _KeysManagementScreenState createState() => _KeysManagementScreenState();
}

class _KeysManagementScreenState extends State<KeysManagementScreen> with TickerProviderStateMixin {
  bool isLoading = true;
  bool isActionLoading = false;
  
  List<Map<String, dynamic>> generatedKeys = [];
  late TabController _keyTabController; // 🔥 فلٹر ٹیبز کے لیے لائیو مینیجر

  // Generator Form State
  String selectedPlan = "pro"; // free, basic, pro
  final TextEditingController _durationController = TextEditingController(text: "30"); // Plan valid for 30 days
  final TextEditingController _validityController = TextEditingController(text: "1"); // Key valid for 1 day to redeem
  final TextEditingController _maxUsesController = TextEditingController(text: "100"); // 100 users can use

  @override
  void initState() {
    super.initState();
    _keyTabController = TabController(length: 4, vsync: this);
    _keyTabController.addListener(() {
      setState(() {}); // ٹیب تبدیل ہونے پر لسٹ کو فوراً ری-فلٹر کرنے کے لیے
    });
    _fetchKeys();
  }

  @override
  void dispose() {
    _keyTabController.dispose();
    _durationController.dispose();
    _validityController.dispose();
    _maxUsesController.dispose();
    super.dispose();
  }

  // ============================================================================
  // --- REAL ADMIN APIs ---
  // ============================================================================

  Future<void> _fetchKeys() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse('/api/admin/keys'));
      if (res.statusCode == 200) {
        setState(() {
          generatedKeys = List<Map<String, dynamic>>.from(jsonDecode(res.body));
        });
      }
    } catch (e) {
      PremiumToast.show(context, "Network Error fetching keys", false);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _generateKey() async {
    if (_durationController.text.isEmpty || _validityController.text.isEmpty || _maxUsesController.text.isEmpty) {
      PremiumToast.show(context, "All fields are required!", false);
      return;
    }
    setState(() => isActionLoading = true);
    try {
      final res = await http.post(
        Uri.parse('/api/admin/keys/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'plan_type': selectedPlan,
          'duration_days': int.parse(_durationController.text),
          'redeem_validity_days': int.parse(_validityController.text),
          'max_uses': int.parse(_maxUsesController.text)
        })
      );
      final data = jsonDecode(res.body);
      
      if (res.statusCode == 200) {
        PremiumToast.show(context, "Key Generated Successfully!", true);
        _fetchKeys(); 
      } else {
        PremiumToast.show(context, data['message'], false);
      }
    } catch (e) {
      PremiumToast.show(context, "Generation Failed", false);
    } finally {
      if (mounted) setState(() => isActionLoading = false);
    }
  }

  Future<void> _toggleKeyStatus(String keyId, String currentStatus) async {
    setState(() => isActionLoading = true);
    String newStatus = currentStatus == "Active" ? "Paused" : "Active";
    try {
      final res = await http.post(
        Uri.parse('/api/admin/keys/$keyId/action'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'toggle_status', 'status': newStatus})
      );
      if (res.statusCode == 200) {
        PremiumToast.show(context, "Key $newStatus!", true);
        _fetchKeys();
      }
    } catch (e) {
      PremiumToast.show(context, "Action Failed", false);
    } finally {
      if (mounted) setState(() => isActionLoading = false);
    }
  }

  Future<void> _deleteKey(String keyId) async {
    setState(() => isActionLoading = true);
    try {
      final res = await http.post(
        Uri.parse('/api/admin/keys/$keyId/action'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'delete'})
      );
      if (res.statusCode == 200) {
        PremiumToast.show(context, "Key Deleted!", true);
        _fetchKeys();
      }
    } catch (e) {
      PremiumToast.show(context, "Deletion Failed", false);
    } finally {
      if (mounted) setState(() => isActionLoading = false);
    }
  }

  // 🔥 اسمارٹ فلٹر انجن: یہ کی کوڈ کے پہلے لفظ اور پلان ٹائپ دونوں کو اسکین کرتا ہے
  List<Map<String, dynamic>> _getFilteredKeys() {
    if (_keyTabController.index == 0) return generatedKeys;
    
    String currentScope = ["all", "free", "basic", "pro"][_keyTabController.index];
    return generatedKeys.where((k) {
      String planType = (k['plan_type'] ?? '').toString().toLowerCase();
      String keyCode = (k['key_code'] ?? '').toString().toLowerCase();
      
      return planType == currentScope || keyCode.startsWith(currentScope);
    }).toList();
  }

  // ============================================================================
  // --- UI BUILDING ---
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    final filteredKeys = _getFilteredKeys();

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
                  child: RefreshIndicator(
                    color: Colors.amber, backgroundColor: const Color(0xFF140518),
                    onRefresh: _fetchKeys,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        _buildGeneratorForm(),
                        const SizedBox(height: 30),
                        
                        // 🎛️ نیا جوڑا گیا فلٹر مینیو (Custom TabBar UI)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("ACTIVE & PAST KEYS", style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.bold)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                              child: Text("${filteredKeys.length} FOUND", style: const TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                            )
                          ],
                        ),
                        const SizedBox(height: 12),
                        
                        Theme(
                          data: ThemeData(highlightColor: Colors.transparent, splashColor: Colors.transparent),
                          child: TabBar(
                            controller: _keyTabController,
                            indicatorColor: Colors.amber,
                            labelColor: Colors.amber,
                            unselectedLabelColor: Colors.white38,
                            indicatorSize: TabBarIndicatorSize.tab,
                            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                            tabs: const [
                              Tab(text: "ALL"),
                              Tab(text: "FREE"),
                              Tab(text: "BASIC"),
                              Tab(text: "PRO"),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        if (isLoading)
                          const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Colors.amber)))
                        else if (filteredKeys.isEmpty)
                          const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No keys found in this matrix.", style: TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'monospace'))))
                        else
                          ...filteredKeys.map((k) => _buildKeyCard(k)).toList(),
                          
                        const SizedBox(height: 50),
                      ],
                    ),
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
          Icon(Icons.vpn_key_rounded, color: Colors.amber, size: 28),
          SizedBox(width: 10),
          Text("ACCESS KEYS", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
        ],
      ),
    );
  }

  Widget _buildGeneratorForm() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: Colors.amber.withOpacity(0.05), borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.amber.withOpacity(0.3))),
      child: Stack(
        children: [
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _AdminShatterPainterX()))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [Icon(Icons.auto_awesome, color: Colors.amber, size: 18), SizedBox(width: 10), Text("GENERATE NEW KEY", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, letterSpacing: 2))]),
              const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider(color: Colors.white10)),
              
              const Text("TARGET PLAN", style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _planSelectorBtn("Free", "free", Colors.blueAccent)),
                  const SizedBox(width: 10),
                  Expanded(child: _planSelectorBtn("Basic", "basic", Colors.greenAccent)),
                  const SizedBox(width: 10),
                  Expanded(child: _planSelectorBtn("Pro", "pro", const Color(0xFFA855F7))),
                ],
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(child: _buildInput("PLAN DURATION (DAYS)", _durationController, "e.g. 30")),
                  const SizedBox(width: 15),
                  Expanded(child: _buildInput("MAX USERS (LIMIT)", _maxUsesController, "e.g. 100")),
                ],
              ),
              const SizedBox(height: 15),

              _buildInput("REDEEM VALIDITY WINDOW (DAYS)", _validityController, "e.g. 1 (Expires tomorrow if not used)"),
              
              const SizedBox(height: 25),
              
              GestureDetector(
                onTap: isActionLoading ? null : _generateKey,
                child: Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), border: Border.all(color: Colors.amber), borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.1), blurRadius: 15)]),
                  child: Center(child: isActionLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2)) : const Text("GENERATE VIP KEY", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, letterSpacing: 2))),
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _planSelectorBtn(String title, String value, Color color) {
    bool isSelected = selectedPlan == value;
    return GestureDetector(
      onTap: () => setState(() => selectedPlan = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300), padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: isSelected ? color.withOpacity(0.2) : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: isSelected ? color : Colors.white10)),
        child: Center(child: Text(title.toUpperCase(), style: TextStyle(color: isSelected ? color : Colors.white54, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1))),
      ),
    );
  }

  // 🔒 ان پٹ باکس لاجک: کلرز اور بارڈرز کو بالکل آپ کے اصل ڈیزائن کے مطابق برقرار رکھا گیا ہے
  Widget _buildInput(String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        TextField(
          controller: controller, keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.white24, fontSize: 12), filled: true, fillColor: Colors.black.withOpacity(0.3), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.amber))),
        ),
      ],
    );
  }

  // --- KEY CARD ---
  Widget _buildKeyCard(Map<String, dynamic> k) {
    String pType = k['plan_type'] ?? 'free';
    Color pColor = pType == 'pro' ? const Color(0xFFA855F7) : pType == 'basic' ? Colors.greenAccent : Colors.blueAccent;
    String status = k['status'] ?? 'Active';
    Color sColor = status == 'Active' ? Colors.greenAccent : status == 'Paused' ? Colors.amber : Colors.redAccent;
    
    int used = k['used_count'] ?? 0;
    int max = k['max_uses'] ?? 100;
    String code = k['key_code'] ?? 'SILENT-XXXX-XXXX';

    return Container(
      margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(20), border: Border.all(color: sColor.withOpacity(0.3))),
      child: Stack(
        children: [
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _AdminShatterPainterX()))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: pColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: pColor.withOpacity(0.3))), child: Text("${pType.toUpperCase()} PLAN", style: TextStyle(color: pColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1))),
                  _buildKeyMenu(k['id'].toString(), status),
                ],
              ),
              const SizedBox(height: 15),
              
              // 🔥 فکس لاجک: لمبی کیز کو کارڈ کے اندر لاک رکھنا اور کاپی بٹن کو فکس اسکرین پر سیٹ کرنا
              GestureDetector(
                onTap: () { Clipboard.setData(ClipboardData(text: code)); PremiumToast.show(context, "Key Copied!", true); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12), 
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                    children: [
                      // کِتنی بھی لمبی کی ہو، وہ اس ایکسپینڈڈ ڈبے میں سوائپ ہوگی، باہر نہیں جائے گی
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Text(
                            code, 
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 2, fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // کاپی بٹن ہمیشہ دائیں طرف فکس رہے گا، اسکرین سے باہر نہیں بھاگے گا
                      const Icon(Icons.copy, color: Colors.amber, size: 18),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Stats
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text("USAGE", style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
                    const SizedBox(height: 5),
                    Text("$used / $max Users", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text("GIVES PLAN FOR", style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
                    const SizedBox(height: 5),
                    Text("${k['duration_days']} Days", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    const Text("STATUS", style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
                    const SizedBox(height: 5),
                    Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: sColor, boxShadow: [BoxShadow(color: sColor, blurRadius: 5)])), const SizedBox(width: 6), Text(status, style: TextStyle(color: sColor, fontSize: 14, fontWeight: FontWeight.bold))]),
                  ]),
                ],
              ),
              
              const SizedBox(height: 15),
              Text("Redeem Window Expires: ${k['valid_until'] ?? 'Tomorrow'}", style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  // --- KEY ADMIN MENU ---
  Widget _buildKeyMenu(String keyId, String currentStatus) {
    bool isPaused = currentStatus == 'Paused';
    
    return Theme(
      data: Theme.of(context).copyWith(popupMenuTheme: PopupMenuThemeData(color: const Color(0xFF140518).withOpacity(0.95), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.amber.withOpacity(0.4), width: 1.5)))),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.white54),
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(value: 'toggle', child: Row(children: [Icon(isPaused ? Icons.play_circle_fill : Icons.pause_circle_filled, size: 18, color: isPaused ? Colors.greenAccent : Colors.amber), const SizedBox(width: 10), Text(isPaused ? "Resume Key" : "Pause Key", style: const TextStyle(color: Colors.white))])),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(value: 'delete', child: Row(children: [Icon(Icons.delete_forever, size: 18, color: Colors.redAccent), SizedBox(width: 10), Text("Delete Key", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))])),
        ],
        onSelected: (val) {
          if (val == 'toggle') _toggleKeyStatus(keyId, currentStatus);
          if (val == 'delete') _deleteKey(keyId);
        },
      ),
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
