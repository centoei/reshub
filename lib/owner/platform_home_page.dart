import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../login_page.dart'; 
import '../edit_profile_page.dart';
import 'platform_add_dorm_page.dart';
import 'platform_dorm_list_page.dart';
import 'platform_dashboard_page.dart';
import 'platform_user_list_page.dart';

class PlatformHomePage extends StatefulWidget {
  const PlatformHomePage({super.key});

  @override
  State<PlatformHomePage> createState() => _PlatformHomePageState();
}

class _PlatformHomePageState extends State<PlatformHomePage> {
  bool _checking = true;
  String _fullName = "กำลังโหลด...";
  String _username = "";
  String _phone = "";

  // 🎨 Palette สีใหม่: สดใสและคมชัด (Deep Coffee & Cream)
  static const Color cBg = Color(0xFFF4EFE6);       // ครีมสว่าง
  static const Color cAccent = Color(0xFFDCD2C1);   // ครีมเข้ม
  static const Color cTextMain = Color(0xFF2A1F17); // น้ำตาลเข้มจัด (คมชัด)
  static const Color cDark = Color(0xFF523D2D);     // น้ำตาลไอคอน

  // 📏 Typography System
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle  = 15.0; // หัวข้อย่อย
  static const double fBody   = 13.0; // เนื้อหา

  @override
  void initState() {
    super.initState();
    _guard();
  }

  Future<void> _guard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final platformRole = prefs.getString("platform_role") ?? "user";
      
      if (platformRole != "platform_admin") {
        _logout();
        return;
      }

      setState(() {
        _fullName = prefs.getString("full_name") ?? "Platform Admin";
        _username = prefs.getString("username") ?? "admin";
        _phone = prefs.getString("phone") ?? "";
        _checking = false;
      });
    } catch (e) {
      setState(() => _checking = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  void _goToEditProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfilePage(
          username: _username,
          fullName: _fullName,
          phone: _phone,
        ),
      ),
    );

    if (result != null && result['ok'] == true) {
      _guard();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: cBg,
        body: Center(child: CircularProgressIndicator(color: cDark)),
      );
    }

    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        child: Column(
          children: [
            // --- 🏠 Header Card (ข้อมูล + ปุ่มแบบแบ่ง 2 ฝั่ง) ---
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: _buildWelcomeCard(),
            ),

            // --- ส่วนเนื้อหา Menu Grid ---
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 18,
                      crossAxisSpacing: 18,
                      childAspectRatio: 0.95,
                      children: [
                        _buildMenu(
                          context,
                          icon: Icons.apartment_rounded,
                          title: "จัดการหอพัก",
                          subtitle: "ดูรายชื่อหอทั้งหมด",
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlatformDormListPage())),
                        ),
                        _buildMenu(
                          context,
                          icon: Icons.analytics_rounded,
                          title: "สรุปภาพรวม",
                          subtitle: "วิเคราะห์ข้อมูล",
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlatformDashboardPage())),
                        ),
                        _buildMenu(
                          context,
                          icon: Icons.add_business_rounded,
                          title: "เพิ่มหอพัก",
                          subtitle: "ลงทะเบียนหอใหม่",
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlatformAddDormPage())),
                        ),
                        _buildMenu(
                          context,
                          icon: Icons.people_alt_rounded,
                          title: "รายชื่อผู้ใช้งาน",
                          subtitle: "จัดการผู้ใช้ทั้งหมด",
                          onTap: () {
                            Navigator.push(
                              context, 
                              MaterialPageRoute(builder: (_) => const PlatformUserListPage())
                            );
                          }, 
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cTextMain, // สีน้ำตาลเข้มจัด
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Column(
          children: [
            // ส่วนข้อมูลโปรไฟล์
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: cAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cAccent.withOpacity(0.3), width: 1.5),
                    ),
                    child: const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFDCD2C1), size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "PLATFORM ADMIN",
                          style: GoogleFonts.kanit(color: const Color(0xFFDCD2C1), fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fullName,
                          style: GoogleFonts.kanit(
                            color: Colors.white,
                            fontSize: fHeader,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // ส่วนปุ่มกด 2 ฝั่ง (แก้ไขโปรไฟล์ | ออกจากระบบ)
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1611), // สีน้ำตาลเกือบดำ
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _goToEditProfile,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.manage_accounts_rounded, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text("ตั้งค่าบัญชี", style: GoogleFonts.kanit(color: Colors.white, fontSize: fBody, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    VerticalDivider(width: 1, indent: 15, endIndent: 15, color: Colors.white.withOpacity(0.1)),
                    Expanded(
                      child: InkWell(
                        onTap: _logout,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.power_settings_new_rounded, color: Color(0xFFFF8A8A), size: 18),
                              const SizedBox(width: 8),
                              Text(
                                "ลงชื่อออก", 
                                style: GoogleFonts.kanit(color: const Color(0xFFFF8A8A), fontSize: fBody, fontWeight: FontWeight.w600)
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context, {required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: cBg, borderRadius: BorderRadius.circular(20)),
                child: Icon(icon, size: 30, color: cDark),
              ),
              const SizedBox(height: 12),
              Text(title, style: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: fTitle, color: cTextMain)),
              const SizedBox(height: 4),
              Text(subtitle, style: GoogleFonts.kanit(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }
}