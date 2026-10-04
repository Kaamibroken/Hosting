import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:html' as html;

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({Key? key}) : super(key: key);

  void _openLink(String url) {
    html.window.open(url, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    // Determine if the screen is running on a mobile device for responsive padding
    bool isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A10),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF45F3FF)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Icon(Icons.menu_book_rounded, color: Color(0xFFA855F7), size: 22),
            SizedBox(width: 10),
            Text("DOCUMENTATION & HELP",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    fontSize: 16,
                    color: Colors.white)),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Premium Background Gradient
          Container(
              decoration: const BoxDecoration(
                  gradient: RadialGradient(
                      colors: [Color(0xFF0F3B57), Color(0xFF082236), Color(0xFF020E18)],
                      radius: 1.5))),
          
          // Live Cyber Background Waves
          const Positioned.fill(child: LiveCyberBackgroundX()),

          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 20 : MediaQuery.of(context).size.width * 0.15,
                  vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- SECTION 1: PRIVACY & SECURITY ---
                  _buildHeader(Icons.security, "Privacy Policy & Security", const Color(0xFF34D399)),
                  const SizedBox(height: 15),
                  _buildGlassContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: const TextSpan(
                            style: TextStyle(color: Colors.white60, height: 1.6, fontSize: 14),
                            children: [
                              TextSpan(text: "At "),
                              TextSpan(
                                  text: "Silent Hosting",
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              TextSpan(
                                  text:
                                      ", we take your privacy, data security, and source code protection as our highest priority. Operating on an enterprise-grade infrastructure, we ensure that your source code, environment variables, and user databases are entirely isolated in highly secure, containerized environments."),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Responsive Layout for Info Boxes
                        isMobile
                            ? Column(
                                children: [
                                  _buildInfoBox(
                                      Icons.lock_outline,
                                      "Military-Grade",
                                      "Your project files and database credentials are fully encrypted.",
                                      const Color(0xFF34D399)),
                                  const SizedBox(height: 15),
                                  _buildInfoBox(
                                      Icons.dns_outlined,
                                      "Absolute Privacy",
                                      "We do not monitor or share your deployment logs. Data is instantly wiped.",
                                      const Color(0xFF3B82F6)),
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      child: _buildInfoBox(
                                          Icons.lock_outline,
                                          "Military-Grade",
                                          "Your project files and database credentials are fully encrypted.",
                                          const Color(0xFF34D399))),
                                  const SizedBox(width: 15),
                                  Expanded(
                                      child: _buildInfoBox(
                                          Icons.dns_outlined,
                                          "Absolute Privacy",
                                          "We do not monitor or share your deployment logs. Data is instantly wiped.",
                                          const Color(0xFF3B82F6))),
                                ],
                              ),
                        const SizedBox(height: 20),
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 10),
                        RichText(
                          text: const TextSpan(
                            style: TextStyle(color: Colors.white60, height: 1.5, fontSize: 13),
                            children: [
                              TextSpan(
                                  text: "Fair Usage Policy: ",
                                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                              TextSpan(
                                  text:
                                      "By utilizing our cloud network, you agree not to host malicious scripts, phishing sites, or botnets. Violating our policies will result in an immediate hardware IP ban."),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // --- SECTION 2: DOCKER FILE ---
                  _buildHeader(Icons.terminal, "Advanced Execution Engine", Colors.redAccent),
                  const SizedBox(height: 15),
                  _buildGlassContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text("The ",
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                            Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.blueAccent.withOpacity(0.1),
                                    border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                                    borderRadius: BorderRadius.circular(8)),
                                child: const Text("Dockerfile",
                                    style: TextStyle(
                                        color: Colors.blueAccent,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold))),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                            "Silent Hosting empowers developers with full containerized execution. Create a Dockerfile in your root directory to execute commands and setup your environment line by line.",
                            style: TextStyle(color: Colors.white60, height: 1.6, fontSize: 13)),
                        const SizedBox(height: 20),
                        
                        // Code Block
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              border: const Border(left: BorderSide(color: Colors.blueAccent, width: 3)),
                              borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(15), bottomRight: Radius.circular(15))),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _codeLine("# Step 1: Base Image", "FROM python:3.9-slim"),
                              const SizedBox(height: 10),
                              _codeLine("# Step 2: Install dependencies", "RUN apt-get update && apt-get install -y ffmpeg"),
                              const SizedBox(height: 10),
                              _codeLine("# Step 3: Install Python requirements", "RUN pip install -r requirements.txt"),
                              const SizedBox(height: 10),
                              const Divider(color: Colors.white10),
                              const SizedBox(height: 10),
                              const Text("# Step 4: Boot up the main server/bot!",
                                  style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace')),
                              const SizedBox(height: 5),
                              const Row(children: [
                                Icon(Icons.bolt, color: Colors.amber, size: 16),
                                SizedBox(width: 8),
                                Text("CMD [\"python3\", \"main.py\"]",
                                    style: TextStyle(
                                        color: Colors.blueAccent,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace',
                                        fontSize: 14))
                              ]),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),

                  // --- SECTION 3: TECHNOLOGIES ---
                  _buildHeader(Icons.code, "Supported Technologies", const Color(0xFFA855F7)),
                  const SizedBox(height: 15),
                  const Text(
                      "Silent Hosting is a polyglot platform. We natively support almost every major programming language and framework.",
                      style: TextStyle(color: Colors.white60, height: 1.5, fontSize: 14)),
                  const SizedBox(height: 20),
                  
                  // Tech Boxes with Real Logos
                  _buildTechBox("Go (Golang)", "main.go", "go run main.go", const Color(0xFF22D3EE), "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcTkrkIZ8rOBHaRFDJ8yRQRqj6XS0Jp0FEjQ7EUKewT-rw&s=10"),
                  const SizedBox(height: 15),
                  _buildTechBox("Node.js (JS/TS)", "index.js / server.js", "npm start", Colors.greenAccent, "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQ6i9x88O-v_RNLW8lTvwU4Edz7TNHA2cD_qRbgn-MMjw&s=10"),
                  const SizedBox(height: 15),
                  _buildTechBox("Python", "main.py / app.py", "python main.py", Colors.amber, "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSBEmmAyvlkz86eCHXShAiXY_1C0y4VtKjn8s3joUvGkej1c6fq7eB_D4dZ&s=10"),
                  const SizedBox(height: 15),
                  _buildTechBox("Rust", "main.rs", "cargo run", const Color(0xFFF97316), "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQ-qLv8g551q7R2weIFUkEtYMNTRRfJOeD1FDgBwxQl-w&s=10"),
                  const SizedBox(height: 15),
                  _buildTechBox("PHP & Static HTML", "index.php / index.html", "Automatically Served", const Color(0xFF6366F1), "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRnzZWQs0NCZq9QvFFZkxURlGhMud5ThMgZ8ylBdX--wA&s=10"),
                  const SizedBox(height: 15),
                  _buildTechBox("Docker", "Dockerfile", "docker build .", const Color(0xFF3B82F6), "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQ8BmC0UymPUNN3ccgWEXNTd9-cEl5KFyF9f6-G7oyZMg&s=10"),
                  
                  const SizedBox(height: 60),

                  // --- VIP FOOTER ---
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 40),
                  Center(
                    child: Column(
                      children: [
                        Container(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                            decoration: BoxDecoration(
                                color: const Color(0xFFA855F7).withOpacity(0.1),
                                border: Border.all(color: const Color(0xFFA855F7).withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(20)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.favorite_border, color: Color(0xFFA855F7), size: 16),
                              SizedBox(width: 8),
                              Text("PREMIUM CLOUD INFRASTRUCTURE",
                                  style: TextStyle(
                                      color: Color(0xFFA855F7),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2))
                            ])),
                        const SizedBox(height: 20),
                        // Responsive Title
                        Text("SILENT HOSTING PLATFORM",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: isMobile ? 18 : 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 3)),
                        const SizedBox(height: 10),
                        const Text(
                            "Engineered for absolute performance, unyielding security,\nand unrestricted developer freedom.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5)),
                        
                        const SizedBox(height: 40),
                        
                        // Founder Card
                        _buildGlassContainer(
                          child: Column(
                            children: [
                              const Text("DEVELOPED & MAINTAINED BY",
                                  style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10,
                                      letterSpacing: 3,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 15),
                              
                              // Founder Line 1
                              const Text("CO-FOUNDER OF",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 2)),
                              const SizedBox(height: 5),
                              
                              // Founder Line 2
                              const Text("SILENT HACKERS TEAM",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                              
                              const SizedBox(height: 20),
                              
                              // Green Nothing is Impossible
                              const Text("💀 Nothing Is Impossible 💀",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.w900)),
                              
                              const SizedBox(height: 30),
                              const Divider(color: Colors.white10),
                              const SizedBox(height: 20),
                              const Text("CONNECT DIRECTLY",
                                  style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10,
                                      letterSpacing: 3,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 20),
                              
                              // Social Links with Real Logos
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _socialLogoBtn("https://img.icons8.com/?size=100&id=DUEq8l5qTqBE&format=png&color=000000", const Color(0xFF25D366),
                                      () => _openLink("https://wa.me/923027665767")),
                                  const SizedBox(width: 15),
                                  _socialLogoBtn("https://img.icons8.com/?size=100&id=k4jADXhS5U1t&format=png&color=000000", const Color(0xFF0088cc),
                                      () => _openLink("tg://resolve?domain=only_possible")),
                                  const SizedBox(width: 15),
                                  _socialLogoBtn("https://img.icons8.com/?size=100&id=oKHadYScUe2I&format=png&color=000000", Colors.white,
                                      () => _openLink("https://www.tiktok.com/@only_possible")),
                                  const SizedBox(width: 15),
                                  _socialLogoBtn("https://img.icons8.com/?size=100&id=omVNNE6wkyP7&format=png&color=000000", const Color(0xFFFF0000),
                                      () => _openLink("https://www.youtube.com/@only_possible")),
                                ],
                              )
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.copyright, color: Colors.white24, size: 14),
                          SizedBox(width: 5),
                          Text("2026 Silent Hosting. All Rights Reserved.",
                              style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1))
                        ]),
                      ],
                    ),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  // Helper Widgets
  Widget _buildHeader(IconData icon, String title, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Expanded(
            child: Text(title.toUpperCase(),
                style: TextStyle(
                    color: color, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1))),
      ],
    );
  }

  Widget _buildGlassContainer({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: const Color(0xFF45F3FF).withOpacity(0.02),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: const Color(0xFF45F3FF).withOpacity(0.2)),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _RealisticShatterPainterX())), // Shattered Glass Effect
          child,
        ],
      ),
    );
  }

  Widget _buildInfoBox(IconData icon, String title, String desc, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 5),
          Text(desc,
              style: const TextStyle(color: Colors.white54, fontSize: 11, height: 1.5)),
        ],
      ),
    );
  }

  Widget _codeLine(String comment, String code) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(comment,
            style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace')),
        const SizedBox(height: 3),
        Text(code,
            style: const TextStyle(
                color: Color(0xFF34D399),
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                fontSize: 13)),
      ],
    );
  }

  Widget _buildTechBox(String title, String file, String runCmd, Color color, String logoUrl) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Real Logo
          Container(
            width: 45,
            height: 45,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10)),
            child: Image.network(logoUrl, fit: BoxFit.contain, errorBuilder: (c,e,s) => Icon(Icons.code, color: color)),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                RichText(
                    text: TextSpan(
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                        children: [
                      const TextSpan(text: "Entry File: "),
                      TextSpan(
                          text: file,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                    ])),
                const SizedBox(height: 4),
                RichText(
                    text: TextSpan(
                        style: const TextStyle(color: Colors.white60, fontSize: 11),
                        children: [
                      const TextSpan(text: "Command: "),
                      TextSpan(text: runCmd, style: TextStyle(color: color, fontFamily: 'monospace'))
                    ])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _socialLogoBtn(String logoUrl, Color brandColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 45,
        height: 45,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            border: Border.all(color: brandColor.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(12)),
        child: Image.network(logoUrl, fit: BoxFit.contain, errorBuilder: (c,e,s) => const Icon(Icons.link, color: Colors.white)),
      ),
    );
  }
}

