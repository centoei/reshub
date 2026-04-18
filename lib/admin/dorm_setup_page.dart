import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config.dart';
import 'room/admin_room_page.dart';

class DormSetupPage extends StatefulWidget {
  const DormSetupPage({super.key});

  @override
  State<DormSetupPage> createState() => _DormSetupPageState();
}

class _DormSetupPageState extends State<DormSetupPage> {
  // 🎨 ปรับ Palette สีเป็น Earth Tone (F4EFE6 / 523D2D)
  static const Color cBg = Color(0xFFF4EFE6);       // สีครีมพื้นหลัง
  static const Color cAccent = Color(0xFFDCD2C1);   // สีน้ำตาลอ่อน (Accent)
  static const Color cIcon = Color(0xFF523D2D);     // สีไอคอน
  static const Color cTextMain = Color(0xFF523D2D); // สีน้ำตาลเข้ม (Main Text)

  // 📏 มาตราส่วน Font ตามที่กำหนด
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle = 15.0;  // หัวข้อย่อย
  static const double fBody = 13.0;   // เนื้อหา
  static const double fCaption = 11.0;

  bool loading = true;
  bool saving = false;
  int dormId = 0;

  final List<String> buildingNames = []; 
  final buildingNameCtrl = TextEditingController();

  final floorsCtrl = TextEditingController(text: "1");
  final roomsPerFloorCtrl = TextEditingController(text: "10");
  final rentFanCtrl = TextEditingController(text: "0");
  final rentAirCtrl = TextEditingController(text: "0");

