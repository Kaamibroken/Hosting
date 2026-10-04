import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web; 

import 'auth/login_screen.dart'; 
import 'dashboard_screen.dart';

class ProjectDashboardScreen extends StatefulWidget {
  final String projectId;
  final String projectName;
  
  const ProjectDashboardScreen({Key? key, required this.projectId, required this.projectName}) : super(key: key);

  @override
  _ProjectDashboardScreenState createState() => _ProjectDashboardScreenState();
}

class _ProjectDashboardScreenState extends State<ProjectDashboardScreen> with TickerProviderStateMixin {
  String activeTab = "logs"; 
  bool isLoading = true;
  bool isFileOpening = false; 

  Map<String, dynamic> projectData = {
    "status": "Loading...", "uptime": "0m", "domain": null, "custom_domain": null, "plan_type": "free",
    "build_cmd": "", "start_cmd": "",
    "ram_used": 0, "ram_total": 1024, "storage_used": 0, "storage_total": 1024
  };

  List<String> logs = [];
  WebSocketChannel? _logsChannel;
  final ScrollController _logsScrollController = ScrollController(); 
  
  bool _isReconnecting = false;
  Timer? _reconnectTimer;

  List<Map<String, String>> envVars = [];
  bool isEnvLoading = false;

  List<Map<String, dynamic>> filesList = [];
  Set<String> selectedFiles = {};
  bool isFilesLoading = false;
  String currentPath = ""; 
  List<String> clipboardFiles = [];
  bool isCutAction = false;

  final TextEditingController _customDomainCtrl = TextEditingController();
  final TextEditingController _editDomainCtrl = TextEditingController();
  final TextEditingController _buildCmdCtrl = TextEditingController();
  final TextEditingController _startCmdCtrl = TextEditingController();
  bool isDomainLoading = false;
  bool isDnsVerified = false; 
  bool isVerifyingBackendDns = false;
  String dnsVerificationMsg = "Click view details to query edge.";

