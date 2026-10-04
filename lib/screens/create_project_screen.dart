import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:html' as html; 

import 'auth/login_screen.dart'; 
import 'dashboard_screen.dart'; 
import 'billing_screen.dart';
import 'project_dashboard_screen.dart'; 

class CreateProjectScreen extends StatefulWidget {
  const CreateProjectScreen({Key? key}) : super(key: key);

  @override
  _CreateProjectScreenState createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends State<CreateProjectScreen> with TickerProviderStateMixin {
  // --- LIMITS & PLAN STATE ---
  bool _isLoadingLimits = true;
  bool _canCreate = false;
  String _userPlan = "Loading...";
  int _projectCount = 0;
  int _planLimit = 0;

  // --- FORM STATE ---
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _buildCmdController = TextEditingController();
  final TextEditingController _startCmdController = TextEditingController();
  
  String selectedRuntime = "Node.js";
  bool showAdvanced = false;
  bool _isDeploying = false;

  // --- FILE UPLOAD & PROGRESS STATE ---
  List<html.File> selectedFiles = [];
  String _currentUploadingFileName = "";
  int _currentUploadingFileIndex = 0;
  double _currentFileProgress = 0.0; // 0.0 to 1.0

  final List<Map<String, dynamic>> runtimes = [
    {"name": "Node.js", "icon": Icons.javascript_rounded, "color": Colors.greenAccent, "build": "npm install", "start": "npm start"},
    {"name": "Python", "icon": Icons.terminal_rounded, "color": Colors.amber, "build": "pip install -r requirements.txt", "start": "python main.py"},
    {"name": "Go (Golang)", "icon": Icons.memory_rounded, "color": const Color(0xFF22D3EE), "build": "go mod tidy", "start": "go run ."},
    {"name": "Static HTML", "icon": Icons.html_rounded, "color": Colors.orangeAccent, "build": "", "start": "serve"},
    {"name": "PHP", "icon": Icons.webhook_rounded, "color": const Color(0xFF6366F1), "build": "", "start": "php -S 0.0.0.0:80"},
    {"name": "Rust", "icon": Icons.settings_system_daydream, "color": Colors.redAccent, "build": "cargo build --release", "start": "cargo run --release"},
  ];

  @override
  void initState() {
    super.initState();
    _checkUserLimits();
    _updateCommandsForRuntime(selectedRuntime);
  }

  Future<void> _checkUserLimits() async {
    try {
      final profileRes = await http.get(Uri.parse('/api/user/profile'));
      final projectsRes = await http.get(Uri.parse('/api/user/projects'));

      if (profileRes.statusCode == 200 && projectsRes.statusCode == 200) {
        final profile = jsonDecode(profileRes.body);
        final projects = jsonDecode(projectsRes.body) as List;

        _userPlan = profile['plan'] ?? "No Plan";
        _projectCount = projects.length;

        if (_userPlan == "Pro Plan") _planLimit = 999999; 
        else if (_userPlan == "Basic Plan") _planLimit = 20;
        else if (_userPlan == "Free Tier") _planLimit = 5;
        else _planLimit = 0; 

        setState(() {
          _canCreate = _projectCount < _planLimit;
          _isLoadingLimits = false;
        });
      } else {
        PremiumToast.show(context, "Session expired.", false);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const LoginScreen()));
      }
    } catch (e) {
      PremiumToast.show(context, "Network Error checking limits.", false);
      Navigator.pop(context);
    }
  }

  void _updateCommandsForRuntime(String rt) {
    var runtimeData = runtimes.firstWhere((element) => element['name'] == rt);
    setState(() {
      _buildCmdController.text = runtimeData['build'];
      _startCmdController.text = runtimeData['start'];
    });
  }

  void _pickFiles() {
    final uploadInput = html.FileUploadInputElement();
    uploadInput.multiple = true;
    uploadInput.click();

    uploadInput.onChange.listen((e) {
      if (uploadInput.files != null && uploadInput.files!.isNotEmpty) {
        setState(() {
          for (var file in uploadInput.files!) {
            if (!selectedFiles.any((f) => f.name == file.name && f.size == file.size)) {
              selectedFiles.add(file);
            }
          }
        });
      }
    });
  }

  Future<void> _handleDeploy() async {
    if (_nameController.text.isEmpty) { PremiumToast.show(context, "Project name is required!", false); return; }
    if (selectedFiles.isEmpty) { PremiumToast.show(context, "Please upload your source code or ZIP file!", false); return; }
    
    setState(() {
      _isDeploying = true;
      _currentFileProgress = 0.0;
      _currentUploadingFileIndex = 0;
      _currentUploadingFileName = selectedFiles.first.name;
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('/api/project/create'));
      request.fields['name'] = _nameController.text;
      request.fields['runtime'] = selectedRuntime;
      request.fields['build_cmd'] = _buildCmdController.text;
      request.fields['start_cmd'] = _startCmdController.text;

      for (int i = 0; i < selectedFiles.length; i++) {
        var file = selectedFiles[i];
        setState(() {
          _currentUploadingFileName = file.name;
          _currentUploadingFileIndex = i;
          _currentFileProgress = 0.0;
        });

        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        await reader.onLoadEnd.first; 
        final bytes = reader.result as Uint8List;

        for (double p = 0.1; p <= 1.0; p += 0.2) {
          await Future.delayed(const Duration(milliseconds: 60));
          setState(() {
            _currentFileProgress = p > 1.0 ? 1.0 : p;
          });
        }

        request.files.add(http.MultipartFile.fromBytes('files[]', bytes, filename: file.name));
      }

      var response = await request.send();
      var resBody = await response.stream.bytesToString();
      var data = jsonDecode(resBody);

      if (response.statusCode == 200) {
        PremiumToast.show(context, "Project '${_nameController.text}' Deployed Successfully!", true);
        
        String newProjectId = data['project_id'] ?? "";
        String newProjectName = _nameController.text;
        
        Future.delayed(const Duration(seconds: 1), () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (c) => ProjectDashboardScreen(
                projectId: newProjectId, 
                projectName: newProjectName
              )
            )
          );
        });
      } else {
        PremiumToast.show(context, data['message'] ?? "Deploy Failed", false);
      }
    } catch (e) {
      PremiumToast.show(context, "Network Error during deployment!", false);
    } finally {
      setState(() => _isDeploying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A10),
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF45F3FF)), onPressed: () => Navigator.pop(context)),
        title: const Row(children: [Icon(Icons.rocket_launch_rounded, color: Color(0xFF45F3FF), size: 22), SizedBox(width: 10), Text("INITIALIZE PROJECT", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 16, color: Colors.white))]),
      ),
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0xFF0F3B57), Color(0xFF082236), Color(0xFF020E18)], radius: 1.5))),
          const Positioned.fill(child: LiveCyberBackgroundX()),

          SafeArea(
            child: _isLoadingLimits 
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF45F3FF)))
                : !_canCreate 
                    ? _buildLimitReachedScreen() 
                    : _buildFormScreen(),
          ),
        ],
      ),
    );
  }

  Widget _buildLimitReachedScreen() {
    bool hasNoPlan = _planLimit == 0;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.05), borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1.5), boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.1), blurRadius: 30)]),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_person_rounded, color: Colors.redAccent, size: 70),
            const SizedBox(height: 20),
            Text(hasNoPlan ? "NO ACTIVE PLAN" : "PROJECT LIMIT REACHED", style: const TextStyle(color: Colors.redAccent, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 20),
            
            if (!hasNoPlan) ...[
              Text("Your current plan is ${_userPlan.toUpperCase()}.", style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 5),
              Text("Total project limit: $_planLimit", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text("You already have $_projectCount projects running.", style: const TextStyle(color: Colors.white54, fontSize: 14)),
              const SizedBox(height: 20),
              const Text("To deploy more applications and unlock advanced resources, please upgrade your cloud infrastructure.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5)),
            ] else ...[
              const Text("You currently do not have any active hosting plan.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 20),
              const Text("Please subscribe to a plan or redeem an access key to start deploying applications.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5)),
            ],

            const SizedBox(height: 30),
            GestureDetector(
              onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const BillingScreen())),
              child: Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), border: Border.all(color: Colors.redAccent), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.redAccent.withOpacity(0.1), blurRadius: 15)]),
                child: const Center(child: Text("UPGRADE PLAN", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w900, letterSpacing: 2))),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildFormScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(25.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("PROJECT NAME", style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.02), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.3))),
            child: TextField(controller: _nameController, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1), decoration: InputDecoration(hintText: "e.g. silent-api-v2", hintStyle: TextStyle(color: Colors.white.withOpacity(0.2), letterSpacing: 2), prefixIcon: const Icon(Icons.create_new_folder_outlined, color: Color(0xFF45F3FF)), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18))),
          ),
          
          const SizedBox(height: 30),
          
          const Text("SELECT RUNTIME (ENVIRONMENT)", style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.8, crossAxisSpacing: 15, mainAxisSpacing: 15),
            itemCount: runtimes.length,
            itemBuilder: (context, i) {
              bool isSelected = selectedRuntime == runtimes[i]['name'];
              Color tColor = runtimes[i]['color'];
              return GestureDetector(
                onTap: () { setState(() => selectedRuntime = runtimes[i]['name']); _updateCommandsForRuntime(runtimes[i]['name']); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(color: isSelected ? tColor.withOpacity(0.15) : Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(20), border: Border.all(color: isSelected ? tColor : Colors.white10, width: isSelected ? 1.5 : 1), boxShadow: isSelected ? [BoxShadow(color: tColor.withOpacity(0.2), blurRadius: 15)] : []),
                  child: Stack(
                    children: [
                      if (isSelected) Positioned.fill(child: CustomPaint(painter: _LightShatterPainterCP())),
                      Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(runtimes[i]['icon'], color: isSelected ? tColor : Colors.white38, size: 30), const SizedBox(height: 8), Text(runtimes[i]['name'], style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontWeight: FontWeight.bold, fontSize: 12))])),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 30),

          const Text("SOURCE CODE", style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _isDeploying ? null : _pickFiles,
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(color: selectedFiles.isNotEmpty ? const Color(0xFF45F3FF).withOpacity(0.05) : Colors.black.withOpacity(0.3), borderRadius: BorderRadius.circular(20), border: Border.all(color: selectedFiles.isNotEmpty ? const Color(0xFF45F3FF).withOpacity(0.5) : Colors.white10)),
              child: Column(
                children: [
                  Icon(selectedFiles.isNotEmpty ? Icons.folder_zip : Icons.cloud_upload_outlined, color: selectedFiles.isNotEmpty ? const Color(0xFF45F3FF) : Colors.white38, size: 40),
                  const SizedBox(height: 15),
                  if (selectedFiles.isEmpty) ...[
                    const Text("Click to upload source files", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    const Text("Select multiple files or upload a .zip archive", style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ] else ...[
                    Text("${selectedFiles.length} file(s) mapped", style: const TextStyle(color: const Color(0xFF45F3FF), fontWeight: FontWeight.w900)),
                    const SizedBox(height: 5),
                    Text("Ready for private cluster offloading", style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ]
                ],
              ),
            ),
          ),

          if (_isDeploying) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(_currentUploadingFileName, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
                      const SizedBox(width: 10),
                      Text("File ${_currentUploadingFileIndex + 1} of ${selectedFiles.length}", style: const TextStyle(color: Color(0xFF45F3FF), fontSize: 12, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: _currentFileProgress,
                            backgroundColor: Colors.white10,
                            color: const Color(0xFF45F3FF),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Text("${(_currentFileProgress * 100).toInt()}%", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ],

          if (selectedFiles.isNotEmpty) ...[
            const SizedBox(height: 15),
            // 🌟 فکس: maxHeight کو ہٹا کر Container کے اندر BoxConstraints لگا دیا ہے تاکہ ہائٹ اوور فلو نہ ہو
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(15)),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: selectedFiles.length,
                itemBuilder: (context, idx) {
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
                    child: Row(
                      children: [
                        const Icon(Icons.insert_drive_file_outlined, color: Colors.white38, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(selectedFiles[idx].name, style: const TextStyle(color: Colors.white70, fontSize: 13, overflow: TextOverflow.ellipsis))),
                        const SizedBox(width: 10),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: _isDeploying ? null : () {
                            setState(() {
                              selectedFiles.removeAt(idx);
                            });
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 30),

          GestureDetector(
            onTap: () => setState(() => showAdvanced = !showAdvanced),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(children: [Icon(Icons.settings_suggest, color: Colors.amber, size: 18), SizedBox(width: 10), Text("ADVANCED SETTINGS", style: TextStyle(color: Colors.amber, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.bold))]),
                Icon(showAdvanced ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.amber),
              ],
            ),
          ),
          
          if (showAdvanced) ...[
            const SizedBox(height: 20),
            _buildCommandInput("BUILD COMMAND", _buildCmdController, "e.g. npm install"),
            const SizedBox(height: 15),
            _buildCommandInput("START COMMAND", _startCmdController, "e.g. npm start"),
          ],

          const SizedBox(height: 50),
          Center(child: _DeployShatteredButton(text: _isDeploying ? "DEPLOYING TO CLOUD..." : "DEPLOY PROJECT", isLoading: _isDeploying, onPressed: _handleDeploy)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCommandInput(String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 🌟 فکس: 'Cross CrossAxisAlignment' کا ٹائپو فکس کر دیا گیا ہے
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 14),
          decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.white24), filled: true, fillColor: Colors.black.withOpacity(0.3), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.amber))),
        ),
      ],
    );
  }
}

