import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart'; 
import 'package:http/http.dart' as http;
import 'dart:html' as html; 
import 'package:speech_to_text/speech_to_text.dart' as stt; 
import 'package:flutter_markdown/flutter_markdown.dart'; 

class ChatSession {
  String id;
  String title;
  bool isPinned;
  List<Map<String, String>> messages;

  ChatSession({
    required this.id,
    required this.title,
    this.isPinned = false,
    required this.messages,
  });
}

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({Key? key}) : super(key: key);

  @override
  _AiAssistantScreenState createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> with TickerProviderStateMixin {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _chatScrollCtrl = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<ChatSession> _sessions = [];
  String? _activeSessionId;
  bool isAiThinking = false;
  bool isHistoryLoading = false;
  bool isMessagesLoading = false; 
  bool userIsActivelyScrolling = false; 
  bool isStreamingOutput = false; 
  bool showScrollToBottomButton = false; 

  Map<String, bool> collapsedBlocks = {}; 
  Map<int, bool> userPromptCollapsed = {}; 
  List<Map<String, String>> attachedFiles = []; 

  late stt.SpeechToText _speech;
  bool _isListening = false;
  
  http.Client? _streamingClient;

  String _currentlySelectedText = "";

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    
    _chatScrollCtrl.addListener(() {
      if (_chatScrollCtrl.hasClients) {
        double maxScroll = _chatScrollCtrl.position.maxScrollExtent;
        double currentScroll = _chatScrollCtrl.position.pixels;
        
        if (maxScroll - currentScroll > 150) {
          if (!showScrollToBottomButton) {
            setState(() { showScrollToBottomButton = true; });
          }
        } else {
          if (showScrollToBottomButton) {
            setState(() { showScrollToBottomButton = false; });
          }
        }

        if (_chatScrollCtrl.position.userScrollDirection != ScrollDirection.idle) {
          if (maxScroll - currentScroll > 80) {
            if (!userIsActivelyScrolling) {
              setState(() { userIsActivelyScrolling = true; });
            }
          } else {
            if (userIsActivelyScrolling) {
              setState(() { userIsActivelyScrolling = false; });
            }
          }
        }
      }
    });

    _initializeDefaultVirtualChat(); 
    _loadChatSessionsHistory(); 
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _chatScrollCtrl.dispose();
    _streamingClient?.close();
    super.dispose();
  }

  bool _isUrduText(String text) {
    return RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]').hasMatch(text);
  }

  void _initializeDefaultVirtualChat() {
    setState(() {
      _activeSessionId = "VIRTUAL_NEW_CHAT";
      collapsedBlocks.clear();
      userPromptCollapsed.clear();
      attachedFiles.clear();
      userIsActivelyScrolling = false;
      showScrollToBottomButton = false;
      _currentlySelectedText = "";
    });
  }

  Future<void> _loadChatSessionsHistory() async {
    setState(() => isHistoryLoading = true);
    try {
      final res = await http.get(Uri.parse('/api/ai/sessions'));
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        setState(() {
          _sessions = data.map((s) => ChatSession(
            id: s['id'].toString(),
            title: s['title'],
            isPinned: s['is_pinned'] ?? false,
            messages: []
          )).toList();
        });
      }
    } catch (e) {
      print("History loading silent skip: $e");
    } finally {
      setState(() => isHistoryLoading = false);
    }
  }

  Future<void> _loadSessionMessagesFromDB(String sessionId) async {
    if (sessionId == "VIRTUAL_NEW_CHAT") return;
    setState(() {
      isMessagesLoading = true; 
      userIsActivelyScrolling = false;
      showScrollToBottomButton = false;
    });
    
    try {
      final res = await http.get(Uri.parse('/api/ai/sessions/$sessionId/messages'));
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        setState(() {
          _currentSession.messages = data.map((m) => {
            "role": m['role'].toString(),
            "text": m['text'].toString(),
            "files": m['files']?.toString() ?? "" 
          }).toList();
        });
        _scrollToBottomForceInstant();
      }
    } catch (e) {
      AiAssistantToast.show(context, "Failed to load messages", false);
    } finally {
      setState(() { isMessagesLoading = false; }); 
    }
  }

  Future<void> _updateSessionOnDB(ChatSession session, String action, {String? newTitle, bool? pinState}) async {
    if (session.id == "VIRTUAL_NEW_CHAT") return;
    try {
      await http.post(
        Uri.parse('/api/ai/sessions/${session.id}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "action": action,
          "title": newTitle,
          "is_pinned": pinState
        }),
      );
      _loadChatSessionsHistory(); 
    } catch (e) {}
  }

  Future<void> _deleteSessionFromDB(String sessionId) async {
    if (sessionId == "VIRTUAL_NEW_CHAT") return;
    try {
      final res = await http.delete(Uri.parse('/api/ai/sessions/$sessionId'));
      if (res.statusCode == 200) {
        setState(() {
          _sessions.removeWhere((s) => s.id == sessionId);
          _initializeDefaultVirtualChat();
        });
        _loadChatSessionsHistory();
        AiAssistantToast.show(context, "Chat deleted", true);
      }
    } catch (e) {}
  }

  void _showRenameChatDialog(ChatSession session) {
    final TextEditingController renameCtrl = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF020E18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.white10)),
        title: const Text("Rename Code Session", style: TextStyle(color: Color(0xFF45F3FF), fontSize: 14, fontWeight: FontWeight.bold)),
        content: TextFormField(
          controller: renameCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            filled: true, fillColor: Colors.white.withOpacity(0.02),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF45F3FF))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white38, fontSize: 12))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF45F3FF), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              if (renameCtrl.text.trim().isNotEmpty) {
                _updateSessionOnDB(session, "rename", newTitle: renameCtrl.text.trim());
                Navigator.pop(context);
                AiAssistantToast.show(context, "Chat renamed successfully!", true);
              }
            },
            child: const Text("Save", style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  ChatSession get _currentSession {
    return _sessions.firstWhere(
      (s) => s.id == _activeSessionId, 
      orElse: () => ChatSession(id: "VIRTUAL_NEW_CHAT", title: "New Silent Chat", messages: [
        {"role": "ai", "text": "⚡ Welcome to Silent AI Engine. Paste your deployment errors, logs, or ask me to write optimized Dockerfiles/Build commands!"}
      ])
    );
  }

  void _listenToVoice() async {
    if (!_isListening) {
      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() { _msgCtrl.text = val.recognizedWords; });
          },
          listenMode: stt.ListenMode.confirmation, 
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _attachCodeFile() {
    final uploadInput = html.FileUploadInputElement()..multiple = true;
    uploadInput.click();
    uploadInput.onChange.listen((e) {
      if (uploadInput.files != null) {
        for (var file in uploadInput.files!) {
          final reader = html.FileReader();
          reader.readAsText(file);
          reader.onLoadEnd.listen((e) {
            setState(() {
              attachedFiles.add({"name": file.name, "content": reader.result as String});
            });
          });
        }
      }
    });
  }

  Future<void> _sendChatMessage() async {
    String userText = _msgCtrl.text.trim();
    if (userText.isEmpty && attachedFiles.isEmpty || isAiThinking || isStreamingOutput) return;

    for (var file in attachedFiles) {
      int lineCount = const LineSplitter().convert(file['content']!).length;
      if (lineCount > 1000) {
        AiAssistantToast.show(
          context, 
          "Chat Limit Reached. Silent AI supports only a 1,000 line file structure.", 
          false
        );
        return; 
      }
    }

    String filesListString = attachedFiles.map((f) => f['name']!).join(',');
    String fullPayloadPrompt = userText;

    if (attachedFiles.isNotEmpty) {
      fullPayloadPrompt += "\n\n[ATTACHED CODE FILES]:";
      for (var f in attachedFiles) {
        fullPayloadPrompt += "\nFile Name: ${f['name']}\nSource Code:\n${f['content']}\n---";
      }
    }

    if (_activeSessionId == "VIRTUAL_NEW_CHAT") {
      try {
        final res = await http.post(Uri.parse('/api/ai/sessions'));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final newRealSession = ChatSession(
            id: data['id'].toString(), 
            title: userText.length > 20 ? "${userText.substring(0, 20)}..." : "Code Session", 
            messages: []
          );
          _sessions.insert(0, newRealSession);
          _activeSessionId = newRealSession.id;
        } else {
          setState(() {
            _currentSession.messages.add({"role": "ai", "text": "❌ Chat limit reached or connection interrupted. Please start a new chat."});
          });
          return;
        }
      } catch (e) {
        setState(() {
          _currentSession.messages.add({"role": "ai", "text": "❌ Server control plane handshake failed. Try starting a new session."});
        });
        return;
      }
    }

    final session = _currentSession;

    setState(() {
      session.messages.add({
        "role": "user", 
        "text": userText.isNotEmpty ? userText : "Analyzed ${attachedFiles.length} files.",
        "files": filesListString
      });
      _msgCtrl.clear();
      attachedFiles.clear(); 
      isAiThinking = true;
      isStreamingOutput = true; 
      userIsActivelyScrolling = false; 
      showScrollToBottomButton = false;
    });
    _scrollToBottomForceInstant();

    try {
      _streamingClient = http.Client();
      
      final request = http.Request('POST', Uri.parse('/api/ai/chat'));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        "session_id": int.parse(session.id), 
        "prompt": fullPayloadPrompt,
        "files": filesListString
      });

      final response = await _streamingClient!.send(request);

      if (response.statusCode == 200) {
        setState(() {
          isAiThinking = false;
          session.messages.add({"role": "ai", "text": ""});
        });

        String fullAccumulatedReplyText = "";
        String remainingBuffer = "";

        await for (var bytes in response.stream.transform(utf8.decoder)) {
          remainingBuffer += bytes;
          List<String> rawLines = remainingBuffer.split('\n');
          remainingBuffer = rawLines.removeLast();

          for (String rawLine in rawLines) {
            String cleanLine = rawLine.trim();
            if (cleanLine.startsWith("data:")) {
              String jsonString = cleanLine.substring(5).trim();
              try {
                var chunkData = jsonDecode(jsonString);
                if (chunkData['type'] == 'text') {
                  String chunkText = chunkData['text'] ?? "";
                  fullAccumulatedReplyText += chunkText;
                  
                  if (mounted) {
                    setState(() {
                      session.messages.last["text"] = fullAccumulatedReplyText;
                    });
                    _smartSoftAutoScroll(); 
                  }
                }
              } catch (e) {
                continue;
              }
            }
          }
        }

      } else {
        setState(() { session.messages.add({"role": "ai", "text": "❌ Chat limit reached or connection interrupted. Please start a new chat."}); });
      }
    } catch (e) {
      if (isStreamingOutput || isAiThinking) {
        setState(() { session.messages.add({"role": "ai", "text": "❌ Chat limit reached or connection interrupted. Please start a new chat."}); });
      }
    } finally { 
      if (mounted) {
        setState(() {
          isAiThinking = false;
          isStreamingOutput = false;
        });
        _smartSoftAutoScroll();
      }
    }
  }

  void _stopAiStreaming() {
    _streamingClient?.close(); 
    setState(() {
      isAiThinking = false;
      isStreamingOutput = false;
    });
    AiAssistantToast.show(context, "AI Transmission Halted Safely.", true);
  }

  void _smartSoftAutoScroll() {
    if (_chatScrollCtrl.hasClients && !userIsActivelyScrolling) {
      Future.delayed(const Duration(milliseconds: 10), () {
        if (_chatScrollCtrl.hasClients && !userIsActivelyScrolling) {
          _chatScrollCtrl.animateTo(
            _chatScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100), 
            curve: Curves.easeOut, 
          );
        }
      });
    }
  }

  void _scrollToBottomForceInstant() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.jumpTo(_chatScrollCtrl.position.maxScrollExtent);
      }
    });
  }

  void _showCustomContextMenu(String text) {
    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF020E18),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15))),
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.copy, color: Color(0xFF45F3FF), size: 20),
            title: const Text("Copy Message Payload", style: TextStyle(color: Colors.white, fontSize: 14)),
            onTap: () { Clipboard.setData(ClipboardData(text: text)); Navigator.pop(context); AiAssistantToast.show(context, "Copied to Clipboard!", true); },
          ),
        ],
      ),
    );
  }

  void _triggerNativeFileDownload(String fileContent, String languageName) {
    String fileExt = "txt";
    String cleanLang = languageName.replaceAll(RegExp(r'[^\w\s]'), '').trim().toLowerCase();
    
    if (cleanLang.contains("python") || cleanLang.contains("flask")) fileExt = "py";
    else if (cleanLang.contains("golang") || cleanLang.contains("go")) fileExt = "go";
    else if (cleanLang.contains("javascript") || cleanLang.contains("node") || cleanLang.contains("js")) fileExt = "js";
    else if (cleanLang.contains("bash") || cleanLang.contains("sh") || cleanLang.contains("curl")) fileExt = "sh";
    else if (cleanLang.contains("rust")) fileExt = "rs";
    else if (cleanLang.contains("html")) fileExt = "html";
    else if (cleanLang.contains("css")) fileExt = "css";
    else if (cleanLang.contains("dart")) fileExt = "dart";
    else if (cleanLang.contains("docker")) fileExt = "Dockerfile";

    int epochStamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    String finalFileName = fileExt == "Dockerfile" ? "Dockerfile" : "silent_script_$epochStamp.$fileExt";

    final blob = html.Blob([fileContent], 'text/plain');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", finalFileName)
      ..click();
    html.Url.revokeObjectUrl(url);
    AiAssistantToast.show(context, "File downloaded successfully!", true);
  }

  Widget _buildDirectionalText(String rawText, bool forceLeft, TextStyle style) {
    if (forceLeft || (!RegExp(r'[\u0600-\u06FF]').hasMatch(rawText))) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Text(rawText, style: style, textAlign: TextAlign.left),
      );
    }
    return Text(
      rawText, 
      style: style, 
      textDirection: TextDirection.rtl, 
      textAlign: TextAlign.right
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey, backgroundColor: const Color(0xFF0A0A10),
      drawer: _buildHistoryDrawer(),
      floatingActionButton: showScrollToBottomButton ? _buildScrollToBottomFloatingButton() : null, 
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: RadialGradient(colors: [Color(0xFF0F3B57), Color(0xFF082236), Color(0xFF020E18)], radius: 1.5))),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildChatFeed()),
                if (attachedFiles.isNotEmpty) _buildHorizontalAttachmentBar(),
                _buildInputFieldZone(),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildScrollToBottomFloatingButton() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 60.0), 
      child: FloatingActionButton.small(
        backgroundColor: const Color(0xFF082236),
        elevation: 8,
        shape: const CircleBorder(side: BorderSide(color: Color(0xFF45F3FF), width: 1)),
        onPressed: () {
          setState(() { userIsActivelyScrolling = false; });
          _chatScrollCtrl.animateTo(_chatScrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        },
        child: const Icon(Icons.arrow_downward_rounded, color: Color(0xFF45F3FF), size: 18),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.all(15), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            IconButton(icon: const Icon(Icons.menu, color: Color(0xFF45F3FF)), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
            const SizedBox(width: 10),
            Text(_activeSessionId == "VIRTUAL_NEW_CHAT" ? "New Silent Chat" : _currentSession.title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          IconButton(icon: const Icon(Icons.add_comment_rounded, color: Color(0xFF45F3FF)), onPressed: _initializeDefaultVirtualChat),
        ],
      ),
    );
  }

  Widget _buildChatFeed() {
    if (isMessagesLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF45F3FF)),
            SizedBox(height: 15),
            Text("Decrypting Secure Session...", style: TextStyle(color: Color(0xFF45F3FF), fontSize: 12, fontFamily: 'monospace', letterSpacing: 1.5))
          ],
        ),
      );
    }

    final currentMsgs = _currentSession.messages;
    return ListView.builder(
      controller: _chatScrollCtrl, padding: const EdgeInsets.all(20),
      itemCount: currentMsgs.length + (isStreamingOutput && currentMsgs.last['role'] != 'ai' ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == currentMsgs.length) return _buildThinkingBubble();
        var msg = currentMsgs[index];
        
        if (index == currentMsgs.length - 1 && msg['role'] == 'ai' && msg['text']!.isEmpty) {
          return _buildThinkingBubble();
        }
        
        return _buildMessageParserBlock(msg['text']!, msg['role'] == 'ai', index, msg['files'] ?? "");
      },
    );
  }

  Widget _buildMessageParserBlock(String fullText, bool isAi, int msgIndex, String bubbleFiles) {
    bool isUrdu = _isUrduText(fullText);

    if (!isAi) {
      bool isCollapsed = userPromptCollapsed[msgIndex] ?? true;
      List<String> lines = fullText.split('\n');
      bool isLongPrompt = lines.length > 5 || fullText.length > 200;

      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.04), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.15))),
          child: Column(
            crossAxisAlignment: isUrdu ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (bubbleFiles.isNotEmpty) ...[
                Wrap(
                  spacing: 5, runSpacing: 5,
                  children: bubbleFiles.split(',').map((fileName) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.1), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.2))),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.insert_drive_file, color: Color(0xFF45F3FF), size: 12),
                        const SizedBox(width: 4),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(fileName, style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'monospace'))
                        ),
                      ],
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 8),
              ],
              GestureDetector(
                onLongPress: () => _showCustomContextMenu(fullText),
                child: _buildDirectionalText(
                  isLongPrompt && isCollapsed ? (fullText.substring(0, min(180, fullText.length)) + "...") : fullText,
                  false, 
                  const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)
                ),
              ),
              if (isLongPrompt)
                GestureDetector(
                  onTap: () => setState(() { userPromptCollapsed[msgIndex] = !isCollapsed; }),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(isCollapsed ? "Read More" : "Collapse", style: const TextStyle(color: Color(0xFF45F3FF), fontSize: 11, fontWeight: FontWeight.bold)),
                        Icon(isCollapsed ? Icons.arrow_drop_down : Icons.arrow_drop_up, color: const Color(0xFF45F3FF), size: 16)
                      ],
                    ),
                  ),
                )
            ],
          ),
        ),
      );
    }

    List<Widget> parsedWidgets = [];
    bool inCodeBlock = false;
    bool inDocumentShard = false;
    String codeBuffer = "";
    String shardBuffer = "";
    String textBuffer = "";
    String currentLang = "CODE";
    final backticks = String.fromCharCode(96) * 3;

    List<String> lines = fullText.split('\n');

    void flushTextBuffer() {
      if (textBuffer.trim().isNotEmpty) {
        String rawText = textBuffer;
        bool isHeading = rawText.trim().startsWith("###") || rawText.trim().startsWith("##") || rawText.trim().startsWith("#");
        rawText = rawText.replaceAll(RegExp(r'#+\s*'), ''); 
        rawText = rawText.replaceAll(RegExp(r'-\s+'), '• '); 

        bool textIsUrdu = _isUrduText(rawText);
        parsedWidgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Align(
            alignment: textIsUrdu ? Alignment.centerRight : Alignment.centerLeft,
            child: SelectionArea(
              // 🔥 VIP NATIVE VALVE: فلوٹر پبلک لیسنر جو ہر کسٹمر سلیکشن کا ٹیکسٹ لائیو ریکارڈ کرے گا
              onSelectionChanged: (SelectedContent? content) {
                _currentlySelectedText = content?.plainText ?? "";
              },
              contextMenuBuilder: (context, selectionState) => _buildVipContextMenu(context, selectionState, rawText),
              child: Directionality(
                textDirection: textIsUrdu ? TextDirection.rtl : TextDirection.ltr,
                child: MarkdownBody(
                  data: rawText,
                  selectable: false,
                  onTapLink: (text, href, title) {
                    if (href != null) {
                      html.window.open(href, '_blank');
                    }
                  },
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(color: isHeading ? const Color(0xFF45F3FF) : const Color(0xFFE2E8F0), fontSize: 13, height: 1.6),
                    listBullet: const TextStyle(color: Color(0xFF45F3FF), fontSize: 13),
                    code: TextStyle(color: const Color(0xFF34D399), backgroundColor: Colors.white.withOpacity(0.08), fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ),
        ));
        textBuffer = "";
      }
    }

    for (String line in lines) {
      String trimmedLine = line.trim();

      if (!inCodeBlock && !inDocumentShard && trimmedLine.startsWith(backticks)) {
        flushTextBuffer();
        inCodeBlock = true;
        String langMatch = trimmedLine.substring(3).trim().toLowerCase();
        if(langMatch.startsWith("python") || langMatch.startsWith("flask")) currentLang = "PYTHON";
        else if(langMatch.startsWith("go")) currentLang = "GOLANG";
        else if(langMatch.startsWith("bash") || langMatch.startsWith("sh") || langMatch.startsWith("curl")) currentLang = "BASH / cURL";
        else if(langMatch.startsWith("javascript") || langMatch.startsWith("js") || langMatch.startsWith("node")) currentLang = "JAVASCRIPT";
        else if(langMatch.startsWith("dart")) currentLang = "DART";
        else if(langMatch.startsWith("rust")) currentLang = "RUST";
        else if(langMatch.startsWith("html")) currentLang = "HTML";
        else if(langMatch.startsWith("css")) currentLang = "CSS";
        else if(langMatch.isNotEmpty) currentLang = langMatch.toUpperCase();
        else currentLang = "CODE";
      } 
      else if (inCodeBlock && trimmedLine == backticks) {
        parsedWidgets.add(_buildPremiumCodeBox(codeBuffer.trimRight(), currentLang, "${msgIndex}_${parsedWidgets.length}"));
        codeBuffer = "";
        inCodeBlock = false;
      }
      else if (!inCodeBlock && trimmedLine.startsWith(">")) {
        if (!inDocumentShard) {
          flushTextBuffer();
          inDocumentShard = true;
        }
        shardBuffer += trimmedLine.replaceFirst(RegExp(r'>\s*'), '') + '\n';
      }
      else if (inDocumentShard && !trimmedLine.startsWith(">")) {
        parsedWidgets.add(_buildVipDocumentShardBox(shardBuffer.trimRight(), "${msgIndex}_${parsedWidgets.length}"));
        shardBuffer = "";
        inDocumentShard = false;
        textBuffer += line + '\n';
      }
      else {
        if (inCodeBlock) {
          codeBuffer += line + '\n';
        } else {
          textBuffer += line + '\n';
        }
      }
    }

    if (inCodeBlock) {
      parsedWidgets.add(_buildPremiumCodeBox(codeBuffer.trimRight(), currentLang, "${msgIndex}_${parsedWidgets.length}"));
    } else if (inDocumentShard) {
      parsedWidgets.add(_buildVipDocumentShardBox(shardBuffer.trimRight(), "${msgIndex}_${parsedWidgets.length}"));
    } else {
      flushTextBuffer();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...parsedWidgets,
            if (isStreamingOutput && msgIndex == _currentSession.messages.length - 1) ...[
              const SizedBox(height: 8),
              _buildLiveStreamPulseDots(), 
            ],
            const SizedBox(height: 6),
            _buildCosmeticActionFeedbackBar(fullText),
            const Divider(color: Colors.white10, height: 25),
          ],
        ),
      ),
    );
  }

  Widget _buildVipDocumentShardBox(String shardText, String blockId) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: double.infinity,
      decoration: BoxDecoration(
        color: _ColorExtension.redWithOpacity(0.05), 
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withOpacity(0.35), width: 1.2),
        boxShadow: [
          BoxShadow(color: Colors.redAccent.withOpacity(0.05), blurRadius: 15, spreadRadius: 1)
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.01),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16))
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: Colors.white38, size: 16),
                    onPressed: () { Clipboard.setData(ClipboardData(text: shardText)); AiAssistantToast.show(context, "Shard Payload Copied!", true); }
                  ),
                  const SizedBox(width: 6),
                  const Text("دستاویزی جزو", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                ]),
                const Text("DOCUMENT SHARD", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w900, fontFamily: 'monospace', letterSpacing: 1)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SelectionArea(
              onSelectionChanged: (SelectedContent? content) {
                _currentlySelectedText = content?.plainText ?? "";
              },
              contextMenuBuilder: (context, selectionState) => _buildVipContextMenu(context, selectionState, shardText),
              child: Text(
                shardText,
                textDirection: _isUrduText(shardText) ? TextDirection.rtl : TextDirection.ltr,
                textAlign: _isUrduText(shardText) ? TextAlign.right : TextAlign.left,
                style: const TextStyle(color: Color(0xFFFFC1C1), fontSize: 13, height: 1.7, fontWeight: FontWeight.w500),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPremiumCodeBox(String code, String language, String blockId) {
    bool isCollapsed = collapsedBlocks[blockId] ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.transparent, 
        borderRadius: BorderRadius.circular(14), 
        border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.35), width: 1.2),
        boxShadow: [
          BoxShadow(color: const Color(0xFF45F3FF).withOpacity(0.01), blurRadius: 10)
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF45F3FF).withOpacity(0.03), 
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: const Color(0xFF45F3FF).withOpacity(0.15), width: 1))
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: Color(0xFF45F3FF), size: 15), 
                    onPressed: () { Clipboard.setData(ClipboardData(text: code)); AiAssistantToast.show(context, "Code Copied!", true); }
                  ),
                  Text(
                    language, 
                    style: const TextStyle(color: Color(0xFF45F3FF), fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: 0.5)
                  ),
                ]),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download_rounded, color: Color(0xFF34D399), size: 16),
                      onPressed: () => _triggerNativeFileDownload(code, language),
                    ),
                    IconButton(
                      icon: Icon(isCollapsed ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: Colors.white38, size: 16), 
                      onPressed: () => setState(() { collapsedBlocks[blockId] = !isCollapsed; })
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!isCollapsed)
            Container(
              constraints: const BoxConstraints(maxHeight: 380), 
              width: double.infinity, 
              padding: const EdgeInsets.all(14),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectionArea(
                        onSelectionChanged: (SelectedContent? content) {
                          _currentlySelectedText = content?.plainText ?? "";
                        },
                        contextMenuBuilder: (context, selectionState) => _buildVipContextMenu(context, selectionState, code),
                        child: Text.rich( 
                          _highlightCodeSyntax(code), 
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5)
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  TextSpan _highlightCodeSyntax(String code) {
    List<TextSpan> spans = [];
    
    RegExp regex = RegExp(
      r'(#.*|//.*)|' 
      r'("(?:\\.|[^"\\])*"|' 
      r"'(?:\\.|[^'\\])*')|" 
      r'\b(def|fn|func|return|import|from|class|struct|let|mut|pub|use|async|await|if|else|for|while|match|switch|case|package)\b|' 
      r'\b(true|false|None|nil|int|string|bool|float|void|AsyncStream|Json|State|HeaderMap|Result)\b' 
    );

    int start = 0;
    for (var match in regex.allMatches(code)) {
      if (match.start > start) {
        spans.add(TextSpan(text: code.substring(start, match.start), style: const TextStyle(color: Color(0xFFE2E8F0))));
      }

      if (match.group(1) != null) {
        spans.add(TextSpan(text: match.group(1), style: const TextStyle(color: Colors.white38, fontStyle: FontStyle.italic)));
      } else if (match.group(2) != null) {
        spans.add(TextSpan(text: match.group(2), style: const TextStyle(color: Color(0xFFFDBA74))));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(text: match.group(3), style: const TextStyle(color: Color(0xFF60A5FF), fontWeight: FontWeight.bold)));
      } else if (match.group(4) != null) {
        spans.add(TextSpan(text: match.group(4), style: const TextStyle(color: Color(0xFF34D399))));
      }
      start = match.end;
    }

    if (start < code.length) {
      spans.add(TextSpan(text: code.substring(start), style: const TextStyle(color: Color(0xFFA7F3D0))));
    }
    return TextSpan(children: spans);
  }

  // 🔥 VIP NATIVE FIXED OVERLAY MECHANISM (Bypasses hidden getters completely)
  Widget _buildVipContextMenu(BuildContext context, SelectableRegionState selectionState, String fullText) {
    // اگر کسٹمر نے کوئی حصہ مینوئلی انگلی سے سلیکٹ کیا ہے تو لائیو اسٹیٹ اٹھائیں، ورنہ پورا متبادل ٹیکسٹ لاک کریں
    String targetSelectedText = _currentlySelectedText.isNotEmpty ? _currentlySelectedText : fullText;

    return AdaptiveTextSelectionToolbar(
      anchors: selectionState.contextMenuAnchors,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          decoration: BoxDecoration(
            color: Colors.transparent, // کالی پٹی مستقل غائب
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.5), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildVipMenuButton("COPY", Icons.copy, () {
                Clipboard.setData(ClipboardData(text: targetSelectedText));
                selectionState.hideToolbar(); // مینیو صرف کاپی یا کٹ ایکشن پر بند ہوگا
                AiAssistantToast.show(context, "Copied to Clipboard!", true);
              }),
              Container(width: 1, height: 20, color: const Color(0xFF45F3FF).withOpacity(0.2)),
              _buildVipMenuButton("SELECT ALL", Icons.select_all, () {
                selectionState.selectAll(); // ہائی لائٹ آل کرے گا، مینیو غائب نہیں ہوگا!
              }),
              Container(width: 1, height: 20, color: const Color(0xFF45F3FF).withOpacity(0.2)),
              _buildVipMenuButton("SHARE", Icons.share, () {
                selectionState.hideToolbar();
                if (html.window.navigator.share != null) {
                  html.window.navigator.share({'text': targetSelectedText});
                } else {
                  AiAssistantToast.show(context, "Sharing not supported in this browser", false);
                }
              }),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildVipMenuButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF45F3FF), size: 14),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }

  Widget _buildCosmeticActionFeedbackBar(String fullText) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(icon: const Icon(Icons.copy_all, size: 16, color: Colors.white38), onPressed: () { Clipboard.setData(ClipboardData(text: fullText)); AiAssistantToast.show(context, "Full Payload Copied!", true); }),
        const SizedBox(width: 5),
        _buildCosmeticFeedbackIcon(Icons.thumb_up_outlined),
        const SizedBox(width: 5),
        _buildCosmeticFeedbackIcon(Icons.thumb_down_outlined),
      ],
    );
  }

  Widget _buildCosmeticFeedbackIcon(IconData icon) {
    bool isSelected = false;
    return StatefulBuilder(builder: (context, setIconState) => IconButton(icon: Icon(icon, size: 14, color: isSelected ? const Color(0xFF45F3FF) : Colors.white38), onPressed: () => setIconState(() { isSelected = !isSelected; })));
  }

  Widget _buildThinkingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.1))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text("Synthesizing optimal response", style: TextStyle(color: Color(0xFF45F3FF), fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
            SizedBox(width: 8),
            JumpingDotsEngine(),
          ],
         ),
      ),
    );
  }

  Widget _buildLiveStreamPulseDots() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Text("⚡ Receiving secure telemetry", style: TextStyle(color: Color(0xFF34D399), fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
        SizedBox(width: 6), 
        JumpingDotsEngine(),
      ],
    );
  }

  Widget _buildHorizontalAttachmentBar() {
    return Container(
      height: 45, margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
      child: ListView.builder(
        scrollDirection: Axis.horizontal, itemCount: attachedFiles.length,
        itemBuilder: (c, i) => Container(
          margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: const Color(0xFF45F3FF).withOpacity(0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.25))),
          child: Row(children: [
            const Icon(Icons.insert_drive_file, color: Color(0xFF45F3FF), size: 14), const SizedBox(width: 6),
            Text(attachedFiles[i]['name']!, style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace')), const SizedBox(width: 6),
            GestureDetector(onTap: () => setState(() { attachedFiles.removeAt(i); }), child: const Icon(Icons.close, color: Colors.redAccent, size: 12)),
          ]),
        ),
      ),
    );
  }

  Widget _buildInputFieldZone() {
    bool showStopButton = isAiThinking || isStreamingOutput; 

    return Container(
      padding: const EdgeInsets.all(15), decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white10))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end, 
        children: [
          GestureDetector(
            onTap: _attachCodeFile, 
            child: Container(
              height: 40, width: 40, 
              margin: const EdgeInsets.only(bottom: 2), 
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(10)), 
              child: const Icon(Icons.add, color: Color(0xFF45F3FF), size: 18)
            )
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120), 
              child: Scrollbar(
                thumbVisibility: true,
                child: TextFormField(
                  controller: _msgCtrl, 
                  maxLines: null, 
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  // انپٹ باکس کا فلو لیس مینیو مینیجر
                  contextMenuBuilder: (context, editableTextState) {
                    final String inputAllText = _msgCtrl.text;
                    final TextSelection inputSelection = editableTextState.textEditingValue.selection;
                    String targetInputText = inputSelection.textInside(inputAllText);
                    if (targetInputText.isEmpty) targetInputText = inputAllText;

                    return AdaptiveTextSelectionToolbar(
                      anchors: editableTextState.contextMenuAnchors,
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          decoration: BoxDecoration(
                            color: Colors.transparent, 
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.5), width: 1.2),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildVipMenuButton("CUT", Icons.cut, () {
                                editableTextState.cutSelection(SelectionChangedCause.toolbar);
                                editableTextState.hideToolbar();
                              }),
                              Container(width: 1, height: 20, color: Colors.white10),
                              _buildVipMenuButton("COPY", Icons.copy, () {
                                editableTextState.copySelection(SelectionChangedCause.toolbar);
                                editableTextState.hideToolbar();
                                AiAssistantToast.show(context, "Copied to Clipboard!", true);
                              }),
                              Container(width: 1, height: 20, color: Colors.white10),
                              _buildVipMenuButton("PASTE", Icons.paste, () {
                                editableTextState.pasteText(SelectionChangedCause.toolbar);
                                editableTextState.hideToolbar();
                              }),
                              Container(width: 1, height: 20, color: Colors.white10),
                              _buildVipMenuButton("SELECT ALL", Icons.select_all, () {
                                editableTextState.selectAll(SelectionChangedCause.toolbar); 
                              }),
                            ],
                          ),
                        )
                      ],
                    );
                  },
                  decoration: InputDecoration(
                    hintText: "Ask anything or paste logs...", 
                    hintStyle: const TextStyle(color: Colors.white24),
                    filled: true, 
                    fillColor: Colors.white.withOpacity(0.02),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    suffixIcon: IconButton(
                      icon: Icon(_isListening ? Icons.mic_none : Icons.mic, color: _isListening ? Colors.redAccent : Colors.white38, size: 20), 
                      onPressed: _listenToVoice
                    ), 
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: showStopButton ? _stopAiStreaming : _sendChatMessage, 
            child: Container(
              height: 40, width: 40,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: showStopButton ? Colors.redAccent.withOpacity(0.2) : const Color(0xFF45F3FF).withOpacity(0.15), 
                borderRadius: BorderRadius.circular(12), 
                border: Border.all(color: showStopButton ? Colors.redAccent : const Color(0xFF45F3FF))
              ),
              child: Icon(showStopButton ? Icons.stop_circle_rounded : Icons.send, color: showStopButton ? Colors.redAccent : const Color(0xFF45F3FF), size: 16),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildHistoryDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF082236).withOpacity(0.95),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF45F3FF), foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () { Navigator.pop(context); _initializeDefaultVirtualChat(); },
              icon: const Icon(Icons.add), label: const Text("NEW CHAT", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 20, vertical: 5), child: Text("CHAT HISTORY", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold))),
          Expanded(
            child: isHistoryLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF45F3FF))) 
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10), itemCount: _sessions.length,
                  itemBuilder: (context, i) {
                    final s = _sessions[i]; bool isActive = s.id == _activeSessionId;
                    return ListTile(
                      selected: isActive, selectedTileColor: const Color(0xFF45F3FF).withOpacity(0.08),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      leading: Icon(s.isPinned ? Icons.push_pin : Icons.chat_bubble_outline, color: isActive ? const Color(0xFF45F3FF) : Colors.white38, size: 16),
                      title: Text(s.title, style: TextStyle(color: isActive ? const Color(0xFF45F3FF) : Colors.white70, fontSize: 13), overflow: TextOverflow.ellipsis),
                      onTap: () { 
                        setState(() { 
                          _activeSessionId = s.id; 
                        }); 
                        Navigator.pop(context); 
                        _loadSessionMessagesFromDB(s.id); 
                      },
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz, color: Colors.white38, size: 16), color: const Color(0xFF020E18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.white10)),
                        itemBuilder: (c) => [
                          PopupMenuItem(value: 'rename', child: Row(children: const [Icon(Icons.edit, size: 14, color: Color(0xFF45F3FF)), SizedBox(width: 8), Text("Rename Chat", style: TextStyle(color: Colors.white, fontSize: 12))])),
                          PopupMenuItem(value: 'pin', child: Row(children: [Icon(Icons.push_pin, size: 14, color: s.isPinned ? Colors.redAccent : const Color(0xFF45F3FF)), const SizedBox(width: 8), Text(s.isPinned ? "Unpin" : "Pin Chat", style: const TextStyle(color: Colors.white, fontSize: 12))])),
                          PopupMenuItem(value: 'delete', child: Row(children: const [Icon(Icons.delete, size: 14, color: Colors.redAccent), SizedBox(width: 8), Text("Delete", style: TextStyle(color: Colors.redAccent, fontSize: 12))])),
                        ],
                        onSelected: (val) {
                          if (val == 'rename') _showRenameChatDialog(s);
                          if (val == 'pin') _updateSessionOnDB(s, "pin", pinState: !s.isPinned);
                          if (val == 'delete') _deleteSessionFromDB(s.id);
                        },
                      ),
                    );
                  },
                ),
          )
        ],
      ),
    );
  }
}