  String defaultType = "fan"; 
  int totalRooms = 0, fanRooms = 0, airRooms = 0, totalBuildings = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    buildingNameCtrl.dispose();
    floorsCtrl.dispose();
    roomsPerFloorCtrl.dispose();
    rentFanCtrl.dispose();
    rentAirCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    dormId = prefs.getInt("dorm_id") ?? prefs.getInt("selected_dorm_id") ?? 0;
    if (dormId <= 0) {
      if (mounted) setState(() => loading = false);
      return;
    }
    await _loadAll();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadAll() async {
    try {
      final uri = Uri.parse(AppConfig.url("dorm_setup.php")).replace(queryParameters: {
        "action": "get",
        "dorm_id": dormId.toString(),
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);

      if (data["ok"] == true) {
        final s = data["settings"] ?? {};
        rentFanCtrl.text = "${s["default_rent_fan"] ?? 0}";
        rentAirCtrl.text = "${s["default_rent_air"] ?? 0}";

        final sum = data["summary"] ?? {};
        totalRooms = sum["total_rooms"] ?? 0;
        fanRooms = sum["fan_count"] ?? 0;
        airRooms = sum["air_count"] ?? 0;
        totalBuildings = sum["building_count"] ?? 0;
        if (mounted) setState(() {});
      }
    } catch (e) { debugPrint("Load Error: $e"); }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.kanit(fontSize: fBody)), 
        behavior: SnackBarBehavior.floating,
        backgroundColor: cTextMain,
      ),
    );
  }

  Future<bool?> _showConfirmDialog({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: cBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_business_rounded, color: cIcon, size: 40),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: GoogleFonts.kanit(fontSize: fHeader, fontWeight: FontWeight.bold, color: cTextMain),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(fontSize: fBody, color: Colors.grey, height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: cTextMain,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text("ตกลง", style: GoogleFonts.kanit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fTitle)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: cAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text("ยกเลิก", style: GoogleFonts.kanit(color: cTextMain, fontWeight: FontWeight.bold, fontSize: fTitle)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generateRooms() async {
    if (buildingNames.isEmpty) { _snack("กรุณากดปุ่มบวกเพื่อเพิ่มชื่อตึกก่อน"); return; }
    
    final bool? confirm = await _showConfirmDialog(
      title: "ยืนยันการสร้างห้อง",
      message: "ระบบจะสร้างตึก ${buildingNames.join(', ')} \nจำนวน ${floorsCtrl.text} ชั้น ชั้นละ ${roomsPerFloorCtrl.text} ห้อง \nต้องการดำเนินการหรือไม่ ?",
    );

    if (confirm != true) return;

    setState(() => saving = true);
    try {
      final res = await http.post(
        Uri.parse(AppConfig.url("dorm_setup.php")),
        body: {
          "action": "generate",
          "dorm_id": dormId.toString(),
          "building_names": jsonEncode(buildingNames), 
          "floors": floorsCtrl.text.trim(),
          "rooms_per_floor": roomsPerFloorCtrl.text.trim(),
          "default_type": defaultType,
        },
      ).timeout(const Duration(seconds: 20));

      final data = jsonDecode(res.body);
      if (data["ok"] == true) {
        _snack("สร้างห้องสำเร็จ! เพิ่มขึ้น ${data['count']} ห้อง");
        setState(() => buildingNames.clear()); 
        _loadAll(); 
      }
    } catch (e) { _snack("เกิดข้อผิดพลาดในการสร้างห้อง"); }
    finally { if (mounted) setState(() => saving = false); }
  }

  Widget _buildBuildingAdder() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("พิมพ์ชื่อตึกแล้วกด +", style: GoogleFonts.kanit(fontSize: fBody, fontWeight: FontWeight.bold, color: Colors.black54)),
            if (buildingNames.isNotEmpty)
              InkWell(
                onTap: () => setState(() => buildingNames.clear()),
                child: Text("ล้างทั้งหมด", style: GoogleFonts.kanit(fontSize: fCaption, color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 45,
                child: TextField(
                  controller: buildingNameCtrl,
                  style: GoogleFonts.kanit(fontSize: fBody, color: cTextMain),
                  decoration: InputDecoration(
                    hintText: "เช่น ตึกนที, ตึก A",
                    hintStyle: GoogleFonts.kanit(fontSize: fBody),
                    filled: true, 
                    fillColor: cBg.withOpacity(0.5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () {
                if (buildingNameCtrl.text.trim().isNotEmpty) {
                  setState(() {
                    if (!buildingNames.contains(buildingNameCtrl.text.trim())) {
                      buildingNames.add(buildingNameCtrl.text.trim());
                    }
                    buildingNameCtrl.clear();
                  });
                }
              },
              icon: const Icon(Icons.add),
              style: IconButton.styleFrom(backgroundColor: cIcon),
            ),
          ],
        ),
        if (buildingNames.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8, runSpacing: 4,
              children: buildingNames.map((name) => Chip(
                label: Text(name, style: GoogleFonts.kanit(fontSize: fBody, color: cTextMain, fontWeight: FontWeight.bold)),
                backgroundColor: cAccent.withOpacity(0.4),
                onDeleted: () => setState(() => buildingNames.remove(name)),
                deleteIcon: const Icon(Icons.cancel, size: 16, color: cTextMain),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide.none),
              )).toList(),
            ),
          ),
      ],
    );  
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 50, 
        backgroundColor: Colors.white, 
        elevation: 0.5, 
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: cTextMain, size: 18), onPressed: () => Navigator.pop(context)),
        title: Text("จัดการอาคาร", style: GoogleFonts.kanit(color: cTextMain, fontWeight: FontWeight.bold, fontSize: fHeader)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: cTextMain))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSimpleStatRow(),
                  const SizedBox(height: 12),
                  _buildQuickGoToRoomButton(),
                  const SizedBox(height: 24),
                  
                  _buildModernCard(
                    title: "ราคาเช่าพื้นฐาน",
                    icon: Icons.payments_outlined,
                    child: Column(
                      children: [
                        _buildInputField("ราคาห้องพัดลม / เดือน", rentFanCtrl, "฿"),
                        const SizedBox(height: 12),
                        _buildInputField("ราคาห้องแอร์ / เดือน", rentAirCtrl, "฿"),
                        const SizedBox(height: 16),
                        _buildPrimaryButton("บันทึกราคา", cTextMain, _savePrices),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),

                  _buildModernCard(
                    title: "ตัวช่วยสร้างห้องพัก",
                    icon: Icons.add_business_outlined,
                    child: Column(
                      children: [
                        _buildBuildingAdder(),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildInputField("จำนวนชั้น", floorsCtrl, "ชั้น")),
                            const SizedBox(width: 12),
                            Expanded(child: _buildInputField("จำนวนห้องต่อชั้น", roomsPerFloorCtrl, "ห้อง")),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildDropdownField("ประเภทห้องเริ่มต้น"),
                        const SizedBox(height: 20),
                        _buildPrimaryButton("สร้างห้องทั้งหมด", cTextMain, _generateRooms),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildQuickGoToRoomButton() {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminRoomPage())),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(12), 
          border: Border.all(color: cAccent), 
          boxShadow: [BoxShadow(color: cTextMain.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))]
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.meeting_room_outlined, color: cIcon, size: 18),
          const SizedBox(width: 8),
          Text("ดูรายชื่อห้องพักทั้งหมด", style: GoogleFonts.kanit(color: cIcon, fontWeight: FontWeight.bold, fontSize: fTitle)),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_forward_ios_rounded, color: cIcon, size: 10),
        ]),
      ),
    );
  }

  Widget _buildSimpleStatRow() {
    return Row(
      children: [
        Expanded(child: _buildStatCard("พัดลม", fanRooms, Colors.orange.shade800, Icons.mode_fan_off_rounded)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard("แอร์", airRooms, Colors.blue.shade800, Icons.ac_unit_rounded)),
        const SizedBox(width: 8),
        Expanded(child: _buildStatCard("รวม", totalRooms, cTextMain, Icons.domain_rounded)),
      ],
    );
  }

  Widget _buildStatCard(String label, int value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16), 
        boxShadow: [BoxShadow(color: cTextMain.withOpacity(0.02), blurRadius: 6)], 
        border: Border.all(color: Colors.white)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withOpacity(0.08), shape: BoxShape.circle), child: Icon(icon, color: color, size: 16)),
          const SizedBox(height: 8),
          Text("$value", style: GoogleFonts.kanit(fontSize: fHeader, fontWeight: FontWeight.bold, color: cTextMain)),
          Text(label, style: GoogleFonts.kanit(fontSize: fCaption, fontWeight: FontWeight.bold, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildModernCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16), 
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(18), 
        boxShadow: [BoxShadow(color: cTextMain.withOpacity(0.04), blurRadius: 10)]
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, size: 18, color: cIcon), const SizedBox(width: 8), Text(title, style: GoogleFonts.kanit(fontSize: fTitle, fontWeight: FontWeight.bold, color: cTextMain))]),
        const SizedBox(height: 16), child,
      ]),
    );
  }

  Widget _buildInputField(String label, TextEditingController ctrl, String suffix) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 6), child: Text(label, style: GoogleFonts.kanit(fontSize: fBody, fontWeight: FontWeight.bold, color: Colors.black54))),
      SizedBox(
        height: 45, 
        child: TextField(
          controller: ctrl, 
          keyboardType: TextInputType.text, 
          style: GoogleFonts.kanit(fontSize: fBody, color: cTextMain, fontWeight: FontWeight.bold), 
          decoration: InputDecoration(
            suffixText: suffix, 
            suffixStyle: GoogleFonts.kanit(fontSize: fBody, color: Colors.grey), 
            filled: true, 
            fillColor: cBg.withOpacity(0.4), 
            contentPadding: const EdgeInsets.symmetric(horizontal: 12), 
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)
          )
        )
      ),
    ]);
  }

  Widget _buildDropdownField(String label) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 6), child: Text(label, style: GoogleFonts.kanit(fontSize: fBody, fontWeight: FontWeight.bold, color: Colors.black54))),
      Container(
        height: 45, 
        padding: const EdgeInsets.symmetric(horizontal: 12), 
        decoration: BoxDecoration(color: cBg.withOpacity(0.4), borderRadius: BorderRadius.circular(10)), 
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: defaultType, 
            isExpanded: true, 
            icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: cIcon), 
            style: GoogleFonts.kanit(fontSize: fBody, color: cTextMain, fontWeight: FontWeight.bold), 
            items: const [
              DropdownMenuItem(value: "fan", child: Text("ห้องพัดลม")), 
              DropdownMenuItem(value: "air", child: Text("ห้องแอร์"))
            ], 
            onChanged: (v) => setState(() => defaultType = v!)
          )
        )
      ),
    ]);
  }

  Widget _buildPrimaryButton(String label, Color color, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity, height: 48,
      child: ElevatedButton(
        onPressed: saving ? null : onTap,
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        child: saving 
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : Text(label, style: GoogleFonts.kanit(fontSize: fTitle, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Future<void> _savePrices() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final res = await http.post(Uri.parse(AppConfig.url("dorm_setup.php")), body: {"action": "update_rent", "dorm_id": dormId.toString(), "rent_fan": rentFanCtrl.text.trim(), "rent_air": rentAirCtrl.text.trim()});
      final data = jsonDecode(res.body);
      if (data["ok"] == true) _snack("บันทึกราคาเรียบร้อยแล้ว ✅");
    } catch (_) { _snack("เชื่อมต่อเซิร์ฟเวอร์ไม่ได้"); }
    finally { if (mounted) setState(() => saving = false); }
  }
}