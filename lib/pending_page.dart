import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import 'config.dart';

class PendingPage extends StatefulWidget {
  const PendingPage({super.key});

  @override
  State<PendingPage> createState() => _PendingPageState();
}

class _PendingPageState extends State<PendingPage> {
  // 🎨 Palette สี: Vanilla Bean & Teddy Bear
  static const Color cVanilla  = Color(0xFFF4EFE6); // พื้นหลังนวล
  static const Color cTeddy    = Color(0xFF523D2D); // น้ำตาลเข้ม Teddy
  static const Color cBrown    = Color(0xFF8D7456); // น้ำตาลกลาง
  static const Color cWhite    = Colors.white;

  // 📏 Typography System
  static const double fHeader  = 18.0; // หัวข้อใหญ่
  static const double fTitle   = 15.0; // หัวข้อย่อย
  static const double fBody    = 13.0; // เนื้อหา
  static const double fCaption = 12.0;

  Timer? _timer;
  bool _loading = false;
  String _msg = "กำลังรอแอดมินอนุมัติ...";

  @override
  void initState() {
    super.initState();
    _checkOnce();
    // ✅ เช็คอัตโนมัติทุก 5 วิ
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkOnce());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkOnce() async {
    if (_loading) return;

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt("user_id") ?? 0;

    if (userId == 0) {
      if (!mounted) return;
      setState(() => _msg = "ไม่พบข้อมูลผู้ใช้ กรุณาเข้าสู่ระบบใหม่");
      return;
    }

    setState(() => _loading = true);

    try {
      final url = Uri.parse(AppConfig.url("check_status.php"));
      final res = await http
          .post(url, body: {"user_id": userId.toString()})
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);

      if (!mounted) return;

      if (res.statusCode == 200 && data["success"] == true) {
        final user = Map<String, dynamic>.from(data["user"] ?? {});
        final platformRole = (user["platform_role"] ?? "user").toString();
        final roleInDorm = (user["role_in_dorm"] ?? "tenant").toString();
        final approveStatus = (user["approve_status"] ?? "pending").toString();

        if (approveStatus == "approved") {
          await prefs.setBool("isLogin", true);
          await prefs.setString("username", (user["username"] ?? "").toString());
          await prefs.setString("full_name", (user["full_name"] ?? "").toString());
          await prefs.setString("platform_role", platformRole);
          await prefs.setString("role_in_dorm", roleInDorm);
          await prefs.setString("approve_status", approveStatus);
          await prefs.setInt("dorm_id", int.tryParse(user["dorm_id"].toString()) ?? 0);

          _timer?.cancel();

          if (platformRole == "platform_admin") {
            Navigator.pushNamedAndRemoveUntil(context, "/platform", (r) => false);
          } else if (roleInDorm == "owner" || roleInDorm == "admin") {
            Navigator.pushNamedAndRemoveUntil(context, "/admin", (r) => false);
          } else {
            Navigator.pushNamedAndRemoveUntil(context, "/home", (r) => false);
          }
          return;
        }

        setState(() {
          _msg = "ยังรออนุมัติอยู่... (เช็คอัตโนมัติทุก 5 วินาที)";
        });
      } else {
        setState(() => _msg = data["message"]?.toString() ?? "เช็คสถานะไม่สำเร็จ");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _msg = "เชื่อมต่อไม่ได้: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _backToLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, "/", (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cVanilla, // พื้นหลังครีมนวล
      appBar: AppBar(
        title: Text("ตรวจสอบสถานะ", 
          style: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: fHeader)),
        backgroundColor: cWhite,
        foregroundColor: cTeddy,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon อนิเมชั่นเบาๆ ด้วยเงา
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cWhite.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.hourglass_top_rounded, size: 80, color: cBrown),
            ),
            const SizedBox(height: 30),
            
            Text(
              "กำลังรอการอนุมัติ",
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(
                fontSize: fHeader, 
                fontWeight: FontWeight.w600, 
                color: cTeddy,
                letterSpacing: 0.5
              ),
            ),
            const SizedBox(height: 12),
            
            Text(
              _msg,
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(
                color: cTeddy.withOpacity(0.6), 
                fontSize: fBody,
                height: 1.5
              ),
            ),
            const SizedBox(height: 40),

            // ปุ่มเช็คสถานะ (Teddy Style)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _checkOnce,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cTeddy,
                  foregroundColor: cVanilla,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: cVanilla, strokeWidth: 2),
                      )
                    : Text("เช็คสถานะอีกครั้ง", 
                        style: GoogleFonts.kanit(fontSize: fTitle, fontWeight: FontWeight.w600)),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // ปุ่มกลับ (Outlined Teddy)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: _backToLogin,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: cTeddy, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                ),
                child: Text(
                  "กลับไปหน้าเข้าสู่ระบบ",
                  style: GoogleFonts.kanit(fontSize: fTitle, color: cTeddy, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            Text(
              "หากรอนานเกินไป กรุณาติดต่อเจ้าหน้าที่หอพัก",
              style: GoogleFonts.kanit(color: cTeddy.withOpacity(0.4), fontSize: fCaption),
            ),
          ],
        ),
      ),
    );
  }
}