  Map<String, String?> dbUrls = {"mongodb": null, "redis": null, "postgres": null, "mysql": null};
  Map<String, bool> dbLoaders = {"mongodb": false, "redis": false, "postgres": false, "mysql": false};
  bool isDbTabLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchProjectData();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel(); 
    _logsChannel?.sink.close();
    _logsScrollController.dispose();
    _customDomainCtrl.dispose();
    _editDomainCtrl.dispose();
    _buildCmdCtrl.dispose();
    _startCmdCtrl.dispose();
    super.dispose();
  }
  
  Future<void> _fetchProjectData() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse('/api/project/${widget.projectId}/details'));
      if (res.statusCode == 200) {
        setState(() {
          projectData = jsonDecode(res.body);
          _buildCmdCtrl.text = projectData['build_cmd'] ?? "";
          _startCmdCtrl.text = projectData['start_cmd'] ?? "";
        });
        
        await _fetchHistoricalLogs();
        _connectWebSocket();
        
        _fetchEnv();
        _fetchFiles();
        _fetchVipDatabases(); 
        if (projectData['custom_domain'] != null) {
          _runBackendDnsVerification(projectData['custom_domain'], silent: true);
        }
      } else {
        PremiumToast.show(context, "Failed to load project", false);
        Future.delayed(const Duration(seconds: 1), () { if (mounted) Navigator.pop(context); });
      }
    } catch (e) {
      PremiumToast.show(context, "Network Error", false);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _fetchHistoricalLogs() async {
    try {
      final res = await http.get(Uri.parse('/api/projects/${widget.projectId}/logs'));
      if (res.statusCode == 200 && mounted) {
        final content = utf8.decode(res.bodyBytes);
        if (content.isNotEmpty) {
          setState(() {
            logs = content.split('\n').where((line) => line.trim().isNotEmpty).toList();
          });
          _scrollToBottomFiles();
        }
      }
    } catch (_) {}
  }

  void _connectWebSocket() {
    _reconnectTimer?.cancel();
    _logsChannel?.sink.close();
    
    final wsUrl = html.window.location.protocol == "https:" ? "wss" : "ws";
    final host = html.window.location.host;
    
    _logsChannel = WebSocketChannel.connect(Uri.parse('$wsUrl://$host/api/project/${widget.projectId}/live-stream'));
    
    _logsChannel!.stream.listen(
      (message) {
        if (mounted) {
          _isReconnecting = false; 
          try {
            final data = jsonDecode(message.toString());
            
            if (data['type'] == 'status_update') {
              setState(() { projectData['status'] = data['value'] ?? projectData['status']; });
              return;
            } 
            else if (data['type'] == 'log_update') {
              setState(() {
                logs.add(data['value'].toString());
                if (logs.length > 1000) logs.removeAt(0); 
              });
              _scrollToBottomFiles();
            }
          } catch (_) {
            setState(() {
              logs.add(message.toString());
              if (logs.length > 1000) logs.removeAt(0);
            });
            _scrollToBottomFiles();
          }
        }
      },
      onDone: () => _handleWebSocketDisconnect(),
      onError: (err) => _handleWebSocketDisconnect(),
      cancelOnError: true,
    );
  }

  void _handleWebSocketDisconnect() {
    if (!mounted || _isReconnecting) return;
    
    setState(() {
      _isReconnecting = true;
      logs.add("⚠️ [SYSTEM] Connection lost due to network shift. Attempting auto-reconnection...");
    });
    _scrollToBottomFiles();
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        _connectWebSocket();
      }
    });
  }

  void _scrollToBottomFiles() {
    Future.delayed(const Duration(milliseconds: 50), () {
      if (_logsScrollController.hasClients) {
        _logsScrollController.jumpTo(_logsScrollController.position.maxScrollExtent);
      }
    });
  }
  
  Future<void> _fetchVipDatabases() async {
    setState(() => isDbTabLoading = true);
    try {
      final res = await http.get(Uri.parse('/api/project/${widget.projectId}/databases'));
      if (res.statusCode == 200) {
        Map<String, dynamic> data = jsonDecode(res.body);
        setState(() {
          dbUrls["mongodb"] = data["mongodb"];
          dbUrls["redis"] = data["redis"];
          dbUrls["postgres"] = data["postgres"];
          dbUrls["mysql"] = data["mysql"];
        });
      }
    } catch (e) {
    } finally {
      if (mounted) setState(() => isDbTabLoading = false);
    }
  }

  Future<void> _executeDatabaseProvisioning(String type) async {
    setState(() => dbLoaders[type] = true);
    try {
      final res = await http.post(
        Uri.parse('/api/project/${widget.projectId}/database/create'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"type": type}),
      );
      if (res.statusCode == 200) {
        Map<String, dynamic> data = jsonDecode(res.body);
        setState(() { dbUrls[type] = data["url"]; });
        PremiumToast.show(context, "Database Connected!", true);
      } else {
        PremiumToast.show(context, "Database creation failed", false);
      }
    } catch (e) {
      PremiumToast.show(context, "Network Error", false);
    } finally {
      if (mounted) setState(() => dbLoaders[type] = false);
    }
  }

  Future<void> _executeDatabaseDeprovisioning(String type) async {
    setState(() => dbLoaders[type] = true);
    try {
      final res = await http.post(
        Uri.parse('/api/project/${widget.projectId}/database/delete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"type": type}),
      );
      if (res.statusCode == 200) {
        setState(() { dbUrls[type] = null; });
        PremiumToast.show(context, "Database Disconnected!", true);
      }
    } catch (e) {
    } finally {
      if (mounted) setState(() => dbLoaders[type] = false);
    }
  }

  Future<void> _handlePowerAction(String action) async {
    PremiumToast.show(context, "Executing command...", true);
    if (action == 'start' || action == 'redeploy') {
      setState(() {
        logs.clear();
        projectData['status'] = action == 'redeploy' ? 'Building' : 'Starting';
      });
    }
    try {
      final res = await http.post(Uri.parse('/api/project/${widget.projectId}/action'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'action': action}));
      if (res.statusCode != 200) {
        PremiumToast.show(context, "Action failed", false);
      }
    } catch (e) { PremiumToast.show(context, "Network Error", false); }
  }

  Future<void> _fetchEnv() async {
    setState(() => isEnvLoading = true);
    try {
      final res = await http.get(Uri.parse('/api/project/${widget.projectId}/env'));
      if (res.statusCode == 200) {
        Map<String, dynamic> data = jsonDecode(res.body);
        setState(() { envVars = data.entries.map((e) => {"key": e.key, "value": e.value.toString()}).toList(); });
      }
    } finally { 
      if (mounted) setState(() => isEnvLoading = false); 
    }
  }

  Future<void> _saveEnv() async {
    setState(() => isEnvLoading = true);
    Map<String, String> envData = {};
    for (var env in envVars) { if (env["key"]!.isNotEmpty) envData[env["key"]!] = env["value"]!; }
    try {
      final res = await http.post(Uri.parse('/api/project/${widget.projectId}/env'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(envData));
      PremiumToast.show(context, res.statusCode == 200 ? "Environment Saved!" : "Failed to save", res.statusCode == 200);
    } finally { 
      if (mounted) setState(() => isEnvLoading = false); 
    }
  }

  String _getFullPath(String filename) {
    return currentPath.isEmpty ? filename : "$currentPath/$filename";
  }

  Future<void> _fetchFiles() async {
    setState(() => isFilesLoading = true);
    try {
      final res = await http.get(Uri.parse('/api/project/${widget.projectId}/files?path=$currentPath'));
      if (res.statusCode == 200) {
        List<Map<String, dynamic>> fetched = List<Map<String, dynamic>>.from(jsonDecode(res.body));
        fetched.sort((a, b) {
          bool isAFolder = a['type'] == 'folder';
          bool isBFolder = b['type'] == 'folder';
          if (isAFolder && !isBFolder) return -1;
          if (!isAFolder && isBFolder) return 1;
          return a['name'].toString().compareTo(b['name'].toString());
        });
        setState(() => filesList = fetched);
      }
    } finally { 
      if (mounted) setState(() => isFilesLoading = false); 
    }
  }

  Future<void> _deleteSelectedFiles() async {
    if (selectedFiles.isEmpty) return;
    try {
      List<String> filesToDelete = selectedFiles.map((f) => _getFullPath(f)).toList();
      final res = await http.post(Uri.parse('/api/project/${widget.projectId}/files/delete'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({"files": filesToDelete}));
      if (res.statusCode == 200) { PremiumToast.show(context, "Files deleted", true); selectedFiles.clear(); _fetchFiles(); }
    } catch (e) {}
  }

  void _downloadSelectedFiles() {
    if (selectedFiles.isEmpty) return;
    String filesParam = selectedFiles.map((f) => _getFullPath(f)).join(',');
    html.window.open('/api/project/${widget.projectId}/files/download?files=$filesParam', '_blank');
    setState(() => selectedFiles.clear());
  }

  void _uploadFile() {
    final uploadInput = html.FileUploadInputElement(); uploadInput.multiple = true; uploadInput.click();
    uploadInput.onChange.listen((e) async {
      if (uploadInput.files != null && uploadInput.files!.isNotEmpty) {
        PremiumToast.show(context, "Uploading...", true);
        var request = http.MultipartRequest('POST', Uri.parse('/api/project/${widget.projectId}/files/upload?path=$currentPath'));
        for (var file in uploadInput.files!) {
          final readerObj = html.FileReader();
          readerObj.readAsArrayBuffer(file); 
          await readerObj.onLoadEnd.first;
          request.files.add(http.MultipartFile.fromBytes('files[]', readerObj.result as Uint8List, filename: file.name));
        }
        var res = await request.send();
        if (res.statusCode == 200) { PremiumToast.show(context, "Upload complete!", true); _fetchFiles(); }
      }
    });
  }

  Future<void> _extractZip(String filename) async {
    PremiumToast.show(context, "Extracting...", true);
    try {
      final res = await http.post(Uri.parse('/api/project/${widget.projectId}/files/extract'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({"filename": _getFullPath(filename)}));
      if (res.statusCode == 200) { PremiumToast.show(context, "Extracted successfully!", true); _fetchFiles(); }
    } catch (e) {}
  }

  Future<void> _pasteFile() async {
    if (clipboardFiles.isEmpty) return;
    PremiumToast.show(context, "Pasting...", true);
    try {
      final res = await http.post(Uri.parse('/api/project/${widget.projectId}/files/copymove'), 
        headers: {'Content-Type': 'application/json'}, 
        body: jsonEncode({"source_paths": clipboardFiles, "dest_path": currentPath, "action": isCutAction ? "move" : "copy"})
      );
      if (res.statusCode == 200) {
        PremiumToast.show(context, "Pasted successfully!", true);
        setState(() { clipboardFiles.clear(); });
        _fetchFiles();
      }
    } catch (e) {}
  }

  void _showCreateFileDialog(String type) {
    TextEditingController ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF082236), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF45F3FF))),
        title: Text("Create $type", style: const TextStyle(color: Color(0xFF45F3FF))),
        content: TextField(controller: ctrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: "Name...", filled: true, fillColor: Colors.white.withOpacity(0.05))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
          ElevatedButton(onPressed: () async {
            Navigator.pop(context);
            await http.post(Uri.parse('/api/project/${widget.projectId}/files/create'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({"name": _getFullPath(ctrl.text), "type": type}));
            _fetchFiles();
          }, child: const Text("CREATE")),
        ],
      ),
    );
  }

  void _showRenameDialog(String oldName) {
    TextEditingController ctrl = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF082236), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.amber)),
        title: const Text("Rename", style: TextStyle(color: Colors.amber)),
        content: TextField(controller: ctrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(filled: true, fillColor: Colors.white.withOpacity(0.05))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          ElevatedButton(onPressed: () async {
            Navigator.pop(context);
            await http.post(Uri.parse('/api/project/${widget.projectId}/files/rename'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({"old_name": _getFullPath(oldName), "new_name": _getFullPath(ctrl.text)}));
            _fetchFiles();
          }, child: const Text("RENAME")),
        ],
      ),
    );
  }

  Future<void> _manageDomain(String action, {String? domain}) async {
    setState(() => isDomainLoading = true);
    try {
      final res = await http.post(
        Uri.parse('/api/project/${widget.projectId}/domain'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"action": action, "domain": domain}),
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        PremiumToast.show(context, data['message'], data['status'] == 'success');
        if (action == 'custom' && data['status'] == 'success') {
          _customDomainCtrl.clear();
          if (domain != null) _showWideDnsGuidePopup(domain);
        }
        _fetchProjectData();
      } else { PremiumToast.show(context, data['message'], false); }
    } finally { 
      if (mounted) setState(() => isDomainLoading = false); 
    }
  }

  Future<void> _runBackendDnsVerification(String domain, {bool silent = false}) async {
    if (!silent) {
      setState(() {
        isVerifyingBackendDns = true;
        dnsVerificationMsg = "Syncing edge network layers...";
      });
    }
    try {
      final res = await http.post(
        Uri.parse('/api/project/${widget.projectId}/domain'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"action": "verify", "domain": domain}),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          if (data['verified'] == true) {
            isDnsVerified = true;
            dnsVerificationMsg = "Verified & Secured with SSL!";
          } else {
            isDnsVerified = false;
            dnsVerificationMsg = "Propagation incomplete. Please verify settings.";
          }
        });
        if (!silent) PremiumToast.show(context, data['message'], data['verified'] == true);
      }
    } catch (e) {
      if (!silent) setState(() { dnsVerificationMsg = "Handshake Error."; });
    } finally {
      if (mounted) setState(() => isVerifyingBackendDns = false);
    }
  }

  void _showAddCustomDomainDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF082236),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF45F3FF))),
        title: const Text("Add Custom Domain", style: TextStyle(color: Color(0xFF45F3FF), fontWeight: FontWeight.bold)),
        content: TextField(
          controller: _customDomainCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "domain.com or sub.domain.site",
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF45F3FF).withOpacity(0.2)),
            onPressed: () {
              Navigator.pop(context);
              if (_customDomainCtrl.text.trim().isNotEmpty) {
                _manageDomain('custom', domain: _customDomainCtrl.text.trim());
              }
            },
            child: const Text("ADD DOMAIN", style: TextStyle(color: Color(0xFF45F3FF)))
          ),
        ],
      ),
    );
  }

  void _showWideDnsGuidePopup(String domain) {
    List<String> parts = domain.split('.');
    String dnsHost = parts.length > 2 ? parts.sublist(0, parts.length - 2).join('.') : "@";
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF082236),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: const Color(0xFF45F3FF).withOpacity(0.3))),
          title: Row(
            children: [
              const Icon(Icons.dns_rounded, color: Color(0xFF45F3FF)),
              const SizedBox(width: 10),
              const Text("DNS Configuration", style: TextStyle(color: Color(0xFF45F3FF), fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Map this single record inside your DNS platform panel. Records are stacked in two lines to avoid text breaking out.", style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black26, 
                    borderRadius: BorderRadius.circular(12), 
                    border: Border.all(color: Colors.white10)
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _twoLineDnsRow("RECORD TYPE", "CNAME", Colors.amber, isCopyable: false),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(color: Colors.white10, height: 1)),
                      _twoLineDnsRow("HOST / NAME", dnsHost, Colors.white, isCopyable: true),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(color: Colors.white10, height: 1)),
                      _twoLineDnsRow("VALUE / TARGET", "connect.silenthost.site", Colors.greenAccent, isCopyable: true),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE", style: TextStyle(color: Colors.white54)))],
        );
      }
    );
  }

  Widget _twoLineDnsRow(String title, String value, Color valueColor, {required bool isCopyable}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                value, 
                style: TextStyle(color: valueColor, fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isCopyable) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: value));
                  PremiumToast.show(context, "Copied", true);
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Icon(Icons.copy_all_rounded, color: Colors.blueAccent, size: 16),
                ),
              )
            ]
          ],
        )
      ],
    );
  }

  Widget _buildDnsVerificationStatusBar(String domain) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 4),
      child: Row(
        children: [
          const Text("Your Domain Status: ", style: TextStyle(color: Colors.white54, fontSize: 12)),
          if (isVerifyingBackendDns) ...[
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: Color(0xFF45F3FF), strokeWidth: 1.5)),
            const SizedBox(width: 6),
          ],
          Text(
            isDnsVerified ? "Verified" : "Pending",
            style: TextStyle(color: isDnsVerified ? Colors.greenAccent : Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          if (!isDnsVerified) ...[
            const SizedBox(width: 12),
            InkWell(
              onTap: () {
                _showWideDnsGuidePopup(domain);
                _runBackendDnsVerification(domain);
              },
              child: const Text(
                "View Details",
                style: TextStyle(color: Color(0xFF45F3FF), fontSize: 12, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
              ),
            ),
          ]
        ],
      ),
    );
  }

  void _showEditDomainDialog(String currentDomainStr, String actionType) {
    String subdomain = currentDomainStr;
    String lockedSuffix = "";

    if (currentDomainStr.endsWith(".silenthost.pro")) {
      lockedSuffix = ".silenthost.pro";
      subdomain = currentDomainStr.substring(0, currentDomainStr.indexOf(".silenthost.pro"));
    } else {
      int lastDot = currentDomainStr.lastIndexOf('.');
      if (lastDot != -1) {
        int secondLastDot = currentDomainStr.lastIndexOf('.', lastDot - 1);
        if (secondLastDot != -1) {
          subdomain = currentDomainStr.substring(0, secondLastDot);
          lockedSuffix = currentDomainStr.substring(secondLastDot);
        } else {
          subdomain = currentDomainStr.substring(0, lastDot);
          lockedSuffix = currentDomainStr.substring(lastDot);
        }
      }
    }

    _editDomainCtrl.text = subdomain;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF082236), 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: const Color(0xFF45F3FF).withOpacity(0.3))),
        title: const Text("Edit Subdomain", style: TextStyle(color: Color(0xFF45F3FF))),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _editDomainCtrl, 
                style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 14), 
                decoration: InputDecoration(
                  hintText: "subdomain",
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true, 
                  fillColor: Colors.white.withOpacity(0.05), 
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                )
              ),
            ),
            if (lockedSuffix.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Text(lockedSuffix, style: const TextStyle(color: Colors.white54, fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF45F3FF).withOpacity(0.2)), 
            onPressed: () { 
              Navigator.pop(context); 
              String finalDomain = _editDomainCtrl.text.trim() + lockedSuffix;
              _manageDomain(actionType, domain: finalDomain); 
            }, 
            child: const Text("UPDATE", style: TextStyle(color: Color(0xFF45F3FF)))
          ),
        ],
      ),
    );
  }

  Future<void> _updateCommands() async {
    PremiumToast.show(context, "Updating Config...", true);
    try {
      final res = await http.post(Uri.parse('/api/project/${widget.projectId}/commands'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({"build_cmd": _buildCmdCtrl.text, "start_cmd": _startCmdCtrl.text}));
      if (res.statusCode == 200) {
        _handlePowerAction('redeploy');
      }
    } catch (e) {
      PremiumToast.show(context, "Failed to update", false);
    }
  }

  String _determineAceAceMode(String filename) {
    String ext = filename.split('.').last.toLowerCase();
    if (ext == 'py') return 'python';
    if (ext == 'rs') return 'rust';
    if (ext == 'go') return 'golang';
    if (ext == 'js' || ext == 'json') return 'javascript';
    if (ext == 'sh') return 'bash';
    if (ext == 'html') return 'html';
    if (ext == 'css') return 'css';
    if (ext.contains('dockerfile')) return 'dockerfile';
    return 'text';
  }

  Future<void> _openVipPopupEditor(String filename) async {
    setState(() => isFileOpening = true);
    String fullPath = _getFullPath(filename);
    try {
      final res = await http.get(Uri.parse('/api/project/${widget.projectId}/files/read?file=$fullPath'));
      if (res.statusCode != 200) {
        PremiumToast.show(context, "Failed to pull source tree", false);
        setState(() => isFileOpening = false);
        return;
      }
      String initialContent = utf8.decode(res.bodyBytes);
      
      if (initialContent.startsWith("PK")) {
        int centralDirIdx = initialContent.indexOf("PK\u0001\u0002");
        if (centralDirIdx == -1) centralDirIdx = initialContent.lastIndexOf("PK");
        
        int nameIdx = initialContent.indexOf(filename);
        int startIdx = 0;
        if (nameIdx != -1 && nameIdx < 150) {
          startIdx = nameIdx + filename.length;
        } else {
          int braceIdx = initialContent.indexOf('{');
          if (braceIdx != -1 && braceIdx < 150) startIdx = braceIdx;
        }
        
        if (startIdx > 0 && centralDirIdx > startIdx) {
          String extracted = initialContent.substring(startIdx, centralDirIdx);
          
          int firstCleanChar = 0;
          for (int i = 0; i < extracted.length; i++) {
            int charCode = extracted.codeUnitAt(i);
            if ((charCode >= 32 && charCode <= 126) || charCode == 10 || charCode == 13 || charCode == 9) {
              firstCleanChar = i;
              break;
            }
          }
          initialContent = extracted.substring(firstCleanChar).trim();
        }
      }

      String aceMode = _determineAceAceMode(filename);
      String viewId = "ace_editor_frame_${DateTime.now().millisecondsSinceEpoch}";
      final html.IFrameElement iframe = html.IFrameElement()
        ..src = "/editor.html"
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';

      ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewId) => iframe);
      iframe.onLoad.listen((_) {
        Timer(const Duration(milliseconds: 200), () {
          iframe.contentWindow?.postMessage({
            'action': 'load',
            'code': initialContent,
            'mode': aceMode
          }, '*');
        });
      });

      setState(() => isFileOpening = false); 
      if (!mounted) return;
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, anim1, anim2) {
          return _VipEditorOverlayLayout(
            projectId: widget.projectId,
            fullPath: fullPath,
            filename: filename,
            viewId: viewId,
            initialCode: initialContent,
            aceMode: aceMode,
            onCloseRequested: () => Navigator.pop(context),
            iframe: iframe,
            onSaveSuccess: () {
              _fetchFiles(); 
            },
          );
        },
      );
    } catch (e) {
      setState(() => isFileOpening = false);
      PremiumToast.show(context, "Handshake Error initialization overlay", false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool hasNoPlan = !isLoading && (projectData['plan_type'] == 'none' || projectData['plan_type'] == null || projectData['plan_type'] == '');
    if (hasNoPlan) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A10),
        body: Stack(
          children: [
            Container(decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0xFF0F3B57), Color(0xFF082236), Color(0xFF020E18)], radius: 1.5))),
            const Positioned.fill(child: LiveCyberBackgroundP()),
            Center(
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
                decoration: BoxDecoration(
                  color: Colors.black26, 
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.3), width: 1.5),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 30)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 60),
                    const SizedBox(height: 20),
                    const Text(
                      "PLAN EXPIRED",
                      style: TextStyle(color: Colors.redAccent, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      "Your hosting plan has expired, or the system could not locate an active subscription. To restore access to the Infrastructure Manager, please reactivate your subscription.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF45F3FF).withOpacity(0.2),
                        side: const BorderSide(color: Color(0xFF45F3FF)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(context); 
                        PremiumToast.show(context, "Please Again Active Plan", true);
                      },
                      icon: const Icon(Icons.add_card_rounded, color: Color(0xFF45F3FF)),
                      label: const Text("REACTIVATE PLAN", style: TextStyle(color: Color(0xFF45F3FF), fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    String currentStatus = projectData['status'] ?? "Offline";
    Color sColor = currentStatus == 'Online' ? Colors.greenAccent : (currentStatus == 'Crashed' || currentStatus == 'Offline') ? Colors.redAccent : Colors.amber;
    bool isRunning = currentStatus == 'Online' || currentStatus == 'Building' || currentStatus == 'Starting';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A10),
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0xFF0F3B57), Color(0xFF082236), Color(0xFF020E18)], radius: 1.5))),
          const Positioned.fill(child: LiveCyberBackgroundP()),
          SafeArea(
            child: Column(
              children: [
                // 🌟 فکس: 'sColor' اب بریکٹ سیکیورٹی کے تحت پوزیشن 1 پر لاک ہے
                _buildHeader(sColor, isRunning, currentStatus),
                _buildTabs(),
                Expanded(child: isLoading ? const Center(child: CircularProgressIndicator(color: Color(0xFF45F3FF))) : _buildActiveTabContent()),
              ],
            ),
          ),
          if (isFileOpening)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF45F3FF)),
                    const SizedBox(height: 15),
                    Text("Opening file...", style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: activeTab == 'files' 
        ? (clipboardFiles.isEmpty 
            ? FloatingActionButton(
                heroTag: "fab_add_file",
                backgroundColor: const Color(0xFF45F3FF),
                child: const Icon(Icons.add, color: Colors.black),
                onPressed: () {
                  showModalBottomSheet(context: context, backgroundColor: const Color(0xFF082236), builder: (c) => Wrap(children: [
                    ListTile(leading: const Icon(Icons.upload, color: Colors.greenAccent), title: const Text("Upload File/Zip", style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(c); _uploadFile(); }),
                    ListTile(leading: const Icon(Icons.insert_drive_file, color: Colors.blueAccent), title: const Text("Create File", style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(c); _showCreateFileDialog('file'); }),
                    ListTile(leading: const Icon(Icons.folder, color: Colors.amber), title: const Text("Create Folder", style: TextStyle(color: Colors.white)), onTap: () { Navigator.pop(c); _showCreateFileDialog('folder'); }),
                  ]));
                },
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: "fab_paste_file",
                    backgroundColor: Colors.greenAccent,
                    child: const Icon(Icons.content_paste_rounded, color: Colors.black),
                    onPressed: () async {
                      await _pasteFile();
                    },
                    tooltip: "Paste Here",
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton(
                    heroTag: "fab_cancel_clipboard",
                    backgroundColor: Colors.redAccent,
                    child: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () {
                      setState(() { clipboardFiles.clear(); });
                      PremiumToast.show(context, "Action cancelled", false);
                    },
                    tooltip: "Cancel",
                  ),
                ],
              ))
        : null,
    );
  }

  // 🌟 فکس: 'Color statusColor' کو پیرامیٹر کی جگہ فرسٹ پوزیشن پر لاک کر دیا ہے
  Widget _buildHeader(Color statusColor, bool isRunning, String status) {
    return Container(
      padding: const EdgeInsets.all(20), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF45F3FF)), onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const DashboardScreen()))),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.projectName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  const SizedBox(height: 5),
                  Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor, boxShadow: [BoxShadow(color: statusColor, blurRadius: 5)])), const SizedBox(width: 8), Text(status, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold))]),
                ],
              ),
            ],
          ),
          Theme(
            data: Theme.of(context).copyWith(popupMenuTheme: PopupMenuThemeData(color: const Color(0xFF082236).withOpacity(0.95), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: const Color(0xFF45F3FF).withOpacity(0.4), width: 1.5)))),
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white, size: 28),
              itemBuilder: (context) => [
                PopupMenuItem(value: isRunning ? 'stop' : 'start', child: Row(children: [Icon(isRunning ? Icons.stop_circle : Icons.play_circle_fill, color: isRunning ? Colors.amber : Colors.greenAccent), const SizedBox(width: 10), Text(isRunning ? "Stop Server" : "Start Server", style: const TextStyle(color: Colors.white))])),
                PopupMenuItem(value: 'redeploy', child: Row(children: const [Icon(Icons.refresh, color: Colors.blueAccent), SizedBox(width: 10), Text("Re-Deploy", style: TextStyle(color: Colors.white))])),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'delete', child: Row(children: const [Icon(Icons.delete, color: Colors.redAccent), SizedBox(width: 10), Text("Delete Project", style: TextStyle(color: Colors.redAccent))])),
              ],
              onSelected: (val) {
                if (val == 'delete') {
                  _handlePowerAction('delete');
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const DashboardScreen()));
                } else {
                  _handlePowerAction(val);
                }
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 15), padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
      child: Row(children: [
        Expanded(child: _tabBtn("LOGS", Icons.terminal, "logs")),
        Expanded(child: _tabBtn("DB", Icons.storage_rounded, "databases")), 
        Expanded(child: _tabBtn("ENV", Icons.vpn_key, "env")),
        Expanded(child: _tabBtn("FILES", Icons.folder, "files")),
        Expanded(child: _tabBtn("SETTINGS", Icons.settings, "settings"))
      ]),
    );
  }

  Widget _tabBtn(String title, IconData icon, String val) {
    bool active = activeTab == val;
    return GestureDetector(
      onTap: () => setState(() { activeTab = val; selectedFiles.clear(); }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: active ? const Color(0xFF45F3FF).withOpacity(0.2) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Column(children: [Icon(icon, size: 18, color: active ? const Color(0xFF45F3FF) : Colors.white38), const SizedBox(height: 5), Text(title, style: TextStyle(color: active ? const Color(0xFF45F3FF) : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1))]),
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (activeTab) {
      case "logs": return _buildLogsTab();
      case "databases": return _buildDatabasesTab(); 
      case "env": return _buildEnvTab();
      case "files": return _buildFilesTab();
      case "settings": return _buildSettingsTab();
      default: return const SizedBox();
    }
  }

  Widget _buildLogsTab() {
    return Container(
      margin: const EdgeInsets.all(20), padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 35),
            child: ListView.builder(
              controller: _logsScrollController, itemCount: logs.length,
              itemBuilder: (c, i) => Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(logs[i], style: const TextStyle(color: Colors.white70, fontFamily: 'monospace', fontSize: 12))),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy_rounded, color: Color(0xFF45F3FF), size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    if (logs.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: logs.join('\n')));
                      PremiumToast.show(context, "Logs Copied!", true);
                    } else {
                      PremiumToast.show(context, "No logs to copy", false);
                    }
                  },
                  tooltip: "Copy Logs",
                ),
                const SizedBox(height: 12),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white60, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    if (_logsScrollController.hasClients) {
                      _logsScrollController.jumpTo(0);
                    }
                  },
                  tooltip: "Scroll to Top",
                ),
                const SizedBox(height: 8),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white60, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    if (_logsScrollController.hasClients) {
                      _logsScrollController.jumpTo(_logsScrollController.position.maxScrollExtent);
                    }
                  },
                  tooltip: "Scroll to Bottom",
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatabasesTab() {
    return isDbTabLoading 
      ? const Center(child: CircularProgressIndicator(color: Color(0xFF45F3FF))) 
      : ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildVipDbRow("MongoDB", "mongodb", const Color(0xFF34D399)),
            const SizedBox(height: 15),
            _buildVipDbRow("Redis Cache", "redis", const Color(0xFFF87171)),
            const SizedBox(height: 15),
            _buildVipDbRow("PostgreSQL", "postgres", const Color(0xFF60A5FF)),
            const SizedBox(height: 15),
            _buildVipDbRow("MySQL", "mysql", Colors.amber),
          ],
        );
  }

  Widget _buildVipDbRow(String displayName, String key, Color brandColor) {
    String? currentUrl = dbUrls[key];
    bool isWorking = dbLoaders[key] ?? false;
    String envName = "";
    if (key == "mongodb") envName = "MONGO_URL";
    if (key == "redis") envName = "REDIS_URL";
    if (key == "postgres") envName = "POSTGRES_URL";
    if (key == "mysql") envName = "MYSQL_URL";

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF45F3FF).withOpacity(0.02),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: currentUrl != null ? Colors.greenAccent.withOpacity(0.3) : Colors.white10),
      ),
        child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName, style: TextStyle(color: brandColor, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                const Text("Add in your script:", style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace')),
                const SizedBox(height: 4),
                Text(envName, style: TextStyle(color: brandColor, fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 15),
          if (isWorking)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: brandColor.withOpacity(0.05),
                side: BorderSide(color: brandColor.withOpacity(0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: null, 
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: brandColor, strokeWidth: 1.5)),
                  const SizedBox(width: 8),
                  Text("CONNECTING...", style: TextStyle(color: brandColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          // 🌟 فکس: پُرانے الیگل اف-ایلس اسٹرکچر کو ہٹا کر کلین 'else if' نیسٹنگ کر دی ہے
          else if (currentUrl == null)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: brandColor.withOpacity(0.15),
                side: BorderSide(color: brandColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () => _executeDatabaseProvisioning(key),
              child: Text("CONNECT", style: TextStyle(color: brandColor, fontSize: 11, fontWeight: FontWeight.bold)),
            )
          else
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.1),
                    border: Border.all(color: Colors.greenAccent.withOpacity(0.7)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text("CONNECTED", style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 20),
                  onPressed: () => _executeDatabaseDeprovisioning(key),
                  tooltip: "Disconnect Database",
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                ),
              ],
            )
        ],
      ),
    );
  }

  Widget _buildEnvTab() {
    return isEnvLoading ? const Center(child: CircularProgressIndicator(color: Color(0xFF45F3FF))) : ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("ENVIRONMENT VARIABLES", style: TextStyle(color: Colors.white54, letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 12)), TextButton.icon(onPressed: () => setState(() => envVars.add({"key": "", "value": ""})), icon: const Icon(Icons.add, color: Color(0xFF45F3FF)), label: const Text("ADD NEW", style: TextStyle(color: Color(0xFF45F3FF), fontWeight: FontWeight.bold)))]),
        const SizedBox(height: 15),
        ...List.generate(envVars.length, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: Row(
              children: [
                Expanded(child: _envInput("KEY", envVars[i]["key"]!, (v) => envVars[i]["key"] = v)),
                const SizedBox(width: 10), const Text("=", style: TextStyle(color: Colors.white54, fontSize: 20)), const SizedBox(width: 10),
                Expanded(flex: 2, child: _envInput("VALUE", envVars[i]["value"]!, (v) => envVars[i]["value"] = v)),
                IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => setState(() => envVars.removeAt(i))),
              ],
            ),
          );
        }),
        const SizedBox(height: 20),
        Center(child: CompactShatteredButtonP(text: "SAVE VARIABLES", onPressed: _saveEnv)),
      ],
    );
  }

  Widget _envInput(String hint, String val, Function(String) onChanged) {
    return TextFormField(
      initialValue: val, 
      onChanged: onChanged, 
      style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13), 
      decoration: InputDecoration(
        hintText: hint, 
        hintStyle: const TextStyle(color: Colors.white24), 
        filled: true, 
        fillColor: Colors.white.withOpacity(0.05), 
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none), 
        contentPadding: const EdgeInsets.all(15)
      )
    );
  }

  Widget _buildFilesTab() {
    bool isSelectionMode = selectedFiles.isNotEmpty;
    // 🌟 فکس: پُرانے 'Expanded' اور بریکٹ لاجک لیکیج کو ہٹا کر کلین کالم اسٹرکچر فٹ کر دیا ہے
    return isFilesLoading ? const Center(child: CircularProgressIndicator(color: Color(0xFF45F3FF))) : Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isSelectionMode) ...[
                Text("${selectedFiles.length} Selected", style: const TextStyle(color: Color(0xFF45F3FF), fontWeight: FontWeight.bold)),
                Row(children: [
                  IconButton(icon: const Icon(Icons.copy, color: Colors.blueAccent), onPressed: () { setState(() { clipboardFiles = selectedFiles.map((f) => _getFullPath(f)).toList(); isCutAction = false; selectedFiles.clear(); }); PremiumToast.show(context, "Copied to clipboard", true); }),
                  IconButton(icon: const Icon(Icons.content_cut, color: Colors.amber), onPressed: () { setState(() { clipboardFiles = selectedFiles.map((f) => _getFullPath(f)).toList(); isCutAction = true; selectedFiles.clear(); }); PremiumToast.show(context, "Cut to clipboard", true); }),
                  IconButton(icon: const Icon(Icons.download, color: Colors.greenAccent), onPressed: _downloadSelectedFiles),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: _deleteSelectedFiles),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => setState(() => selectedFiles.clear())),
                ])
              ] else ...[
                Row(
                  children: [
                    if (currentPath.isNotEmpty) IconButton(icon: const Icon(Icons.arrow_upward, color: Colors.amber, size: 20), onPressed: () {
                      List<String> parts = currentPath.split('/'); parts.removeLast();
                      setState(() { currentPath = parts.join('/'); selectedFiles.clear(); }); 
                      _fetchFiles();
                    }),
                    Text("/root/app${currentPath.isNotEmpty ? '/$currentPath' : ''}", style: const TextStyle(color: Colors.white54, fontFamily: 'monospace', fontSize: 12)),
                  ],
                ),
              ]
            ],
          ),
        ),
        Expanded(
          child: filesList.isEmpty ? const Center(child: Text("Folder is empty", style: TextStyle(color: Colors.white38))) : ListView.builder(
            padding: const EdgeInsets.all(10), 
            itemCount: filesList.length,
            itemBuilder: (c, i) {
              var f = filesList[i]; String name = f['name']; bool isSelected = selectedFiles.contains(name);
              bool isFolder = f['type'] == 'folder';
              IconData fIcon = isFolder ? Icons.folder : name.endsWith('.zip') ? Icons.folder_zip : Icons.insert_drive_file;
              Color fColor = isFolder ? Colors.amber : name.endsWith('.zip') ? Colors.redAccent : Colors.blueAccent;

              return ListTile(
                onTap: () {
                  if (isSelectionMode) { setState(() { isSelected ? selectedFiles.remove(name) : selectedFiles.add(name); }); } 
                  else { 
                    if (isFolder) { setState(() { currentPath = currentPath.isEmpty ? name : "$currentPath/$name"; }); _fetchFiles(); }
                    else if (!name.endsWith('.zip')) { 
                      _openVipPopupEditor(name);
                    }
                  }
                },
                onLongPress: () => setState(() => selectedFiles.add(name)),
                leading: Icon(fIcon, color: fColor, size: 28),
                title: Text(name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(f['size'] ?? '--', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                trailing: isSelectionMode ? Icon(isSelected ? Icons.check_circle : Icons.circle_outlined, color: isSelected ? const Color(0xFF45F3FF) : Colors.white24) : _buildFileItemMenu(f),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFileItemMenu(Map<String, dynamic> f) {
    bool isZip = f['name'].toString().endsWith('.zip');
    bool isFolder = f['type'] == 'folder';
    return Theme(
      data: Theme.of(context).copyWith(popupMenuTheme: PopupMenuThemeData(color: const Color(0xFF082236).withOpacity(0.95), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: const Color(0xFF45F3FF).withOpacity(0.4))))),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.white38),
        itemBuilder: (context) => [
          if (!isFolder && !isZip) PopupMenuItem(value: 'edit', child: Row(children: const [Icon(Icons.edit_document, color: Colors.blueAccent, size: 18), SizedBox(width: 10), Text("Edit File", style: TextStyle(color: Colors.white))])),
          PopupMenuItem(value: 'rename', child: Row(children: const [Icon(Icons.edit, color: Colors.white54, size: 18), SizedBox(width: 10), Text("Rename", style: TextStyle(color: Colors.white))])),
          if (!isFolder) PopupMenuItem(value: 'download', child: Row(children: const [Icon(Icons.download, color: Colors.greenAccent, size: 18), SizedBox(width: 10), Text("Download", style: TextStyle(color: Colors.white))])),
          PopupMenuItem(value: 'copy', child: Row(children: const [Icon(Icons.copy, color: Colors.white54, size: 18), SizedBox(width: 10), Text("Copy", style: TextStyle(color: Colors.white))])),
          PopupMenuItem(value: 'cut', child: Row(children: const [Icon(Icons.content_cut, color: Colors.white54, size: 18), SizedBox(width: 10), Text("Cut", style: TextStyle(color: Colors.white))])),
          if (isZip) PopupMenuItem(value: 'extract', child: Row(children: const [Icon(Icons.unarchive, color: Colors.amber, size: 18), SizedBox(width: 10), Text("Extract Here", style: TextStyle(color: Colors.amber))])),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'delete', child: Row(children: const [Icon(Icons.delete, color: Colors.redAccent, size: 18), SizedBox(width: 10), Text("Delete", style: TextStyle(color: Colors.redAccent))])),
        ],
        onSelected: (v) {
          if (v == 'edit') { _openVipPopupEditor(f['name']); }
          else if (v == 'rename') _showRenameDialog(f['name']);
          else if (v == 'extract') _extractZip(f['name']);
          else if (v == 'download') { html.window.open('/api/project/${widget.projectId}/files/download?files=${_getFullPath(f['name'])}', '_blank'); }
          else if (v == 'copy') { setState(() { clipboardFiles = [_getFullPath(f['name'])]; isCutAction = false; }); PremiumToast.show(context, "Copied to clipboard", true); }
          else if (v == 'cut') { setState(() { clipboardFiles = [_getFullPath(f['name'])]; isCutAction = true; }); PremiumToast.show(context, "Cut to clipboard", true); }
          else if (v == 'delete') { setState(() => selectedFiles.add(f['name'])); _deleteSelectedFiles(); }
        },
      ),
    );
  }

  Widget _buildSettingsTab() {
    bool hasGenDomain = projectData['domain'] != null && projectData['domain'].toString().isNotEmpty;
    bool hasCustomDomain = projectData['custom_domain'] != null && projectData['custom_domain'].toString().isNotEmpty;
    bool isPro = projectData['plan_type'] == 'pro';

    return isDomainLoading ? const Center(child: CircularProgressIndicator(color: Color(0xFF45F3FF))) : ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text("RESOURCE USAGE", style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        _buildSettingsCard(Column(
          children: [
            _buildResourceBar("RAM USAGE", projectData['ram_used'], projectData['ram_total'], "MB", const Color(0xFFA855F7)),
            const SizedBox(height: 25),
            _buildResourceBar("NVMe STORAGE", projectData['storage_used'], projectData['storage_total'], "MB", Colors.amber),
          ],
        )),
        const SizedBox(height: 30),
        const Text("DOMAIN MANAGEMENT", style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        _buildSettingsCard(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasGenDomain) 
              _buildReadOnlyDomainBox("GENERATED DOMAIN", projectData['domain'], 'generate')
            else 
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF45F3FF).withOpacity(0.1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10)), 
                onPressed: () => _manageDomain('generate'), icon: const Icon(Icons.auto_awesome, color: Color(0xFF45F3FF), size: 18), 
                label: const Text("Generate Free Domain", style: TextStyle(color: Color(0xFF45F3FF), fontSize: 12))
              ),
            const SizedBox(height: 25),
            const Divider(color: Colors.white10),
            const SizedBox(height: 15),
            if (hasCustomDomain) ...[
              _buildReadOnlyDomainBox("CUSTOM DOMAIN", projectData['custom_domain'], 'custom'),
              _buildDnsVerificationStatusBar(projectData['custom_domain']),
            ] else ...[
              const Text("CUSTOM DOMAIN NETWORK", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPro ? const Color(0xFF45F3FF).withOpacity(0.1) : Colors.white.withOpacity(0.03), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), 
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                  side: isPro ? null : const BorderSide(color: Colors.white10, width: 0.8),
                ), 
                onPressed: isPro ? _showAddCustomDomainDialog : () { PremiumToast.show(context, "Upgrade to Pro Plan to unlock custom domains!", false); }, 
                icon: Icon(isPro ? Icons.add_link_rounded : Icons.lock_rounded, color: isPro ? const Color(0xFF45F3FF) : Colors.white24, size: 18), 
                label: Text("Add Custom Domain", style: TextStyle(color: isPro ? const Color(0xFF45F3FF) : Colors.white24, fontSize: 12, fontWeight: FontWeight.bold))
              ),
              if (!isPro) ...[
                const SizedBox(height: 8),
                const Padding(padding: EdgeInsets.only(left: 4), child: Text("Only for Pro Users", style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5))),
              ]
            ],
          ],
        )),
        const SizedBox(height: 30),
        const Text("ADVANCED SETTINGS", style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        _buildSettingsCard(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Build Command", style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(controller: _buildCmdCtrl, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13), decoration: InputDecoration(filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none))),
            const SizedBox(height: 15),
            const Text("Start Command", style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(controller: _startCmdCtrl, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13), decoration: InputDecoration(filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none))),
            const SizedBox(height: 20),
            Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF45F3FF).withOpacity(0.2)),
                onPressed: _updateCommands,
                icon: const Icon(Icons.rocket_launch, color: Color(0xFF45F3FF)), label: const Text("UPDATE & RE-DEPLOY", style: TextStyle(color: Color(0xFF45F3FF)))
              ),
            )
          ],
        )),
        const SizedBox(height: 40),
        const Text("DANGER ZONE", style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 3, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        _buildSettingsCard(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Permanently destroy this project, its database, and all files. This action is irreversible.", style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5)),
            const SizedBox(height: 15),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.1), side: const BorderSide(color: Colors.redAccent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () { _handlePowerAction('delete'); Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const DashboardScreen())); },
              child: const Text("DESTROY PROJECT", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1)),
            )
          ],
        )),
        const SizedBox(height: 50),
      ],
    );
  }

  Widget _buildReadOnlyDomainBox(String title, String domainStr, String actionType) {
    String deleteActionName = actionType == 'generate' ? 'delete_generated' : 'delete_custom';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => html.window.open("https://$domainStr", '_blank'),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text(domainStr, style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                ),
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _domainActionBtn(Icons.copy_rounded, Colors.white70, () {
                    Clipboard.setData(ClipboardData(text: "https://$domainStr"));
                    PremiumToast.show(context, "Copied!", true);
                  }),
                  const SizedBox(width: 10),
                  _domainActionBtn(Icons.edit_rounded, Colors.blueAccent, () => _showEditDomainDialog(domainStr, actionType)),
                  const SizedBox(width: 10),
                  _domainActionBtn(Icons.delete_rounded, Colors.redAccent, () => _manageDomain(deleteActionName)),
                ],
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _domainActionBtn(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.08), border: Border.all(color: color.withOpacity(0.3)), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }

  Widget _buildSettingsCard(Widget child) {
    return Container(padding: const EdgeInsets.all(25), decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.02), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)), child: child);
  }

  Widget _buildResourceBar(String title, num used, num total, String unit, Color color) {
    double percentage = total > 0 ? (used / total) : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)), Text("$used / $total $unit", style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'))]),
        const SizedBox(height: 8),
        Stack(children: [Container(height: 10, width: double.infinity, decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(5))), AnimatedContainer(duration: const Duration(seconds: 1), height: 10, width: MediaQuery.of(context).size.width * 0.8 * percentage, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5), boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 10)]))])
      ],
    );
  }
}

