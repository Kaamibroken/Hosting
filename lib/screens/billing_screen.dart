import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:html' as html;

import 'auth/login_screen.dart';
import 'dashboard_screen.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({Key? key}) : super(key: key);
  @override
  _BillingScreenState createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  String activeView = "plans"; // Main options: "plans", "accessKey"
  String paymentTab = "local"; // Nested sub-tabs: "local", "crypto", "card"
  
  Map<String, dynamic>? selectedPlanForLocal;
  bool isLoading = true;
  bool isGatewayLoading = false; 

  Map profileData = {
    "username": "Loading...", 
    "email": "Loading...", 
    "plan_type": "none", 
    "pending_plan": null, 
    "declined_plan": null,
    "decline_reason": null
  };
  
  List<Map<String, dynamic>> purchaseLinks = []; 
  bool linksLoading = true; 

  String trxId = "";
  String? fileName; 
  Uint8List? fileBytes; 
  bool checkoutLoading = false;
  
  String accessKey = "";
  bool keyLoading = false;

  Timer? _expiryTimer;
  String _timeLeft = "";

  // 🎯 الٹرا ایڈوانسڈ: انفرادی گیٹ وے اور پلان لاکنگ انجن (Strict Map Separation)
  final Map<String, DateTime> _lockExpiries = {};
  final Map<String, String> _lockCountdowns = {};
  final Map<String, String> _lockUrls = {};
  Timer? _statelessLockTimer;

  final String jazzCashLogoUrl = "https://images.untrusted.site/logos/jazzcash_placeholder.png";

  final List<Map<String, dynamic>> plans = [
    {
      "id": "basic", 
      "name": "Basic Plan", 
      "priceLocal": "500", 
      "priceInt": "3", 
      "duration": "Month",
      "color": const Color(0xFF22D3EE), 
      "isPopular": false,
      "features": ["1 GB RAM Core Shared", "1 GB NVMe Cloud Storage", "Up to 20 Active Deployments", "Standard Tech Support", "Basic DDoS Shields Built-in"]
    },
    {
      "id": "pro", 
      "name": "Pro Plan", 
      "priceLocal": "1000", 
      "priceInt": "7", 
      "duration": "Month",
      "color": const Color(0xFFA855F7), 
      "isPopular": true,
      "features": ["2 GB Dedicated RAM", "5 GB High-Speed NVMe Storage", "Unlimited Cloud Deployments", "24/7 Priority VIP Support", "Advanced Layer-7 DDoS Protection", "Always Online (Zero Sleep Mode)"]
    }
  ];

  @override
  void OphthalmologyInitState() {
    // Intentionally left for metadata tracing context if required
  }

  @override
  void initState() {
    super.initState();
    _fetchData();
    _initStatelessLockWatchdog();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _statelessLockTimer?.cancel();
    super.dispose();
  }

  // 🧠 واچ ڈاگ ٹائمر: ہر ایک سیکنڈ بعد صرف اسی مخصوص پلان کی کیشے مانیٹر کرتا ہے
  void _initStatelessLockWatchdog() {
    _statelessLockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      List<String> expiredKeys = [];
      
      _lockExpiries.forEach((key, expiry) {
        if (now.isAfter(expiry)) {
          expiredKeys.add(key);
        } else {
          final diff = expiry.difference(now);
          final minutes = diff.inMinutes.toString().padLeft(2, '0');
          final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
          _lockCountdowns[key] = "$minutes:$seconds";
        }
      });
      
      if (expiredKeys.isNotEmpty) {
        setState(() {
          for (var k in expiredKeys) {
            _lockExpiries.remove(k);
            _lockCountdowns.remove(k);
            _lockUrls.remove(k);
          }
        });
      } else if (mounted && _lockExpiries.isNotEmpty) {
        setState(() {});
      }
    });
  }

  void _lockSpecificGatewayContext(String gateway, String planId, String url) {
    final key = "${gateway}_$planId";
    setState(() {
      _lockExpiries[key] = DateTime.now().add(const Duration(minutes: 10));
      _lockUrls[key] = url;
    });
  }

  void _startExpiryTimer(String expiryStr) {
    DateTime expiry = DateTime.parse(expiryStr).toLocal();
    _expiryTimer?.cancel();
    
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      if (now.isAfter(expiry)) {
        setState(() => _timeLeft = "EXPIRED");
        timer.cancel();
      } else {
        final diff = expiry.difference(now);
        String days = diff.inDays > 0 ? "${diff.inDays}d " : "";
        String hours = "${(diff.inHours % 24).toString().padLeft(2, '0')}h ";
        String mins = "${(diff.inMinutes % 60).toString().padLeft(2, '0')}m ";
        String secs = "${(diff.inSeconds % 60).toString().padLeft(2, '0')}s";
        setState(() => _timeLeft = days + hours + mins + secs);
      }
    });
  }

  Future<void> _fetchData() async {
    try {
      final res = await http.get(Uri.parse('/api/user/profile'));
      final linkRes = await http.get(Uri.parse('/api/billing/key-links'));
      
      if (res.statusCode == 200) {
        setState(() {
          profileData = jsonDecode(res.body);
          
          if (linkRes.statusCode == 200) {
            final List<dynamic> data = jsonDecode(linkRes.body);
            purchaseLinks = data.map((e) => {"name": e["name"], "url": e["url"]}).toList();
          }
          
          isLoading = false;
          linksLoading = false;

          if (profileData['plan_expiry'] != null && profileData['plan_expiry'].toString().isNotEmpty) {
            _startExpiryTimer(profileData['plan_expiry']);
          } else {
            _timeLeft = "LIFETIME";
          }
        });
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const LoginScreen()));
      }
    } catch (e) {
      PremiumToast.show(context, "Cloud server handshake failed", false);
      setState(() => linksLoading = false);
    }
  }

  // 🚀 سیکیور فلوٹنگ ونڈو پوپ اپ: ری ڈائریکٹس اور ریفیوزل کو 100٪ بائی پاس کرتا ہے
  void _openSecureFloatingContextWindow(String targetUrl) {
    html.window.open(
      targetUrl, 
      'Secure Payment Panel', 
      'width=950,height=750,location=no,toolbar=no,menubar=no,status=no,scrollbars=yes,resizable=yes'
    );
  }

  Future<void> _handleLocalFormSubmit(String planId) async {
    if (trxId.isEmpty || fileBytes == null || fileName == null) {
      PremiumToast.show(context, "Please enter Receipt Transaction ID and upload Proof Image", false);
      return;
    }
    setState(() => checkoutLoading = true);

    try {
      var request = http.MultipartRequest('POST', Uri.parse('/api/billing/submit'));
      request.fields['plan'] = planId;
      request.fields['trxId'] = trxId;
      request.files.add(http.MultipartFile.fromBytes('file', fileBytes!, filename: fileName)); 

      var response = await request.send();
      if (response.statusCode == 200) {
        PremiumToast.show(context, "Payment statement locked! Admin will review details shortly.", true);
        Future.delayed(const Duration(seconds: 2), () {
          _fetchData();
          setState(() {
            selectedPlanForLocal = null;
            trxId = "";
            fileName = null;
            fileBytes = null;
          });
        });
      } else {
        PremiumToast.show(context, "Submission refused by banking api, try again", false);
      }
    } catch (e) {
      PremiumToast.show(context, "Handshake timeout during transmission", false);
    } finally { setState(() => checkoutLoading = false); }
  }

  Future<void> _launchCryptoGateway(String planId) async {
    setState(() => isGatewayLoading = true);
    try {
      final response = await http.post(
        Uri.parse('/api/payment/crypto-create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'plan_type': planId})
      );
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['payment_url'] != null) {
        String targetUrl = data['payment_url'];
        _lockSpecificGatewayContext("crypto", planId, targetUrl);
        setState(() => isGatewayLoading = false);
        _openSecureFloatingContextWindow(targetUrl);
      } else {
        setState(() => isGatewayLoading = false);
        PremiumToast.show(context, "Crypto Mode Currently Not Available Please Use Credit Card Or Local.", false);
      }
    } catch (e) {
      setState(() => isGatewayLoading = false);
      PremiumToast.show(context, "API communication error occurred", false);
    }
  }

  Future<void> _launchCardGateway(String planId) async {
    setState(() => isGatewayLoading = true);
    try {
      final response = await http.post(
        Uri.parse('/api/payment/card-create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'plan_type': planId})
      );
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['payment_url'] != null) {
        String targetUrl = data['payment_url'];
        _lockSpecificGatewayContext("card", planId, targetUrl);
        setState(() => isGatewayLoading = false);
        _openSecureFloatingContextWindow(targetUrl);
      } else {
        setState(() => isGatewayLoading = false);
        PremiumToast.show(context, "Credit Card Currently Not Available Please Use Crypto Or Local.", false);
      }
    } catch (e) {
      setState(() => isGatewayLoading = false);
      PremiumToast.show(context, "Secure terminal connection lost", false);
    }
  }

  Future<void> _handleKeyRedeem() async {
    if (accessKey.isEmpty) return;
    setState(() => keyLoading = true);
    try {
      final res = await http.post(
        Uri.parse('/api/user/redeem'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'access_key': accessKey.toUpperCase()})
      );
      final data = jsonDecode(res.body);
      
      if (res.statusCode == 200) {
        PremiumToast.show(context, "Workspace upgraded to premium level successfully!", true);
        Future.delayed(const Duration(seconds: 2), () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const DashboardScreen())));
      } else {
        PremiumToast.show(context, data['message'] ?? "This access token does not exist", false);
      }
    } catch (e) {
      PremiumToast.show(context, "Token authentication failure", false);
    } finally { setState(() => keyLoading = false); }
  }

  void _pickImage() {
    final html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
    uploadInput.accept = 'image/*';
    uploadInput.click();

    uploadInput.onChange.listen((e) {
      final files = uploadInput.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        reader.onLoadEnd.listen((e) {
          setState(() {
            fileName = file.name;
            fileBytes = reader.result as Uint8List;
          });
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Scaffold(backgroundColor: Color(0xFF0A0A10), body: Center(child: CircularProgressIndicator(color: Color(0xFF45F3FF))));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A10),
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF45F3FF)), onPressed: () => Navigator.pop(context)),
        title: const Text("BILLING CENTER", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 16, color: Colors.white)),
      ),
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0xFF0F3B57), Color(0xFF082236), Color(0xFF020E18)], radius: 1.5))),
          const Positioned.fill(child: LiveCyberBackgroundB()), 

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildViewSwitcher(),
                  const SizedBox(height: 30),
                  if (activeView == "plans") _buildPlansSection(),
                  if (activeView == "accessKey") _buildAccessKeyView(),
                ],
              ),
            ),
          ),

          if (isGatewayLoading)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF45F3FF)),
                    const SizedBox(height: 20),
                    const Text(
                      "Please Wait...",
                      style: TextStyle(color: Color(0xFF45F3FF), fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildViewSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.04), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _switcherBtn("PLANS", Icons.layers_rounded, activeView == "plans", () => setState(() => activeView = "plans")),
          _switcherBtn("ACCESS KEY", Icons.token_rounded, activeView == "accessKey", () => setState(() => activeView = "accessKey")),
        ],
      ),
    );
  }

  Widget _switcherBtn(String text, IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(color: active ? const Color(0xFF45F3FF).withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: active ? const Color(0xFF45F3FF) : Colors.white38),
            const SizedBox(width: 8),
            Text(text, style: TextStyle(color: active ? const Color(0xFF45F3FF) : Colors.white38, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlansSection() {
    return Column(
      children: [
        // 🗺️ THE 3 PAYMENTS SUB-TABS MATRIX
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
          child: Row(
            children: [
              _paymentTabBtn("LOCAL", "local", Icons.account_balance_wallet_rounded),
              _paymentTabBtn("CRYPTO", "crypto", Icons.currency_bitcoin_rounded),
              _paymentTabBtn("CREDIT CARD", "card", Icons.credit_card_rounded),
            ],
          ),
        ),
        
        const SizedBox(height: 25),

        ...plans.map((plan) {
          bool isCurrent = profileData['plan_type'] == plan['id'];
          bool isPending = profileData['pending_plan'] == plan['id'];
          bool isDeclined = profileData['declined_plan'] == plan['id'];
          Color planColor = plan['color'];

          // 🎯 فکس: اب لاک صرف اسی مخصوص ٹیب اور پلان کے امتزاج (Key) پر کام کرے گا
          String lockKey = "${paymentTab}_${plan['id']}";
          bool isThisButtonLocked = _lockExpiries.containsKey(lockKey);

          return Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: planColor.withOpacity(0.04),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: plan['isPopular'] ? planColor.withOpacity(0.4) : Colors.white10, width: plan['isPopular'] ? 2 : 1),
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (plan['isPopular']) 
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: planColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Text("POPULAR CHOICE", style: TextStyle(color: planColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5))),
                    
                    const SizedBox(height: 15),
                    Text(plan['name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 6),
                    
                    if (paymentTab == "local")
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("PKR ${plan['priceLocal']}", style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
                          Padding(padding: const EdgeInsets.only(bottom: 4, left: 6), child: Text("/ ${plan['duration']}", style: const TextStyle(color: Colors.white38, fontSize: 13))),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("\$${plan['priceInt']}.00", style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
                          Padding(padding: const EdgeInsets.only(bottom: 4, left: 6), child: Text("USD / ${plan['duration']}", style: const TextStyle(color: Colors.white38, fontSize: 13))),
                        ],
                      ),

                    const SizedBox(height: 20),
                    
                    ...List.generate(plan['features'].length, (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(children: [Icon(Icons.check_circle_outline_rounded, color: planColor, size: 18), const SizedBox(width: 10), Expanded(child: Text(plan['features'][i], style: const TextStyle(color: Colors.white70, fontSize: 13)))]),
                    )),
                    
                    const SizedBox(height: 20),

                    if (isDeclined && paymentTab == "local")
                      Container(
                        margin: const EdgeInsets.only(bottom: 15),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.redAccent.withOpacity(0.3))),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Text("Declined: ${profileData['decline_reason'] ?? 'Invalid details provided.'}", style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold))),
                          ],
                        ),
                      ),

                    if (isCurrent)
                      _infoBanner("THIS WORKSPACE IS ACTIVE", Colors.greenAccent)
                    else if (isPending && paymentTab == "local")
                      _infoBanner("VERIFICATION PENDING IN CLOUD", Colors.amber)
                    else if (paymentTab == "local") ...[
                      if (selectedPlanForLocal?['id'] == plan['id']) ...[
                        _buildLocalInteractiveForm(plan),
                      ] else ...[
                        _actionBtn(
                          text: "BUY PLAN", 
                          color: planColor, 
                          onTap: () => setState(() => selectedPlanForLocal = plan)
                        )
                      ]
                    ] else ...[
                      // 🎯 فکس: اب صرف مخصوص لاکڈ بٹن ہی رینڈر ہوگا، باقی اوپن رہیں گے
                      if (isThisButtonLocked)
                        _actionBtn(
                          text: "CHECKOUT ACTIVE (${_lockCountdowns[lockKey]})", 
                          color: Colors.amber, 
                          onTap: () => _openSecureFloatingContextWindow(_lockUrls[lockKey]!)
                        )
                      else
                        _actionBtn(
                          text: "BUY PLAN", 
                          color: planColor, 
                          onTap: () {
                            if (paymentTab == "crypto") {
                              _launchCryptoGateway(plan['id']);
                            } else {
                              _launchCardGateway(plan['id']);
                            }
                          }
                        )
                    ]
                  ],
                ),
                Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _RealisticShatterPainterB()))),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _paymentTabBtn(String label, String value, IconData icon) {
    bool isSelected = paymentTab == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          paymentTab = value;
          selectedPlanForLocal = null; 
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: isSelected ? const Color(0xFF45F3FF).withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? const Color(0xFF45F3FF) : Colors.white38, size: 16),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocalInteractiveForm(Map<String, dynamic> plan) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(jazzCashLogoUrl, width: 28, height: 28, errorBuilder: (c,e,s) => const Icon(Icons.wallet, color: Colors.amber))),
              const SizedBox(width: 10),
              const Text("JazzCash Direct Transfer", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 15),
          const Text("Account Title: Muhammad Arslan", style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Number: 0302 7665767", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'monospace')),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.amber, size: 16),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: "03027665767"));
                  PremiumToast.show(context, "Account number copied", true);
                },
              )
            ],
          ),
          const Divider(color: Colors.white10, height: 20),
          const Text("ENTER TRANSACTION ID (12 DIGITS)", style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            onChanged: (v) => setState(() => trxId = v),
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 14),
            decoration: InputDecoration(hintText: "TID from message payload", hintStyle: const TextStyle(color: Colors.white24, fontSize: 12), filled: true, fillColor: Colors.white.withOpacity(0.02), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
          ),
          const SizedBox(height: 15),
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: fileName != null ? const Color(0xFF45F3FF).withOpacity(0.08) : Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(10), border: Border.all(color: fileName != null ? const Color(0xFF45F3FF) : Colors.white10)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(fileName != null ? Icons.done : Icons.cloud_upload, color: fileName != null ? const Color(0xFF45F3FF) : Colors.white38, size: 16),
                  const SizedBox(width: 8),
                  Text(fileName ?? "Upload Proof Screenshot", style: TextStyle(color: fileName != null ? Colors.white : Colors.white38, fontSize: 12)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: OutlinedButton(child: const Text("CANCEL", style: TextStyle(color: Colors.white60)), onPressed: () => setState(() => selectedPlanForLocal = null))),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF45F3FF).withOpacity(0.2)),
                  child: Text(checkoutLoading ? "LOCKING..." : "SUBMIT ORDER", style: const TextStyle(color: Color(0xFF45F3FF), fontWeight: FontWeight.bold)),
                  onPressed: checkoutLoading ? null : () => _handleLocalFormSubmit(plan['id']),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _infoBanner(String msg, Color color) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: color.withOpacity(0.08), border: Border.all(color: color.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)),
      child: Center(child: Text(msg, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1))),
    );
  }

  Widget _actionBtn({required String text, required Color color, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: color.withOpacity(0.12), border: Border.all(color: color), borderRadius: BorderRadius.circular(12)),
        child: Center(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1))),
      ),
    );
  }

  Widget _buildAccessKeyView() {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.05), borderRadius: BorderRadius.circular(25), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.2))),
      child: Column(
        children: [
          const Icon(Icons.vpn_key_rounded, color: Color(0xFF45F3FF), size: 45),
          const SizedBox(height: 20),
          const Text("REDEEM ACCESS KEY", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          const Text("Enter the secure VIP code provided by administration to instantly unlock authorization parameters.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
          const SizedBox(height: 30),
          
          TextField(
            onChanged: (v) => setState(() => accessKey = v),
            style: const TextStyle(color: Color(0xFF45F3FF), fontWeight: FontWeight.bold, letterSpacing: 5, fontSize: 16),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: "SILENT-XXXX", hintStyle: TextStyle(color: const Color(0xFF45F3FF).withOpacity(0.15), letterSpacing: 5),
              filled: true, fillColor: Colors.black26,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Colors.white10)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFF45F3FF))),
            ),
          ),
          
          const SizedBox(height: 20),
          CompactShatteredButtonB(text: keyLoading ? "VERIFYING TOKEN..." : "REDEEM", onPressed: _handleKeyRedeem),
          
          const SizedBox(height: 30),
          const Divider(color: Colors.white10),
          const SizedBox(height: 20),
          
          if (linksLoading)
            const SizedBox(height: 30, width: 30, child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2))
          else if (purchaseLinks.isNotEmpty)
            ...purchaseLinks.map((link) => Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: GestureDetector(
                onTap: () => html.window.open(link['url'], '_blank'),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                  decoration: BoxDecoration(color: Colors.amber.withOpacity(0.04), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber.withOpacity(0.25))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.shopping_cart, color: Colors.amber, size: 16),
                      const SizedBox(width: 10),
                      Text(link['name'].toString().toUpperCase(), style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
                    ],
                  ),
                ),
              ),
            )).toList()
          else
            const Text("No external links mapped in repository grid currently.", style: TextStyle(color: Colors.white38, fontSize: 12))
        ],
      ),
    );
  }
}

