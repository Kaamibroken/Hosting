import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // کلپ بورڈ کاپی فیچر کے لیے
import 'package:http/http.dart' as http;
import 'dart:html' as html; // ویب ڈاؤن لوڈ انجن کے لیے

// PremiumToast کے لیے امپورٹ (اپنے پاتھ کے حساب سے ایڈجسٹ کر لیں)
import '../auth/login_screen.dart'; 

class BillingManagementScreen extends StatefulWidget {
  const BillingManagementScreen({Key? key}) : super(key: key);
  @override
  _BillingManagementScreenState createState() => _BillingManagementScreenState();
}

class _BillingManagementScreenState extends State<BillingManagementScreen> with TickerProviderStateMixin {
  bool isLoading = true;
  bool isActionLoading = false;
  
  List<Map<String, dynamic>> pendingRequests = [];

  // 🔥 لائیو سرچ مینیجر اسٹیٹ ویری ایبلز
  bool isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchBillingRequests();
  }

  @override
  void dispose() {
    _searchController.dispose(); // میموری لیک پروٹیکشن ہک
    super.dispose();
  }

  // ============================================================================
  // --- REAL ADMIN APIs ---
  // ============================================================================

  Future<void> _fetchBillingRequests() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse('/api/admin/billing/requests'));
      if (res.statusCode == 200) {
        setState(() {
          pendingRequests = List<Map<String, dynamic>>.from(jsonDecode(res.body));
        });
      }
    } catch (e) {
      PremiumToast.show(context, "Network Error fetching requests", false);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _handleApprove(String reqId) async {
    setState(() => isActionLoading = true);
    try {
      final res = await http.post(
        Uri.parse('/api/admin/billing/approve'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'request_id': reqId})
      );
      final data = jsonDecode(res.body);
      
      if (res.statusCode == 200) {
        PremiumToast.show(context, data['message'], true);
        _fetchBillingRequests(); 
      } else {
        PremiumToast.show(context, data['message'], false);
      }
    } catch (e) {
      PremiumToast.show(context, "Approval Failed", false);
    } finally {
      if (mounted) setState(() => isActionLoading = false);
    }
  }

  Future<void> _handleDecline(String reqId, String reason) async {
    setState(() => isActionLoading = true);
    try {
      final res = await http.post(
        Uri.parse('/api/admin/billing/decline'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'request_id': reqId, 'reason': reason})
      );
      final data = jsonDecode(res.body);
      
      if (res.statusCode == 200) {
        PremiumToast.show(context, data['message'], true);
        _fetchBillingRequests(); 
      } else {
        PremiumToast.show(context, data['message'], false);
      }
    } catch (e) {
      PremiumToast.show(context, "Decline Failed", false);
    } finally {
      if (mounted) setState(() => isActionLoading = false);
    }
  }

  void _copyToClipboard(String text) {
    if (text.isEmpty || text == "N/A") return;
    Clipboard.setData(ClipboardData(text: text));
    PremiumToast.show(context, "Transaction ID Copied!", true);
  }

  void _openFullscreenImage(String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.95), 
      builder: (context) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.black26,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.download_for_offline_rounded, color: Colors.greenAccent, size: 28),
              onPressed: () {
                final anchor = html.AnchorElement(href: imageUrl)
                  ..target = '_blank'
                  ..download = imageUrl.split('/').last;
                anchor.click();
                PremiumToast.show(context, "Downloading receipt asset...", true);
              },
            ),
            const SizedBox(width: 20),
          ],
        ),
        body: Center(
          child: InteractiveViewer(
            panEnabled: true,
            boundaryMargin: const EdgeInsets.all(20),
            minScale: 0.5,
            maxScale: 5.0, 
            child: Image.network(imageUrl, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  // ============================================================================
  // --- SMART REVERSE & INLINE SEARCH FUSION LOGIC ---
  // ============================================================================
  List<Map<String, dynamic>> get filteredRequests {
    // 🔥 فکس: پوری لسٹ کو ریورس کر دیا تاکہ نئی پیمنٹ ہمیشہ ٹاپ پر شو ہو
    List<Map<String, dynamic>> reversedList = List.from(pendingRequests.reversed);
    
    // 🔍 لائیو سرچ فلٹر پائپ لائن (Username, Email اور Trx ID اسکیننگ)
    if (isSearching && _searchController.text.isNotEmpty) {
      String query = _searchController.text.toLowerCase();
      reversedList.retainWhere((req) {
        final username = (req['username'] ?? '').toString().toLowerCase();
        final email = (req['email'] ?? '').toString().toLowerCase();
        final trxId = (req['trx_id'] ?? '').toString().toLowerCase();
        return username.contains(query) || email.contains(query) || trxId.contains(query);
      });
    }
    return reversedList;
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
                    ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                    : _buildRequestsList(),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // ============================================================================
  // --- EXPANDABLE SEARCH NAVBAR HEADER ---
  // ============================================================================
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Row(
        children: [
          if (isSearching) ...[
            // 🔥 الٹرا اسمارٹ ان لائن ان پٹ سرچ بار
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (val) => setState(() {}), // ٹائپنگ پر ریئل ٹائم ریفریش ٹریگر
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Search requests by name or Trx ID...",
                  hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                  filled: true,
                  fillColor: Colors.black.withOpacity(0.3),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.greenAccent)),
                  prefixIcon: const Icon(Icons.search, color: Colors.greenAccent, size: 20),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                    onPressed: () {
                      if (_searchController.text.isNotEmpty) {
                        _searchController.clear(); // اگر ٹیکسٹ ہے تو صاف ہو جائے گا
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
            // نارمل پینل ہیڈر ویو
            const Icon(Icons.receipt_long_rounded, color: Colors.greenAccent, size: 28),
            const SizedBox(width: 10),
            const Expanded(
              child: Text("BILLING REQUESTS", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ),
            IconButton(
              icon: const Icon(Icons.search, color: Colors.greenAccent, size: 26),
              onPressed: () => setState(() => isSearching = true), // سرچ پینل پاپ اپ ایکشن
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildRequestsList() {
    final list = filteredRequests; // فلٹرڈ اور ریورس کی ہوئی لسٹ لوڈ کریں

    if (list.isEmpty) {
      return const Center(child: Text("No Billing Requests Mapped.", style: TextStyle(color: Colors.white54, letterSpacing: 2, fontSize: 12, fontFamily: 'monospace')));
    }

    return RefreshIndicator(
      color: Colors.greenAccent, backgroundColor: const Color(0xFF140518),
      onRefresh: _fetchBillingRequests,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: list.length,
        itemBuilder: (c, i) => _buildRequestCard(list[i]),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final String transactionId = req['trx_id'] ?? 'N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.greenAccent.withOpacity(0.3))),
      child: Stack(
        children: [
          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _AdminShatterPainterX()))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(req['username'] ?? 'Unknown', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        Text(req['email'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.greenAccent.withOpacity(0.4))), child: Text(req['plan_requested'] ?? 'Unknown Plan', style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1))),
                ],
              ),
              const SizedBox(height: 20),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded( 
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("TRANSACTION ID", style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2)),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                transactionId, 
                                style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                                softWrap: true,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (transactionId != "N/A")
                              IconButton(
                                icon: const Icon(Icons.copy_all_rounded, color: Colors.greenAccent, size: 18),
                                onPressed: () => _copyToClipboard(transactionId),
                                tooltip: "Copy ID",
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 15), 
                  GestureDetector(
                    onTap: () => _showRequestDetails(req),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.15), border: Border.all(color: Colors.blueAccent), borderRadius: BorderRadius.circular(10)),
                      child: const Row(
                        children: [
                          Icon(Icons.visibility, color: Colors.blueAccent, size: 16),
                          SizedBox(width: 8),
                          Text("VIEW", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, letterSpacing: 2)),
                        ],
                      ),
                    ),
                  )
                ],
              )
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // --- DIALOGS (Overlays) ---
  // ============================================================================

  void _showRequestDetails(Map<String, dynamic> req) {
    final String activeImageUrl = req['screenshot'] ?? req['screenshot_url'] ?? '';
    final String modalTrxId = req['trx_id'] ?? 'N/A';

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 730),
          decoration: BoxDecoration(
            color: const Color(0xFF140518).withOpacity(0.95), 
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white10, width: 1.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30)]
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: Stack(
              children: [
                Positioned.fill(child: CustomPaint(painter: _AdminShatterPainterX())),
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("REQUEST DETAILS", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2)),
                          IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 1),
                    
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("PAYMENT SCREENSHOT", style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity, height: 250,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.4), 
                                borderRadius: BorderRadius.circular(15), 
                                border: Border.all(color: Colors.white10),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(15),
                                child: activeImageUrl.isNotEmpty && !activeImageUrl.contains("No Screenshot")
                                  ? Stack(
                                      children: [
                                        Positioned.fill(
                                          child: Image.network(
                                            activeImageUrl, 
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                        Positioned(
                                          top: 10, right: 10,
                                          child: Row(
                                            children: [
                                              Container(
                                                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                                child: IconButton(
                                                  icon: const Icon(Icons.fullscreen_rounded, color: Colors.blueAccent),
                                                  onPressed: () => _openFullscreenImage(activeImageUrl),
                                                  tooltip: "Full View",
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Container(
                                                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                                child: IconButton(
                                                  icon: const Icon(Icons.download_rounded, color: Colors.greenAccent),
                                                  onPressed: () {
                                                    final anchor = html.AnchorElement(href: activeImageUrl)
                                                      ..target = '_blank'
                                                      ..download = activeImageUrl.split('/').last;
                                                    anchor.click();
                                                  },
                                                  tooltip: "Download Image",
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      ],
                                    )
                                  : const Center(child: Icon(Icons.image_not_supported, color: Colors.white24, size: 50)),
                              ),
                            ),
                            
                            const SizedBox(height: 25),
                            
                            _detailRow("USERNAME", req['username']),
                            _detailRow("EMAIL", req['email']),
                            _detailRow("PLAN REQUESTED", req['plan_requested'], isHighlight: true),
                            
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("TRANSACTION ID", style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        modalTrxId, 
                                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace')
                                      ),
                                    ),
                                    if (modalTrxId != "N/A")
                                      IconButton(
                                        icon: const Icon(Icons.content_copy_rounded, color: Colors.greenAccent, size: 18),
                                        onPressed: () => _copyToClipboard(modalTrxId),
                                        constraints: const BoxConstraints(),
                                        padding: const EdgeInsets.all(4),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 15),
                              ],
                            ),
                            
                            _detailRow("DATE", req['date'] ?? 'Just Now'),
                          ],
                        ),
                      ),
                    ),

                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white10))),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ActionButton(text: "DECLINE", color: Colors.redAccent, icon: Icons.close, onTap: () {
                              Navigator.pop(context); 
                              _showDeclinePrompt(req['id'].toString());
                            }),
                          ),
                          const SizedBox(width: 15), 
                          Expanded(
                            child: _ActionButton(text: "APPROVE", color: Colors.greenAccent, icon: Icons.check, onTap: () {
                              Navigator.pop(context); 
                              _showApproveConfirm(req['id'].toString(), req['username']);
                            }),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String? value, {bool isHighlight = false}) {
    if (label == "TRANSACTION ID") return const SizedBox(); 
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            value ?? 'N/A', 
            style: TextStyle(color: isHighlight ? Colors.greenAccent : Colors.white, fontSize: 16, fontWeight: isHighlight ? FontWeight.w900 : FontWeight.bold),
            softWrap: true,
          ),
        ],
      ),
    );
  }

  void _showApproveConfirm(String reqId, String username) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF140518),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25), side: BorderSide(color: Colors.greenAccent.withOpacity(0.4), width: 1.5)),
        title: const Row(children: [Icon(Icons.verified_user, color: Colors.greenAccent), SizedBox(width: 10), Text("Confirm Approval", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900))]),
        content: Text("Are you sure you want to approve the plan for $username? Their account will be upgraded immediately.", style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent.withOpacity(0.2), side: const BorderSide(color: Colors.greenAccent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              Navigator.pop(context);
              _handleApprove(reqId);
            },
            child: const Text("YES, APPROVE", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  // 🔒 فکس: اپشنل ڈیکلائن مینیو - اگر ان پٹ خالی ہوگا تو یہ ڈاٹ "." بھیج کر بیک اینڈ کو سیف رکھے گا
  void _showDeclinePrompt(String reqId) {
    TextEditingController reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF140518),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25), side: BorderSide(color: Colors.redAccent.withOpacity(0.4), width: 1.5)),
        title: const Row(children: [Icon(Icons.warning_rounded, color: Colors.redAccent), SizedBox(width: 10), Text("Decline Request", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900))]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Please provide a reason for declining. This will be shown to the user.", style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 15),
            TextField(
              controller: reasonController,
              style: const TextStyle(color: Colors.white),
              maxLines: 2,
              decoration: InputDecoration(
                hintText: "e.g. Transaction ID not found in records... (Optional)", hintStyle: const TextStyle(color: Colors.white24),
                filled: true, fillColor: Colors.white.withOpacity(0.05),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent)),
              ),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              // اگر فیلڈ خالی ہے تو کسٹمر کو روکے بغیر چپ چاپ ڈاٹ "." بھیج دیں گے
              String finalReason = reasonController.text.trim().isEmpty ? "." : reasonController.text.trim();
              Navigator.pop(context);
              _handleDecline(reqId, finalReason);
            },
            child: const Text("SEND & DECLINE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }
}

// ============================================================================
// --- INTERNAL UI COMPONENTS & PAINTERS ---
// ============================================================================

class _ActionButton extends StatelessWidget {
  final String text; final Color color; final IconData icon; final VoidCallback onTap;
  const _ActionButton({required this.text, required this.color, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: color.withOpacity(0.1), border: Border.all(color: color.withOpacity(0.5)), borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}

class AdminLiveBackgroundX extends StatefulWidget { const AdminLiveBackgroundX({Key? key}) : super(key: key); @override _AdminLiveBackgroundXState createState() => _AdminLiveBackgroundXState(); }
class _AdminLiveBackgroundXState extends State<AdminLiveBackgroundX> with SingleTickerProviderStateMixin {
  late AnimationController _c; 
  @override 
  void initState() { 
    super.initState(); 
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat(); 
  }
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
