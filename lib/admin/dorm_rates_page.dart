import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config.dart';

class DormRatesPage extends StatefulWidget {
  const DormRatesPage({super.key});

  @override
  State<DormRatesPage> createState() => _DormRatesPageState();
}

class _DormRatesPageState extends State<DormRatesPage> {
  // 🎨 ปรับ Palette สีเป็น Earth Tone (F4EFE6 / 523D2D)
  static const Color cBg = Color(0xFFF4EFE6);       // สีครีมพื้นหลัง
  static const Color cAccent = Color(0xFFDCD2C1);   // สีน้ำตาลอ่อน (Accent)
  static const Color cIcon = Color(0xFF523D2D);     // สีไอคอน
  static const Color cDark  = Color(0xFF523D2D);    // สีน้ำตาลเข้ม (Main)

  // 📏 มาตราส่วน Font ตามที่กำหนด
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle = 15.0;  // หัวข้อย่อย
  static const double fBody = 13.0;   // เนื้อหา
  static const double fCaption = 11.0;

  bool loading = true;
  bool saving = false;
  int dormId = 0;

  final waterCtrl = TextEditingController();
  final elecCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      dormId = prefs.getInt("dorm_id") ?? prefs.getInt("selected_dorm_id") ?? 0;
      if (dormId <= 0) throw Exception("ไม่พบ dorm_id");
      await _load();
    } catch (e) { _snack("$e"); } 
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> _load() async {
    final uri = Uri.parse(AppConfig.url("dorm_setup.php")).replace(queryParameters: {
      "action": "get", "dorm_id": dormId.toString(),
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    final data = jsonDecode(res.body);
    if (data["ok"] == true) {
      final s = data["settings"] ?? {};
      waterCtrl.text = "${s["water_rate"] ?? 0}";
      elecCtrl.text = "${s["electric_rate"] ?? 0}";
      if (mounted) setState(() {});
    }
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final res = await http.post(
        Uri.parse(AppConfig.url("dorm_setup.php?action=save")),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "dorm_id": dormId,
          "water_rate": double.tryParse(waterCtrl.text) ?? 0,
          "electric_rate": double.tryParse(elecCtrl.text) ?? 0,
        }),
      );
      if (jsonDecode(res.body)["ok"] == true) {
        _snack("บันทึกสำเร็จ ✅");
        Navigator.pop(context); 
      }
    } catch (e) { _snack("ผิดพลาด: $e"); }
    finally { if (mounted) setState(() => saving = false); }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.kanit(fontSize: fBody)), 
        behavior: SnackBarBehavior.floating, 
        backgroundColor: cDark
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        toolbarHeight: 50,
        centerTitle: true,
        title: Text("เรทค่าน้ำ-ไฟ", 
          style: GoogleFonts.kanit(color: cDark, fontWeight: FontWeight.bold, fontSize: fHeader)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: cDark, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: cDark))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: cDark.withOpacity(0.06),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      )
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel("ค่าน้ำ / หน่วย"),
                      _buildPriceField(waterCtrl, Icons.water_drop, Colors.blue),
                      
                      const SizedBox(height: 20),
                      
                      _buildLabel("ค่าไฟ / หน่วย"),
                      _buildPriceField(elecCtrl, Icons.bolt, Colors.orange),
                      
                      const SizedBox(height: 32),
                      
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cDark,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: saving 
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text("บันทึกราคา", style: GoogleFonts.kanit(fontSize: fTitle, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: GoogleFonts.kanit(fontSize: fTitle, color: cIcon, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildPriceField(TextEditingController controller, IconData icon, Color iconColor) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.kanit(fontSize: fHeader, fontWeight: FontWeight.bold, color: cDark),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: iconColor, size: 20),
        suffixText: "บาท",
        suffixStyle: GoogleFonts.kanit(color: Colors.grey, fontSize: fBody),
        filled: true,
        fillColor: cBg.withOpacity(0.4), 
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: cDark, width: 1.5),
        ),
      ),
    );
  }
}