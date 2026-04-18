import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import 'config.dart';
import 'login_page.dart';
import 'edit_profile_page.dart';

class ProfilePage extends StatefulWidget {
  final Map<String, dynamic>? tenantData;
  const ProfilePage({super.key, this.tenantData});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // 🎨 Palette สี: Vanilla Bean & Teddy Bear
  static const Color cVanilla   = Color(0xFFF4EFE6); // พื้นหลังนวล
  static const Color cTeddy     = Color(0xFF523D2D); // น้ำตาลเข้ม Teddy
  static const Color cBrown     = Color(0xFF8D7456); // น้ำตาลกลางสำหรับ Icon
  static const Color cCard      = Color(0xFFFFFFFF);
  static const Color cTextMain  = Color(0xFF523D2D);

  // 📏 Typography System
  static const double fHeader  = 18.0; // หัวข้อใหญ่
  static const double fTitle   = 15.0; // หัวข้อย่อย
  static const double fBody    = 13.0; // เนื้อหา
  static const double fCaption = 11.0;

  bool _loading = true;
  bool _isAdminViewing = false;

  String username = "";
  String fullName = "ไม่มีข้อมูล";
  String phone = "ไม่มีข้อมูล";
  String dormName = "";
  String roleInDorm = "tenant";
  String roomText = "ยังไม่ได้รับการจัดห้อง";
  String moveInDate = "-";
  int _targetUserId = 0;

  // ตรวจสอบว่าเป็นผู้ดูแลหรือไม่
  bool get isDormAdmin => roleInDorm == "owner" || roleInDorm == "admin";

