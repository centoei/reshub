import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  // 🎨 Palette - ชุดสี Earth Tone
  static const Color cCream = Color(0xFFFFEAC5); 
  static const Color cPeach = Color(0xFFFFDBB5); 
  static const Color cBrown = Color(0xFF6C4E31); 
  static const Color cDark  = Color(0xFF603F26); 

  // 📏 Micro Typography (ค่าเดียวกับหน้า Login/Register)
  static const double fTitle   = 22.0;   
  static const double fBody    = 13.0;    
  static const double fCaption = 11.0;

  final _formKey = GlobalKey<FormState>();
  final usernameCtrl = TextEditingController();
  final dormCodeCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final newPassCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  bool _loading = false;
  bool obscure1 = true;
  bool obscure2 = true;

  @override
  void dispose() {
    usernameCtrl.dispose();
    dormCodeCtrl.dispose();
    phoneCtrl.dispose();
    newPassCtrl.dispose();
    confirmCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: fBody)), 
        behavior: SnackBarBehavior.floating,
        backgroundColor: cDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

Future<void> _submit() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      // ส่งข้อมูลไปยัง forgot_password.php ที่ปรับปรุงใหม่
      final res = await http.post(
        Uri.parse(AppConfig.url("forgot_password.php")),
        body: {
          "username": usernameCtrl.text.trim(),
          "dorm_code": dormCodeCtrl.text.trim(), // ส่ง Code เพื่อไป Join หา dorm_id ใน DB
          "phone": phoneCtrl.text.trim(),
          "new_password": newPassCtrl.text.trim(),
        },
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      if (!mounted) return;

      if (res.statusCode == 200 && data["success"] == true) {
        _snack("เปลี่ยนรหัสผ่านเรียบร้อย ✅");
        Navigator.pop(context); // กลับไปหน้า Login
      } else {
        _snack(data["message"] ?? "เปลี่ยนรหัสไม่สำเร็จ");
      }
    } catch (e) {
      _snack("เชื่อมต่อไม่ได้: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
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
            colors: [cCream, cPeach],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom Header (เล็กลง)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: cDark, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
              
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Center(
                    child: Container(
                      width: 360, // ความกว้างเท่ากับหน้า Register
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: cDark.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 8))
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text("ลืมรหัสผ่าน", 
                              style: TextStyle(fontSize: fTitle, fontWeight: FontWeight.w900, color: cBrown, letterSpacing: 1.0)
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "กรอกข้อมูลเพื่อตั้งรหัสผ่านใหม่",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cDark.withOpacity(0.7), fontSize: fCaption),
                            ),
                            const SizedBox(height: 20),

                            _sectionLabel("ตรวจสอบตัวตน"),
                            _field(usernameCtrl, "Username", Icons.person_outline),
                            const SizedBox(height: 10),
                            _field(dormCodeCtrl, "โค้ดหอพัก", Icons.vpn_key_outlined),
                            const SizedBox(height: 10),
                            _field(phoneCtrl, "เบอร์โทรศัพท์", Icons.phone_android_outlined, keyboardType: TextInputType.phone),
                            
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Divider(color: Colors.black12, height: 1),
                            ),
                            
                            _sectionLabel("ตั้งรหัสผ่านใหม่"),
                            _field(
                              newPassCtrl, "รหัสผ่านใหม่", Icons.lock_outline,
                              isPass: true,
                              obs: obscure1,
                              toggle: () => setState(() => obscure1 = !obscure1),
                            ),
                            const SizedBox(height: 10),
                            _field(
                              confirmCtrl, "ยืนยันรหัสผ่านใหม่", Icons.lock_reset,
                              isPass: true,
                              obs: obscure2,
                              toggle: () => setState(() => obscure2 = !obscure2),
                            ),

                            const SizedBox(height: 24),
                            
                            // ปุ่มกึ่งสำเร็จรูป (Micro Height)
                            SizedBox(
                              width: double.infinity,
                              height: 44, 
                              child: ElevatedButton(
                                onPressed: _loading ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: cBrown,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                child: _loading
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : const Text("ยืนยันการเปลี่ยนรหัส", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            
                            const SizedBox(height: 16),
                            Text(
                              "หากคุณลืมโค้ดหอพัก กรุณาติดต่อผู้ดูแลหอพัก",
                              style: TextStyle(color: cBrown.withOpacity(0.8), fontSize: fCaption, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
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

  // Label หัวข้อส่วนย่อย
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: const TextStyle(fontSize: fBody, fontWeight: FontWeight.bold, color: cBrown)),
      ),
    );
  }

  // สไตล์ช่องกรอกข้อมูลแบบเดียวกับ Login "Micro"
  Widget _field(
    TextEditingController ctrl, 
    String label, 
    IconData icon, 
    {bool isPass = false, bool obs = false, VoidCallback? toggle, TextInputType keyboardType = TextInputType.text}
  ) {
    return TextFormField(
      controller: ctrl,
      obscureText: obs,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: fBody, color: cDark, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.black54, fontSize: fBody),
        prefixIcon: Icon(icon, color: cBrown, size: 18),
        suffixIcon: isPass ? IconButton(icon: Icon(obs ? Icons.visibility_off : Icons.visibility, color: cBrown, size: 18), onPressed: toggle) : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cBrown, width: 1.5),
        ),
        errorStyle: const TextStyle(fontSize: 10),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return "กรุณากรอกข้อมูล";
        if (label == "รหัสผ่านใหม่" && v.length < 6) return "อย่างน้อย 6 ตัว";
        if (label == "ยืนยันรหัสผ่านใหม่" && v != newPassCtrl.text) return "รหัสไม่ตรงกัน";
        return null;
      },
    );
  }
}