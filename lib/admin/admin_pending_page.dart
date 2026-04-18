import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config.dart';

class AdminPendingPage extends StatefulWidget {
  const AdminPendingPage({super.key});

  @override
  State<AdminPendingPage> createState() => _AdminPendingPageState();
}

class _AdminPendingPageState extends State<AdminPendingPage> {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cIcon = Color(0xFF523D2D);
  static const Color cTextMain = Color(0xFF523D2D);

  // 📏 ขนาด Font ตามที่กำหนด
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle = 15.0;  // หัวข้อย่อย
  static const double fBody = 13.0;   // เนื้อหา
  static const double fCaption = 11.0;

  bool loading = true, saving = false;
  int savingUserDormId = 0;
  List<Map<String, dynamic>> pending = [], rooms = [];
  int dormId = 0, adminUserId = 0;
  String keyword = "";

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    dormId = prefs.getInt("dorm_id") ?? int.tryParse(prefs.getString("dorm_id") ?? "0") ?? 0;
    adminUserId = prefs.getInt("user_id") ?? int.tryParse(prefs.getString("user_id") ?? "0") ?? 0;
    if (!mounted) return;
    await _reload();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => loading = true);
    await _loadBundle();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadBundle() async {
    try {
      final res = await http.post(Uri.parse(AppConfig.url("pending_api.php")), body: {
        "action": "list", 
        "dorm_id": dormId.toString(), 
        "admin_user_id": adminUserId.toString(),
      }).timeout(const Duration(seconds: 10));
      
      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        pending = List<Map<String, dynamic>>.from(data["pending"] ?? []);
        rooms = List<Map<String, dynamic>>.from(data["rooms"] ?? []);
      }
    } catch (e) { debugPrint("Load Error: $e"); }
  }

  int _toInt(dynamic v) => int.tryParse(v?.toString() ?? "0") ?? 0;

  String _prettyThaiDate(String? raw) {
    if (raw == null || raw.isEmpty) return "";
    try {
      final dt = DateTime.parse(raw.replaceFirst(" ", "T"));
      const thMonths = ["ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."];
      return "${dt.day} ${thMonths[dt.month - 1]} ${dt.year + 543}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} น.";
    } catch (_) { return raw; }
  }

  String _fmtDateApi(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${d.year}-${two(d.month)}-${two(d.day)}";
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: GoogleFonts.kanit(fontSize: fBody)), behavior: SnackBarBehavior.floating));
  }

  Future<void> _performApproveApi(int udId, int uId, String? roomId, String date, String role) async {
    setState(() { saving = true; savingUserDormId = udId; });
    try {
      final Map<String, String> body = {
        "action": "approve", 
        "dorm_id": dormId.toString(), 
        "admin_user_id": adminUserId.toString(),
        "user_dorm_id": udId.toString(), 
        "user_id": uId.toString(), 
        "room_id": roomId ?? "", 
        "move_in_date": date, 
        "role": role,
      };

      final response = await http.post(
        Uri.parse(AppConfig.url("pending_api.php")), 
        body: body,
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      
      if (data["success"] == true) {
        _snack("ดำเนินการเรียบร้อยแล้ว ✅");
        await _reload(); 
      } else {
        _snack("ล้มเหลว: ${data["message"]}");
      }
    } catch (e) {
      _snack("เกิดข้อผิดพลาดในการเชื่อมต่อ");
    } finally {
      if (mounted) setState(() { saving = false; savingUserDormId = 0; });
    }
  }

  Future<void> _handleApproveSelection(Map<String, dynamic> p) async {
    final udId = _toInt(p["user_dorm_id"]);
    final uId = _toInt(p["user_id"]);
    final String name = (p["full_name"] ?? p["username"] ?? "-").toString();

    if (udId == 0) { _snack("ข้อมูลไม่ถูกต้อง"); return; }

    final String? role = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("อนุมัติ: $name", textAlign: TextAlign.center, style: GoogleFonts.kanit(fontWeight: FontWeight.bold, fontSize: fHeader, color: cTextMain)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("เลือกประเภทผู้ใช้งาน", style: GoogleFonts.kanit(fontSize: fBody, color: Colors.grey)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: _buildCompactRoleButton(ctx, "tenant", Icons.person_outline_rounded, "ผู้เช่า")),
              const SizedBox(width: 12),
              Expanded(child: _buildCompactRoleButton(ctx, "admin", Icons.admin_panel_settings_outlined, "ผู้ดูแล")),
            ]),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: Text("ยกเลิก", style: GoogleFonts.kanit(color: Colors.grey, fontSize: fTitle))),
        ],
      ),
    );

    if (role == null) return;

    if (role == "admin") {
      await _performApproveApi(udId, uId, null, _fmtDateApi(DateTime.now()), "admin");
    } else {
      final result = await Navigator.push<Map<String, dynamic>>(
        context, MaterialPageRoute(builder: (_) => RoomSelectionPage(rooms: rooms, userName: name)),
      );
      if (result != null) {
        await _performApproveApi(udId, uId, result["room_id"].toString(), result["date"], "tenant");
      }
    }
  }

  Future<void> _reject(int udId) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text("ปฏิเสธคำขอ?", style: GoogleFonts.kanit(fontSize: fHeader)), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("ยกเลิก", style: GoogleFonts.kanit(fontSize: fTitle))), TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("ปฏิเสธ", style: GoogleFonts.kanit(color: Colors.red, fontSize: fTitle)))]));
    if (ok == true) {
      await http.post(Uri.parse(AppConfig.url("pending_api.php")), body: {"action": "reject", "dorm_id": dormId.toString(), "admin_user_id": adminUserId.toString(), "user_dorm_id": udId.toString()});
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = pending.where((p) {
      final name = (p["full_name"] ?? p["username"] ?? "").toString().toLowerCase();
      final phone = (p["phone"] ?? "").toString();
      return name.contains(keyword.toLowerCase()) || phone.contains(keyword);
    }).toList();

    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 50, elevation: 0, backgroundColor: Colors.white, centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: cTextMain, size: 18), onPressed: () => Navigator.pop(context)),
        title: Text("อนุมัติผู้เช่าใหม่", style: GoogleFonts.kanit(color: cTextMain, fontWeight: FontWeight.bold, fontSize: fHeader)),
      ),
      body: loading 
        ? const Center(child: CircularProgressIndicator(color: cTextMain)) 
        : RefreshIndicator(
            onRefresh: _reload,
            color: cTextMain,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _headerCard(filtered.length),
                const SizedBox(height: 12),
                _searchField(),
                const SizedBox(height: 12),
                if (filtered.isEmpty) _emptyState() else ...filtered.map(_pendingCard),
                const SizedBox(height: 100),
              ],
            ),
          ),
    );
  }

  Widget _headerCard(int count) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: cTextMain.withOpacity(0.04), blurRadius: 10)]),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: cAccent.withOpacity(0.4), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.how_to_reg_rounded, color: cIcon, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("รายการรออนุมัติ", style: GoogleFonts.kanit(fontWeight: FontWeight.bold, fontSize: fTitle, color: cTextMain)),
          Text("ทั้งหมด $count รายการ", style: GoogleFonts.kanit(color: Colors.grey, fontSize: fBody)),
        ])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: cBg, borderRadius: BorderRadius.circular(20)), child: Text("$count", style: GoogleFonts.kanit(fontWeight: FontWeight.bold, fontSize: fBody, color: cTextMain)))
      ]),
    );
  }

  Widget _searchField() {
    return SizedBox(
      height: 40, 
      child: TextField(
        onChanged: (v) => setState(() => keyword = v), 
        style: GoogleFonts.kanit(fontSize: fBody),
        decoration: InputDecoration(
          hintText: "ค้นหาชื่อ หรือ เบอร์โทร", 
          hintStyle: GoogleFonts.kanit(fontSize: fBody, color: Colors.grey),
          prefixIcon: const Icon(Icons.search, size: 18, color: cIcon), 
          filled: true, fillColor: Colors.white, 
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), 
          contentPadding: EdgeInsets.zero
        )
      )
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 80), 
      child: Center(
        child: Column(
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green.withOpacity(0.3)), 
            const SizedBox(height: 16), 
            Text("ไม่มีรายการรออนุมัติ", style: GoogleFonts.kanit(color: cTextMain, fontWeight: FontWeight.bold, fontSize: fTitle))
          ]
        )
      )
    );
  }

  Widget _pendingCard(Map<String, dynamic> p) {
    final udId = _toInt(p["user_dorm_id"]);
    final name = (p["full_name"] ?? p["username"] ?? "-").toString();
    final dateRaw = (p["created_at"] ?? "").toString(); 
    final isRowSaving = saving && savingUserDormId == udId;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: cTextMain.withOpacity(0.03), blurRadius: 8)]),
      child: Row(children: [
        CircleAvatar(radius: 22, backgroundColor: cAccent.withOpacity(0.5), child: Text(name.isNotEmpty ? name[0].toUpperCase() : "?", style: GoogleFonts.kanit(fontWeight: FontWeight.bold, color: cIcon, fontSize: fTitle))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: GoogleFonts.kanit(fontWeight: FontWeight.bold, fontSize: fTitle, color: cTextMain)),
          Text(_prettyThaiDate(dateRaw), style: GoogleFonts.kanit(fontSize: fBody, color: Colors.grey)),
        ])),
        Row(children: [
          _actionBtn(Icons.check_rounded, Colors.green, isRowSaving, () => _handleApproveSelection(p)),
          const SizedBox(width: 8),
          _actionBtn(Icons.close_rounded, Colors.redAccent, false, () => _reject(udId)),
        ]),
      ]),
    );
  }

  Widget _actionBtn(IconData icon, Color color, bool isLoad, VoidCallback onTap) {
    return InkWell(
      onTap: saving ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: isLoad ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildCompactRoleButton(BuildContext ctx, String value, IconData icon, String label) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: cAccent)),
        child: Column(children: [Icon(icon, color: cIcon), const SizedBox(height: 8), Text(label, style: GoogleFonts.kanit(fontWeight: FontWeight.bold, fontSize: fTitle, color: cTextMain))]),
      ),
    );
  }
}