  @override
  void initState() {
    super.initState();
    _isAdminViewing = widget.tenantData != null;
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      if (_isAdminViewing) {
        final t = widget.tenantData!;
        _applyTenantData(t);
        _targetUserId = _toInt(t["user_id"] ?? t["id"]);
      } else {
        final prefs = await SharedPreferences.getInstance();
        _targetUserId = prefs.getInt("user_id") ?? 0;
      }

      if (_targetUserId == 0) return;

      final res = await http.post(
        Uri.parse(AppConfig.url("profile.php")),
        body: {"action": "get", "user_id": _targetUserId.toString()},
      );

      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        final profileData = data["data"] is Map<String, dynamic>
            ? Map<String, dynamic>.from(data["data"])
            : Map<String, dynamic>.from(data);

        setState(() => _applyTenantData(profileData));
      }
    } catch (e) {
      debugPrint("ERROR: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyTenantData(Map<String, dynamic> t) {
    fullName = t["full_name"]?.toString() ?? "ไม่มีข้อมูล";
    phone = t["phone"]?.toString() ?? "ไม่มีข้อมูล";
    username = t["username"]?.toString() ?? "";
    dormName = t["dorm_name"]?.toString() ?? "";
    roleInDorm = t["role_in_dorm"]?.toString() ?? "tenant";

    final rNo = t["room_number"]?.toString().trim() ?? "";
    final building = (t["building"]?.toString().trim().isNotEmpty == true)
        ? t["building"].toString().trim()
        : (t["building_name"]?.toString().trim() ?? "");

    if (rNo.isNotEmpty && building.isNotEmpty) {
      roomText = "$building / ห้อง $rNo";
    } else if (rNo.isNotEmpty) {
      roomText = rNo;
    } else {
      roomText = "ยังไม่ได้รับการจัดห้อง";
    }

    moveInDate = t["move_in_date"]?.toString() ?? "-";
  }

  int _toInt(dynamic v) => int.tryParse(v?.toString() ?? "") ?? 0;

  Future<void> _showRemoveConfirm() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Colors.redAccent,
                  size: 45,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "ยืนยันการออก",
                style: GoogleFonts.kanit(
                  fontSize: fHeader,
                  fontWeight: FontWeight.w600,
                  color: cTextMain,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "คุณต้องการให้คุณ $fullName\nออกจากหอพักใช่หรือไม่?",
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(fontSize: fBody, color: Colors.grey),
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cTeddy,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        "ยืนยัน",
                        style: GoogleFonts.kanit(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFDCD2C1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        "กลับ",
                        style: GoogleFonts.kanit(
                          color: cTextMain,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirm == true) _processRemoveTenant();
  }

  Future<void> _processRemoveTenant() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final dormId = prefs.getInt("dorm_id") ?? 0;

      final res = await http.post(
        Uri.parse(AppConfig.url("tenants_api.php")),
        body: {
          "action": "remove",
          "dorm_id": dormId.toString(),
          "user_id": _targetUserId.toString(),
        },
      );
      final data = jsonDecode(res.body);
      if (data["ok"] == true || data["success"] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("ดำเนินการเรียบร้อยแล้ว ✅", style: GoogleFonts.kanit()),
              behavior: SnackBarBehavior.floating,
              backgroundColor: cTeddy,
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("เกิดข้อผิดพลาด")),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cVanilla, 
      appBar: _isAdminViewing
          ? AppBar(
              backgroundColor: Colors.white,
              elevation: 0.5,
              centerTitle: true,
              title: Text(
                "ข้อมูลผู้เช่า",
                style: GoogleFonts.kanit(
                  color: cTextMain,
                  fontWeight: FontWeight.w600,
                  fontSize: fHeader,
                ),
              ),
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: cTextMain,
                  size: 18,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: cTeddy))
            : RefreshIndicator(
                onRefresh: _fetchProfile,
                color: cTeddy,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
                  child: Column(
                    children: [
                      _avatar(),
                      const SizedBox(height: 16),
                      Text(
                        fullName,
                        style: GoogleFonts.kanit(
                          fontSize: fHeader,
                          fontWeight: FontWeight.w600,
                          color: cTextMain,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildRoleBadge(),
                      const SizedBox(height: 30),
                      _section("ข้อมูลส่วนตัว"),
                      _info(Icons.account_circle_outlined, "username", username),
                      _info(Icons.person_outline, "ชื่อ - นามสกุล", fullName),
                      _info(Icons.phone_android_outlined, "เบอร์โทรศัพท์", phone),
                      const SizedBox(height: 25),
                      _section(isDormAdmin ? "ข้อมูลหอพัก" : "รายละเอียดห้องพัก"),
                      _info(
                        Icons.apartment_rounded,
                        "ชื่อหอพัก",
                        dormName.isEmpty ? "ไม่มีข้อมูล" : dormName,
                      ),
                      if (!isDormAdmin)
                        _info(
                          Icons.meeting_room_outlined,
                          "เลขห้องพัก",
                          roomText,
                        ),

                      const SizedBox(height: 40),
                      if (_isAdminViewing) _removeTenantBtn() else _logoutBtn(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _removeTenantBtn() => SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _showRemoveConfirm,
          icon: const Icon(Icons.exit_to_app_rounded, size: 18),
          label: Text(
            "ให้ออกจากหอพัก",
            style: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: fTitle),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );

  Widget _buildRoleBadge() {
    final bool isAdmin = isDormAdmin;
    final Color badgeColor = isAdmin ? cTeddy : const Color(0xFF2E7D32);
    final Color bgColor    = isAdmin ? const Color(0xFFDCD2C1).withOpacity(0.5) : const Color(0xFFE8F5E9);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAdmin ? Icons.admin_panel_settings : Icons.person_pin_rounded,
            size: 14,
            color: badgeColor,
          ),
          const SizedBox(width: 6),
          Text(
            isAdmin ? "ผู้ดูแลหอพัก" : "ผู้เช่าหอพัก",
            style: GoogleFonts.kanit(
              fontSize: fCaption,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar() => Stack(
        alignment: Alignment.bottomRight,
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: const Color(0xFFDCD2C1),
            child: Icon(
              isDormAdmin
                  ? Icons.admin_panel_settings_outlined
                  : Icons.person_rounded,
              size: 55,
              color: cTeddy,
            ),
          ),
          if (!_isAdminViewing)
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditProfilePage(
                    username: username,
                    fullName: fullName,
                    phone: phone,
                  ),
                ),
              ).then((_) => _fetchProfile()),
              child: const CircleAvatar(
                radius: 16,
                backgroundColor: cTeddy,
                child: Icon(Icons.edit, color: Colors.white, size: 16),
              ),
            ),
        ],
      );

  Widget _section(String t) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 4),
          child: Text(
            t,
            style: GoogleFonts.kanit(
              fontSize: fTitle,
              fontWeight: FontWeight.w600,
              color: cTextMain,
            ),
          ),
        ),
      );

  Widget _info(IconData i, String l, String v) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: cCard,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: cTeddy.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            Icon(i, color: cBrown, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l,
                    style: GoogleFonts.kanit(
                      fontSize: fCaption,
                      color: cTeddy.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    v,
                    style: GoogleFonts.kanit(
                      fontSize: fBody,
                      fontWeight: FontWeight.w600,
                      color: cTextMain,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _logoutBtn() => SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout_rounded, size: 18),
          label: Text(
            "ออกจากระบบ",
            style: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: fTitle),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: cTeddy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
}