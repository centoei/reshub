import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import '../config.dart';

class PlatformDashboardPage extends StatefulWidget {
  const PlatformDashboardPage({super.key});

  @override
  State<PlatformDashboardPage> createState() => _PlatformDashboardPageState();
}

class _PlatformDashboardPageState extends State<PlatformDashboardPage> {
  bool loading = true;

  int totalDorms = 0;
  int totalUsers = 0;

  int activeDorms = 0;
  int suspendedDorms = 0;

  // 🎨 Palette ใหม่: สดใสและคมชัด (Deep Coffee & Cream)
  static const Color cBg = Color(0xFFF4EFE6);       // ครีมสว่าง
  static const Color cAccent = Color(0xFFDCD2C1);   // ครีมเข้ม
  static const Color cTextMain = Color(0xFF2A1F17); // น้ำตาลเข้มจัด (คมชัด)
  static const Color cDark = Color(0xFF523D2D);     // น้ำตาลไอคอน

  // 📏 Typography System ตามที่กำหนด
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle  = 15.0; // หัวข้อย่อย
  static const double fBody   = 13.0; // เนื้อหา

  @override
  void initState() {
    super.initState();
    fetchDashboard();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.kanit(fontSize: fBody, fontWeight: FontWeight.normal)), 
        backgroundColor: cTextMain,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> fetchDashboard() async {
    if (!mounted) return;
    setState(() => loading = true);

    try {
      final url = Uri.parse("${AppConfig.baseUrl}/platform_api.php");
      final res = await http.post(url, body: {
        "action": "dashboard",
      }).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);

      if (!mounted) return;

      if (res.statusCode == 200 && data["success"] == true) {
        final m = Map<String, dynamic>.from(data["data"] ?? {});
        final ds = Map<String, dynamic>.from(m["dorm_status"] ?? {});

        setState(() {
          totalDorms = int.tryParse((m["total_dorms"] ?? "0").toString()) ?? 0;
          totalUsers = int.tryParse((m["total_users"] ?? "0").toString()) ?? 0;
          activeDorms = int.tryParse((ds["active"] ?? "0").toString()) ?? 0;
          suspendedDorms = int.tryParse((ds["suspended"] ?? "0").toString()) ?? 0;
        });
      }
    } catch (e) {
      _snack("เชื่อมต่อไม่ได้: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        toolbarHeight: 60, 
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: cTextMain),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "สรุปภาพรวมระบบ",
          style: GoogleFonts.kanit(fontWeight: FontWeight.w600, color: cTextMain, fontSize: fHeader),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: cDark))
                : RefreshIndicator(
                    onRefresh: fetchDashboard,
                    color: cDark,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // 📊 การ์ดสรุปตัวเลขหลัก
                          _bigCard(
                            icon: Icons.apartment_rounded,
                            title: "หอพักทั้งหมด",
                            value: "$totalDorms",
                            hint: "หอพักที่ลงทะเบียนไว้ในระบบ",
                            color: const Color(0xFF1565C0), // น้ำเงินเข้ม
                          ),
                          const SizedBox(height: 16),
                          _bigCard(
                            icon: Icons.people_alt_rounded,
                            title: "ผู้ใช้งานรวม",
                            value: "$totalUsers",
                            hint: "บัญชีผู้ใช้ทั้งหมดในระบบ",
                            color: const Color(0xFF5D4037), // น้ำตาลไหม้
                          ),
                          const SizedBox(height: 24),

                          // 📊 กราฟสถานะหอพัก
                          _buildStatusBreakdown(),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _bigCard({
    required IconData icon,
    required String title,
    required String value,
    required String hint,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 6))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: fTitle, color: cTextMain, letterSpacing: 0.3)),
                const SizedBox(height: 4),
                Text(hint, style: GoogleFonts.kanit(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.normal)),
              ],
            ),
          ),
          Text(value, style: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: 32, color: cTextMain, letterSpacing: -1)),
        ],
      ),
    );
  }

  Widget _buildStatusBreakdown() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: cAccent.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.donut_large_rounded, size: 20, color: cDark),
              const SizedBox(width: 10),
              Text(
                "สถานะหอพักในระบบ",
                style: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: fTitle, color: cTextMain, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 30),
          _statusRow("active", activeDorms, totalDorms, const Color(0xFF2E7D32)), // เขียว
          const SizedBox(height: 24),
          _statusRow("suspended", suspendedDorms, totalDorms, const Color(0xFFD32F2F)), // แดง
        ],
      ),
    );
  }

  Widget _statusRow(String status, int count, int total, Color color) {
    final double p = (total <= 0) ? 0 : (count / total).clamp(0, 1);
    final String label = status == "active" ? "เปิดใช้งานอยู่" : "ปิดการใช้งาน";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(label, style: GoogleFonts.kanit(fontWeight: FontWeight.normal, fontSize: fBody, color: cTextMain)),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: "$count", style: GoogleFonts.kanit(fontWeight: FontWeight.w600, color: color, fontSize: 20)),
                  const TextSpan(text: "  "),
                  TextSpan(text: "หอพัก", style: GoogleFonts.kanit(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.normal)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 14,
          width: double.infinity,
          decoration: BoxDecoration(
            color: cBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOutQuart,
                width: (MediaQuery.of(context).size.width - 88) * p,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}