class RoomSelectionPage extends StatefulWidget {
  final List<Map<String, dynamic>> rooms;
  final String userName;
  const RoomSelectionPage({super.key, required this.rooms, required this.userName});
  @override State<RoomSelectionPage> createState() => _RoomSelectionPageState();
}

class _RoomSelectionPageState extends State<RoomSelectionPage> {
  static const Color cBg = Color(0xFFF4EFE6), cAccent = Color(0xFFDCD2C1), cTextMain = Color(0xFF523D2D), cIcon = Color(0xFF523D2D);
  static const double fHeader = 18.0, fTitle = 15.0, fBody = 13.0;

  int? selectedRoomId;
  String keyword = "";

  String _roomLabel(Map<String, dynamic> r) {
    final b = (r["building"] ?? "").toString().trim(), n = (r["room_number"] ?? "").toString().trim();
    return b.isEmpty ? n : (n.isEmpty ? b : "$b-$n");
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.rooms.where((r) => _roomLabel(r).toLowerCase().contains(keyword.toLowerCase())).toList();
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(toolbarHeight: 50, backgroundColor: Colors.white, elevation: 0, centerTitle: true, leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: cTextMain, size: 18), onPressed: () => Navigator.pop(context)), title: Text("จัดสรรห้องพัก", style: GoogleFonts.kanit(color: cTextMain, fontWeight: FontWeight.bold, fontSize: fTitle))),
      body: Column(children: [
        Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16), color: Colors.white, child: Column(children: [Text("ผู้ขอเข้าพัก", style: GoogleFonts.kanit(fontSize: fBody, color: Colors.grey)), const SizedBox(height: 4), Text(widget.userName, textAlign: TextAlign.center, style: GoogleFonts.kanit(fontSize: fHeader, fontWeight: FontWeight.bold, color: cTextMain))])),
        Padding(padding: const EdgeInsets.all(12), child: SizedBox(height: 40, child: TextField(onChanged: (v) => setState(() => keyword = v), style: GoogleFonts.kanit(fontSize: fBody), decoration: InputDecoration(hintText: "ค้นหาเลขห้อง...", hintStyle: GoogleFonts.kanit(fontSize: fBody), prefixIcon: const Icon(Icons.search, size: 20, color: cIcon), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: EdgeInsets.zero)))),
        Expanded(child: filtered.isEmpty 
          ? Center(child: Text("ไม่พบห้องพักที่ว่าง", style: GoogleFonts.kanit(color: cIcon.withOpacity(0.5), fontSize: fTitle)))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: filtered.length, itemBuilder: (ctx, i) {
              final r = filtered[i], rid = int.parse(r["room_id"].toString()), isSel = selectedRoomId == rid, label = _roomLabel(r);
              return GestureDetector(
                onTap: () => setState(() => selectedRoomId = rid), 
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8), 
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), 
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isSel ? cTextMain : Colors.transparent, width: 1.5)), 
                  child: Row(children: [
                    CircleAvatar(radius: 18, backgroundColor: isSel ? cTextMain : cAccent.withOpacity(0.5), child: Text(label.isNotEmpty ? label[0] : "?", style: GoogleFonts.kanit(color: isSel ? Colors.white : cIcon, fontWeight: FontWeight.bold, fontSize: fBody))), 
                    const SizedBox(width: 12), 
                    Expanded(child: Text("ห้อง $label", style: GoogleFonts.kanit(fontWeight: FontWeight.bold, fontSize: fTitle, color: cTextMain))), 
                    if (isSel) const Icon(Icons.check_circle, color: Colors.green, size: 20)
                  ])
                )
              );
            })),
        Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))), child: SafeArea(child: ElevatedButton(onPressed: selectedRoomId == null ? null : () => Navigator.pop(context, {"room_id": selectedRoomId, "date": "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}"}), style: ElevatedButton.styleFrom(backgroundColor: cTextMain, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: Text("ยืนยันการจัดห้อง", style: GoogleFonts.kanit(fontWeight: FontWeight.bold, fontSize: fTitle))))),
      ]),
    );
  }
}