class _ColorExtension {
  static Color redWithOpacity(double opacity) => const Color(0xFF3A0D14).withOpacity(opacity);
}

class JumpingDotsEngine extends StatefulWidget {
  const JumpingDotsEngine({Key? key}) : super(key: key);
  @override _JumpingDotsEngineState createState() => _JumpingDotsEngineState();
}
class _JumpingDotsEngineState extends State<JumpingDotsEngine> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;
  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 300)));
    _animations = _controllers.map((c) => Tween<double>(begin: 0, end: -6).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut))).toList();
    _startAnimations();
  }
  void _startAnimations() async {
    for (int i = 0; i < 3; i++) {
      if (!mounted) return;
      _controllers[i].forward().then((_) { if (mounted) _controllers[i].reverse(); });
      await Future.delayed(const Duration(milliseconds: 120));
    }
    if (mounted) Future.delayed(const Duration(milliseconds: 250), _startAnimations);
  }
  @override
  void dispose() { for (var c in _controllers) { c.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) => AnimatedBuilder(animation: _animations[i], builder: (context, child) => Transform.translate(offset: Offset(0, _animations[i].value), child: Container(margin: const EdgeInsets.symmetric(horizontal: 2), width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF45F3FF), shape: BoxShape.circle))))));
  }
}

class AiAssistantToast {
  static void show(BuildContext context, String msg, bool success) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(builder: (context) => Positioned(top: 50, left: 20, right: 20, child: Material(color: Colors.transparent, child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), decoration: BoxDecoration(color: const Color(0xFF082236).withOpacity(0.9), borderRadius: BorderRadius.circular(12), border: Border.all(color: success ? const Color(0xFF45F3FF) : Colors.redAccent, width: 1)), child: Row(children: [Icon(success ? Icons.check_circle : Icons.error, color: success ? const Color(0xFF45F3FF) : Colors.redAccent, size: 20), const SizedBox(width: 12), Expanded(child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)))])))));
    overlay.insert(entry); Timer(const Duration(seconds: 3), () => entry.remove());
  }
}