class _VipEditorOverlayLayout extends StatefulWidget {
  final String projectId;
  final String fullPath;
  final String filename;
  final String viewId;
  final String initialCode;
  final String aceMode;
  final VoidCallback onCloseRequested;
  final html.IFrameElement iframe;
  final VoidCallback onSaveSuccess;

  const _VipEditorOverlayLayout({
    Key? key,
    required this.projectId,
    required this.fullPath,
    required this.filename,
    required this.viewId,
    required this.initialCode,
    required this.aceMode,
    required this.onCloseRequested,
    required this.iframe,
    required this.onSaveSuccess,
  }) : super(key: key);

  @override
  __VipEditorOverlayLayoutState createState() => __VipEditorOverlayLayoutState();
}

class __VipEditorOverlayLayoutState extends State<_VipEditorOverlayLayout> {
  bool _isMaximized = false; 
  bool _isSaving = false; 
  StreamSubscription? _msgSub;

  @override
  void initState() {
    super.initState();
    _msgSub = html.window.onMessage.listen((event) {
      if (event.data != null && event.data['action'] == 'save') {
        _executeVipDatabaseSave(event.data['code'] ?? "");
      }
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  Future<void> _executeVipDatabaseSave(String currentCode) async {
    setState(() => _isSaving = true);
    try {
      final res = await http.post(
        Uri.parse('/api/project/${widget.projectId}/files/write'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"filename": widget.fullPath, "content": currentCode}),
      );
      if (res.statusCode == 200) {
        PremiumToast.show(context, "Successfully Saved!", true);
        widget.onSaveSuccess(); 
      } else {
        PremiumToast.show(context, "Failed to save file", false);
      }
    } catch (e) {
      PremiumToast.show(context, "Network Error on save operation", false);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOutCubic,
        width: _isMaximized ? MediaQuery.of(context).size.width : MediaQuery.of(context).size.width * 0.85,
        height: _isMaximized ? MediaQuery.of(context).size.height : MediaQuery.of(context).size.height * 0.80,
        margin: _isMaximized ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 30, vertical: 30),
        decoration: BoxDecoration(
          color: const Color(0xFF141622),
          borderRadius: _isMaximized ? BorderRadius.zero : BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.3), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 30, spreadRadius: 5)],
        ),
        child: ClipRRect(
          borderRadius: _isMaximized ? BorderRadius.zero : BorderRadius.circular(18),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: const Color(0xFF0F111a),
              automaticallyImplyLeading: false,
              elevation: 0,
              title: Row(
                children: [
                  const Icon(Icons.code_rounded, color: Color(0xFF45F3FF), size: 18),
                  const SizedBox(width: 10),
                  Text(widget.filename, style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                ],
              ),
              actions: [
                _isSaving 
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Color(0xFF45F3FF), strokeWidth: 2))),
                    )
                  : IconButton(
                      icon: const Icon(Icons.save_rounded, color: Colors.greenAccent, size: 20),
                      onPressed: () {
                        widget.iframe.contentWindow?.postMessage({'action': 'request_save'}, '*');
                      },
                      tooltip: "Save File",
                    ),
                IconButton(
                  icon: Icon(_isMaximized ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: Colors.amber, size: 20),
                  onPressed: () => setState(() => _isMaximized = !_isMaximized),
                  tooltip: "Maximize Window",
                ),
                const SizedBox(width: 5),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 22),
                  onPressed: widget.onCloseRequested,
                  tooltip: "Dismiss Editor",
                ),
                const SizedBox(width: 10),
              ],
            ),
            body: Container(
              width: double.infinity,
              height: double.infinity,
              color: const Color(0xFF141622),
              child: HtmlElementView(viewType: widget.viewId),
            ),
          ),
        ),
      ),
    );
  }
}

