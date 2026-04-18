import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isObscured = true, _isLoading = false;
  final TextEditingController emailCtrl = TextEditingController(), passCtrl = TextEditingController();

  // 🎨 Palette ของคุณ: Vanilla Bean & Teddy Bear
  static const Color cVanilla = Color(0xFFF4EFE6); // พื้นหลังหลัก
  static const Color cTeddy   = Color(0xFF523D2D); // สีน้ำตาลเข้มสำหรับเน้น
  static const Color cWhite   = Colors.white;

  // 📏 Micro Typography
  static const double fTitle = 22.0;
  static const double fBody = 13.0;
  static const double fCaption = 11.0;

  @override
  void initState() {
    super.initState();
    _autoRedirectIfLoggedIn();
  }

  // --- LOGIC SECTION ---

  int _toInt(dynamic v) => v == null ? 0 : (v is int ? v : int.tryParse(v.toString()) ?? 0);

  Future<void> _goNext({required String platformRole, required String roleInDorm, required String approveStatus}) async {
    if (!mounted) return;
    if (platformRole == "platform_admin") {
      Navigator.pushReplacementNamed(context, "/platform");
      return;
    }
    if (approveStatus != "approved") {
      Navigator.pushReplacementNamed(context, "/pending");
      return;
    }
    if (roleInDorm == "owner" || roleInDorm == "admin") {
      Navigator.pushReplacementNamed(context, "/admin");
      return;
    }
    Navigator.pushReplacementNamed(context, "/home");
  }

  Future<void> _autoRedirectIfLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool("isLogin") ?? false)) return;
    await _goNext(
      platformRole: prefs.getString("platform_role") ?? "user",
      roleInDorm: prefs.getString("role_in_dorm") ?? "tenant",
      approveStatus: prefs.getString("approve_status") ?? "approved",
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final res = await http.post(Uri.parse(AppConfig.url("login.php")), body: {
        "username": emailCtrl.text.trim(),
        "password": passCtrl.text,
      }).timeout(const Duration(seconds: 12));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data["success"] == true) {
        final user = data["user"];
        final prefs = await SharedPreferences.getInstance();

        await prefs.setInt("user_id", _toInt(user["user_id"]));
        await prefs.setString("full_name", user["full_name"] ?? "");
        await prefs.setString("username", user["username"] ?? "");
        await prefs.setInt("dorm_id", _toInt(user["dorm_id"]));
        await prefs.setString("platform_role", user["platform_role"] ?? "user");
        await prefs.setString("role_in_dorm", user["role_in_dorm"] ?? "tenant");
        await prefs.setString("approve_status", user["approve_status"] ?? "pending");
        await prefs.setBool("isLogin", true);

        _goNext(
          platformRole: user["platform_role"],
          roleInDorm: user["role_in_dorm"],
          approveStatus: user["approve_status"],
        );
      } else {
        _snack(data["message"] ?? "เข้าสู่ระบบไม่สำเร็จ");
      }
    } catch (e) {
      _snack("เชื่อมต่อไม่ได้: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: fBody, color: cVanilla)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: cTeddy,
    ));
  }

  // ✅ UI Style Helper (Updated with Teddy & Vanilla)
  InputDecoration _buildInputStyle(String label, IconData icon, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: cTeddy.withOpacity(0.6), fontSize: fBody),
      prefixIcon: Icon(icon, color: cTeddy, size: 18),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: cWhite.withOpacity(0.9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: cTeddy.withOpacity(0.1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: cTeddy, width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cVanilla, // พื้นหลังหลักสีนวล
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cWhite.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: cTeddy.withOpacity(0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo
                  Image.asset("assets/images/RHLogo.png",
                      width: 80, height: 80, fit: BoxFit.contain,
                      errorBuilder: (c, e, s) => const Icon(Icons.home_rounded, size: 60, color: cTeddy)),

                  const SizedBox(height: 12),
                  const Text("RESHUB",
                      style: TextStyle(fontSize: fTitle, fontWeight: FontWeight.w900, color: cTeddy, letterSpacing: 1.0)),
                  Text("เข้าสู่ระบบเพื่อใช้งาน",
                      style: TextStyle(color: cTeddy.withOpacity(0.7), fontSize: fCaption)),

                  const SizedBox(height: 20),
                  // Username Field
                  TextFormField(
                    controller: emailCtrl,
                    style: const TextStyle(fontSize: fBody, color: cTeddy),
                    decoration: _buildInputStyle('Username', Icons.person_outline_rounded),
                    validator: (v) => v!.isEmpty ? 'กรุณากรอกข้อมูล' : null,
                  ),
                  const SizedBox(height: 12),
                  // Password Field
                  TextFormField(
                    controller: passCtrl,
                    obscureText: _isObscured,
                    style: const TextStyle(fontSize: fBody, color: cTeddy),
                    decoration: _buildInputStyle('รหัสผ่าน', Icons.lock_outline_rounded,
                        suffixIcon: IconButton(
                            icon: Icon(_isObscured ? Icons.visibility_off : Icons.visibility, color: cTeddy, size: 18),
                            onPressed: () => setState(() => _isObscured = !_isObscured))),
                    validator: (v) => v!.isEmpty ? 'กรุณากรอกรหัสผ่าน' : null,
                  ),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/forgot-password'),
                      child: const Text("ลืมรหัสผ่าน?",
                          style: TextStyle(fontSize: fCaption, fontWeight: FontWeight.bold, color: cTeddy)),
                    ),
                  ),

                  const SizedBox(height: 8),
                  // Login Button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: cTeddy,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0),
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: cVanilla, strokeWidth: 2))
                          : const Text("เข้าสู่ระบบ", style: TextStyle(fontSize: 16, color: cVanilla, fontWeight: FontWeight.bold)),
                    ),
                  ),

                  const SizedBox(height: 12),
                  // Register Link
                  TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/register'),
                    child: const Text("สมัครสมาชิก",
                        style: TextStyle(fontSize: fCaption, fontWeight: FontWeight.bold, color: cTeddy)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}