class _DeployShatteredButton extends StatefulWidget {
  final String text; final bool isLoading; final VoidCallback onPressed;
  const _DeployShatteredButton({Key? key, required this.text, required this.isLoading, required this.onPressed}) : super(key: key);
  @override __DeployShatteredButtonState createState() => __DeployShatteredButtonState();
}
class __DeployShatteredButtonState extends State<_DeployShatteredButton> with TickerProviderStateMixin {
  late AnimationController _wave; late AnimationController _glow;
  @override void initState() { super.initState(); _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(); _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true); }
  @override void dispose() { _wave.dispose(); _glow.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.isLoading ? null : widget.onPressed,
      child: AnimatedBuilder(animation: _glow, builder: (context, child) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity, height: 65, decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.7), width: 1.5), boxShadow: [BoxShadow(color: const Color(0xFF45F3FF).withOpacity(0.3 + (_glow.value * 0.2)), blurRadius: 20 + (_glow.value * 10), spreadRadius: 3 + (_glow.value * 2))]),
          child: Stack(children: [
            CustomPaint(size: const Size(double.infinity, 65), painter: _RealisticShatterPainterCP()),
            if (!widget.isLoading) AnimatedBuilder(animation: _wave, builder: (context, child) => Positioned(left: -150 + (_wave.value * 700), top: -50, bottom: -50, child: Transform.rotate(angle: 0.4, child: Container(width: 12, decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.9), blurRadius: 20, spreadRadius: 5), BoxShadow(color: const Color(0xFF45F3FF).withOpacity(1.0), blurRadius: 30, spreadRadius: 8)]))))),
            Center(child: widget.isLoading ? const SizedBox(width: 25, height: 25, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) : Text(widget.text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 4))),
          ]),
        ),
      )),
    );
  }
}