// ============================================================================
// --- UI ELEMENTS, BACKGROUND SYSTEMS AND CUSTOM PAINTERS ---
// ============================================================================

class CompactShatteredButtonB extends StatefulWidget {
  final String text; final VoidCallback onPressed;
  const CompactShatteredButtonB({Key? key, required this.text, required this.onPressed}) : super(key: key);
  @override _CompactShatteredButtonBState createState() => _CompactShatteredButtonBState();
}
class _CompactShatteredButtonBState extends State<CompactShatteredButtonB> with SingleTickerProviderStateMixin {
  late AnimationController _wave; @override void initState() { super.initState(); _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(); }
  @override void dispose() { _wave.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 240, height: 46,
          decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.6))),
          child: Stack(children: [
            CustomPaint(size: const Size(240, 46), painter: _RealisticShatterPainterB()),
            AnimatedBuilder(animation: _wave, builder: (_, __) => Positioned(left: -100 + (_wave.value * 480), top: -50, bottom: -50, child: Transform.rotate(angle: 0.4, child: Container(width: 12, decoration: BoxDecoration(color: Colors.white.withOpacity(0.4), boxShadow: [BoxShadow(color: const Color(0xFF45F3FF), blurRadius: 15)]))))),
            Center(child: Text(widget.text, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12, letterSpacing: 1))),
          ]),
        ),
      ),
    );
  }
}

