import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // 🎨 Palette - Vanilla Bean & Teddy Bear
  static const Color cVanilla = Color(0xFFF4EFE6); // พื้นหลังหลักสีนวล
  static const Color cTeddy   = Color(0xFF523D2D); // น้ำตาลเข้ม Teddy
  static const Color cBrown   = Color(0xFF8D7456); // น้ำตาลกลางสำหรับ Icon/Label
  static const Color cDark    = Color(0xFF523D2D);

  // 📏 Typography System
  static const double fHeader  = 18.0; // หัวข้อใหญ่
  static const double fTitle   = 15.0; // หัวข้อย่อย
  static const double fBody    = 13.0; // เนื้อหา
  static const double fCaption = 11.0;

  final _formKey = GlobalKey<FormState>();
  final fullNameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final userCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  final dormCodeCtrl = TextEditingController();

  bool loading = false;
  bool obscure1 = true;
  bool obscure2 = true;

  String? serverUserError;
  String? serverDormError;

  @override
  void dispose() {
    fullNameCtrl.dispose();
    phoneCtrl.dispose();
    userCtrl.dispose();
    passCtrl.dispose();
    confirmCtrl.dispose();
    dormCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (loading) return;
    
    setState(() {
      serverUserError = null;
      serverDormError = null;
    });

    if (!_formKey.currentState!.validate()) return;
    
    setState(() => loading = true);

    try {
      final uri = Uri.parse("${AppConfig.baseUrl}/register.php");
      final res = await http.post(uri, body: {
        "full_name": fullNameCtrl.text.trim(),
        "phone": phoneCtrl.text.trim(),
        "username": userCtrl.text.trim(),
        "password": passCtrl.text.trim(),
        "dorm_code": dormCodeCtrl.text.trim(),
      }).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      if (!mounted) return;

      if (res.statusCode == 200 && data["success"] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt("user_id", int.tryParse(data["user_id"].toString()) ?? 0);
        await prefs.setString("approve_status", "pending"); 
        
        Navigator.pushNamedAndRemoveUntil(context, "/pending", (r) => false);
      } else {
        final msg = data["message"]?.toString() ?? "";
        setState(() {
          if (msg.contains("Username")) {
            serverUserError = "ชื่อผู้ใช้นี้ถูกใช้งานแล้ว";
          } else if (msg.contains("หอพัก")) serverDormError = "โค้ดหอพักไม่ถูกต้อง";
        });
        _formKey.currentState!.validate();
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [cVanilla, Color(0xFFE8DFD0)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: cTeddy, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: 360,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: cTeddy.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("สร้างบัญชี", 
                            style: GoogleFonts.kanit(fontSize: fHeader, fontWeight: FontWeight.w600, color: cTeddy, letterSpacing: 1.0)
                          ),
                          Text("กรอกข้อมูลเพื่อลงทะเบียนผู้เช่า", 
                            style: GoogleFonts.kanit(color: cTeddy.withOpacity(0.7), fontSize: fCaption)
                          ),
                          const SizedBox(height: 20),

                          _sectionLabel("ข้อมูลส่วนตัว"),
                          _field(fullNameCtrl, "ชื่อ-นามสกุล", Icons.person_outline),
                          const SizedBox(height: 10),
                          _field(phoneCtrl, "เบอร์โทร", Icons.phone_android_outlined, keyboardType: TextInputType.phone),
                          const SizedBox(height: 10),
                          _field(dormCodeCtrl, "โค้ดหอพัก", Icons.apartment_outlined, sErr: serverDormError),
                          
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Divider(color: Colors.black12, height: 1),
                          ),
                          
                          _sectionLabel("ข้อมูลบัญชี"),
                          _field(userCtrl, "Username", Icons.alternate_email, sErr: serverUserError),
                          const SizedBox(height: 10),
                          _field(
                            passCtrl, "รหัสผ่าน", Icons.lock_outline,
                            isPass: true,
                            obs: obscure1,
                            toggle: () => setState(() => obscure1 = !obscure1),
                          ),
                          const SizedBox(height: 10),
                          _field(
                            confirmCtrl, "ยืนยันรหัสผ่าน", Icons.lock_reset,
                            isPass: true,
                            obs: obscure2,
                            toggle: () => setState(() => obscure2 = !obscure2),
                          ),

                          const SizedBox(height: 24),
                          
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton(
                              onPressed: loading ? null : _register,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: cTeddy,
                                foregroundColor: cVanilla,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: loading
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: cVanilla, strokeWidth: 2))
                                  : Text("สมัครสมาชิก", style: GoogleFonts.kanit(fontSize: 16, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: GoogleFonts.kanit(fontSize: fTitle, fontWeight: FontWeight.w600, color: cBrown)),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl, 
    String label, 
    IconData icon, 
    {bool isPass = false, bool obs = false, VoidCallback? toggle, TextInputType keyboardType = TextInputType.text, String? sErr}
  ) {
    return TextFormField(
      controller: ctrl,
      obscureText: obs,
      keyboardType: keyboardType,
      onChanged: (v) {
        if (sErr != null || serverUserError != null || serverDormError != null) {
          setState(() {
            serverUserError = null;
            serverDormError = null;
          });
        }
      },
      style: GoogleFonts.kanit(fontSize: fBody, color: cTeddy, fontWeight: FontWeight.normal),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.kanit(color: cTeddy.withOpacity(0.6), fontSize: fBody),
        errorText: sErr, 
        errorStyle: GoogleFonts.kanit(fontSize: 10, color: Colors.redAccent),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.redAccent, width: 1.5)),
        
        helperText: (label == "รหัสผ่าน") ? "8 ตัวขึ้นไป (ต้องมีตัวอักษรและตัวเลข)" : null,
        helperStyle: GoogleFonts.kanit(fontSize: 9, color: cBrown),
        prefixIcon: Icon(icon, color: cBrown, size: 18),
        suffixIcon: isPass ? IconButton(icon: Icon(obs ? Icons.visibility_off : Icons.visibility, color: cBrown, size: 18), onPressed: toggle) : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: cTeddy, width: 1.5)),
      ),
      validator: (v) {
        final val = v?.trim() ?? "";
        if (val.isEmpty) return "กรุณากรอก$label";
        if (label == "Username" && val.length < 6) return "อย่างน้อย 6 ตัวอักษร";
        if (label == "รหัสผ่าน") {
          if (val.length < 8) return "อย่างน้อย 8 ตัวอักษร";
          if (!RegExp(r'^(?=.*[A-Za-z])(?=.*\d)').hasMatch(val)) return "ต้องมีตัวอักษรและตัวเลข";
        }
        if (label == "ยืนยันรหัสผ่าน" && val != passCtrl.text) return "รหัสผ่านไม่ตรงกัน";
        return null;
      },
    );
  }
}