// ============================================================================
// --- INDEPENDENT UI PAINTERS & WIDGETS ---
// ============================================================================

class LiveCyberBackgroundX extends StatefulWidget {
  const LiveCyberBackgroundX({Key? key}) : super(key: key);
  @override
  _LiveCyberBackgroundXState createState() => _LiveCyberBackgroundXState();
}

class _LiveCyberBackgroundXState extends State<LiveCyberBackgroundX> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _DiagonalWavePainterX(_c.value)));
}

class _DiagonalWavePainterX extends CustomPainter {
  final double progress;
  _DiagonalWavePainterX(this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF45F3FF).withOpacity(0.03)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    double offset = progress * 100;
    for (double i = -size.height; i < size.width + size.height; i += 40) {
      canvas.drawLine(Offset(i + offset, 0), Offset(i - size.height + offset, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

class _RealisticShatterPainterX extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (int i = 0; i < 10; i++) {
      double cx = Random(i).nextDouble() * size.width;
      double cy = Random(i + 1).nextDouble() * size.height;
      for (int j = 0; j < 5; j++) {
        double a = (j * 45) * (pi / 180);
        path.moveTo(cx, cy);
        path.lineTo(cx + cos(a) * 30, cy + sin(a) * 30);
      }
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(CustomPainter old) => false;
}