class LiveCyberBackgroundB extends StatefulWidget { const LiveCyberBackgroundB({Key? key}) : super(key: key); @override _LiveCyberBackgroundBState createState() => _LiveCyberBackgroundBState(); }
class _LiveCyberBackgroundBState extends State<LiveCyberBackgroundB> with SingleTickerProviderStateMixin {
  late AnimationController _c; @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _DiagonalWavePainterB(_c.value)));
}
class _DiagonalWavePainterB extends CustomPainter {
  final double progress; _DiagonalWavePainterB(this.progress);
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF45F3FF).withOpacity(0.02)..strokeWidth = 1.2..style = PaintingStyle.stroke;
    double offset = progress * 100;
    for (double i = -size.height; i < size.width + size.height; i += 40) { canvas.drawLine(Offset(i + offset, 0), Offset(i - size.height + offset, size.height), p); }
  }
  @override bool shouldRepaint(covariant CustomPainter old) => true;
}

class _RealisticShatterPainterB extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.12)..strokeWidth = 0.8..style = PaintingStyle.stroke;
    final path = Path();
    for (int i = 0; i < 10; i++) {
      double cx = Random(i).nextDouble() * size.width; double cy = Random(i+1).nextDouble() * size.height;
      for (int j = 0; j < 5; j++) { double a = (j * 45) * (pi / 180); path.moveTo(cx, cy); path.lineTo(cx + cos(a) * 25, cy + sin(a) * 25); }
    }
    canvas.drawPath(path, p);
  }
  @override bool shouldRepaint(CustomPainter old) => false;
}