class LiveCyberBackgroundX extends StatefulWidget { const LiveCyberBackgroundX({Key? key}) : super(key: key); @override _LiveCyberBackgroundXState createState() => _LiveCyberBackgroundXState(); }
class _LiveCyberBackgroundXState extends State<LiveCyberBackgroundX> with SingleTickerProviderStateMixin {
  late AnimationController _c; @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _DiagonalWavePainterX(_c.value)));
}
class _DiagonalWavePainterX extends CustomPainter {
  final double progress; _DiagonalWavePainterX(this.progress);
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF45F3FF).withOpacity(0.03)..strokeWidth = 1.5..style = PaintingStyle.stroke;
    double offset = progress * (size.width * 2);
    for (double i = -size.height * 2; i < size.width * 2; i += 40) { canvas.drawLine(Offset(i + offset, 0), Offset(i - size.height + offset, size.height), p); }
  }
  @override bool shouldRepaint(covariant CustomPainter old) => true;
}
class _LightShatterPainterCP extends CustomPainter {
  @override void paint(Canvas canvas, Size size) { final p = Paint()..color = Colors.white.withOpacity(0.08)..strokeWidth = 1.0..style = PaintingStyle.stroke; final path = Path(); path.moveTo(size.width * 0.7, 0); path.lineTo(size.width, size.height * 0.4); path.moveTo(0, size.height * 0.6); path.lineTo(size.width * 0.4, size.height); canvas.drawPath(path, p); }
  @override bool shouldRepaint(CustomPainter old) => false;
}
class _RealisticShatterPainterCP extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.2)..strokeWidth = 1.0..style = PaintingStyle.stroke;
    final path = Path();
    for (int i = 0; i < 15; i++) {
      double cx = Random(i).nextDouble() * size.width; double cy = Random(i+1).nextDouble() * size.height;
      for (int j = 0; j < 5; j++) { double a = (j * 45) * (pi / 180); path.moveTo(cx, cy); path.lineTo(cx + cos(a) * 30, cy + sin(a) * 30); }
    }
    canvas.drawPath(path, p);
  }
  @override bool shouldRepaint(CustomPainter old) => false;
}