class LiveCyberBackgroundP extends StatefulWidget { const LiveCyberBackgroundP({Key? key}) : super(key: key); @override _LiveCyberBackgroundPState createState() => _LiveCyberBackgroundPState(); }
class _LiveCyberBackgroundPState extends State<LiveCyberBackgroundP> with SingleTickerProviderStateMixin {
  late AnimationController _c; @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _DiagonalWavePainterP(_c.value)));
}
class _DiagonalWavePainterP extends CustomPainter {
  final double progress; 
  _DiagonalWavePainterP(this.progress);
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF45F3FF).withOpacity(0.03)..strokeWidth = 1.5..style = PaintingStyle.stroke;
    double offset = progress * 100;
    for (double i = -size.height; i < size.width + size.height; i += 40) { canvas.drawLine(Offset(i + offset, 0), Offset(i - size.height + offset, size.height), p); }
  }
  @override bool shouldRepaint(covariant CustomPainter old) => true;
}

class _RealisticShatterPainterP extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.2)..strokeWidth = 1.0..style = PaintingStyle.stroke;
    final path = Path();
    for (int i = 0; i < 10; i++) {
      double cx = Random(i).nextDouble() * size.width; double cy = Random(i+1).nextDouble() * size.height;
      for (int j = 0; j < 5; j++) { double a = (j * 45) * (pi / 180); path.moveTo(cx, cy); path.lineTo(cx + cos(a) * 30, cy + sin(a) * 30); }
    }
    canvas.drawPath(path, p);
  }
  @override bool shouldRepaint(CustomPainter old) => false;
}

class CompactShatteredButtonP extends StatefulWidget {
  final String text; final VoidCallback onPressed;
  const CompactShatteredButtonP({Key? key, required this.text, required this.onPressed}) : super(key: key);
  @override _CompactShatteredButtonPState createState() => _CompactShatteredButtonPState();
}
class _CompactShatteredButtonPState extends State<CompactShatteredButtonP> with SingleTickerProviderStateMixin {
  late AnimationController _wave; @override void initState() { super.initState(); _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(); }
  @override void dispose() { _wave.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Container(
          width: 200, height: 45,
          decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.7))),
          child: Stack(children: [
            CustomPaint(size: const Size(200, 45), painter: _RealisticShatterPainterP()),
            AnimatedBuilder(animation: _wave, builder: (_, __) => Positioned(left: -100 + (_wave.value * 400), top: -50, bottom: -50, child: Transform.rotate(angle: 0.4, child: Container(width: 10, decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), boxShadow: [BoxShadow(color: const Color(0xFF45F3FF), blurRadius: 20)]))))),
            Center(child: Text(widget.text, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2))),
          ]),
        ),
      ),
    );
  }
}