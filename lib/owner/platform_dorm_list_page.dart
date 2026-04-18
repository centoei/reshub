import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import '../config.dart';

class PlatformDormListPage extends StatefulWidget {
  const PlatformDormListPage({super.key});

  @override
  State<PlatformDormListPage> createState() => _PlatformDormListPageState();
}

class _PlatformDormListPageState extends State<PlatformDormListPage> {
  final TextEditingController searchCtrl = TextEditingController();
  bool loading = true;

  String statusFilter = "all"; 
  List<Map<String, dynamic>> dorms = [];

  static const Color cBg = Color(0xFFF4EFE6);       
  static const Color cAccent = Color(0xFFDCD2C1);   
  static const Color cTextMain = Color(0xFF2A1F17); 
  static const Color cDark = Color(0xFF523D2D);     

  // 📏 Typography System
  static const double fHeader  = 18.0; // หัวข้อใหญ่
  static const double fTitle   = 15.0; // หัวข้อย่อย
  static const double fBody    = 13.0; // เนื้อหา
  static const double fCaption = 11.0; // คำอธิบาย

  final Map<String, String> statusMap = const {
    "all": "ทั้งหมด",
    "active": "ใช้งานอยู่",
    "suspended": "ปิดใช้งาน",
  };

  @override
  void initState() {
    super.initState();
    fetchDorms();
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get filtered {
    if (statusFilter == "all") return dorms;
    return dorms.where((d) => (d["status"] ?? "") == statusFilter).toList();
  }

  Color _getFilterColor(String key) {
    switch (key) {
      case "all":       return const Color(0xFF1565C0);
      case "active":    return const Color(0xFF2E7D32);
      case "suspended": return const Color(0xFFD32F2F);
      default:          return Colors.grey;
    }
  }

  Future<void> fetchDorms() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      final url = Uri.parse("${AppConfig.baseUrl}/platform_api.php");
      final res = await http.post(url, body: {
        "action": "listDorms",
        "q": searchCtrl.text.trim(),
      }).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data["success"] == true) {
        final List list = (data["data"] as List?) ?? [];
        setState(() {
          dorms = list.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _setDormStatus(int dormId, String newStatus) async {
    try {
      final url = Uri.parse("${AppConfig.baseUrl}/platform_api.php");
      final res = await http.post(url, body: {
        "action": "setDormStatus",
        "dorm_id": dormId.toString(),
        "status": newStatus,
      }).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data["success"] == true) {
        fetchDorms();
      }
    } catch (e) {
    }
  }

  void _showStatusPicker(int dormId, String currentStatus) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "จัดการสถานะหอพัก",
                style: GoogleFonts.kanit(fontSize: fHeader, fontWeight: FontWeight.w600, color: cTextMain),
              ),
              const SizedBox(height: 24),
              _statusOption(
                label: "เปิดใช้งาน",
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF2E7D32),
                isSelected: currentStatus == "active",
                onTap: () {
                  Navigator.pop(context);
                  _setDormStatus(dormId, "active");
                },
              ),
              const SizedBox(height: 12),
              _statusOption(
                label: "ปิดการใช้งาน",
                icon: Icons.block_flipped,
                color: const Color(0xFFD32F2F),
                isSelected: currentStatus == "suspended",
                onTap: () {
                  Navigator.pop(context);
                  _setDormStatus(dormId, "suspended");
                },
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  "ยกเลิก",
                  style: GoogleFonts.kanit(color: Colors.grey[600], fontWeight: FontWeight.w600, fontSize: fBody),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusOption({required String label, required IconData icon, required Color color, required bool isSelected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? color : Colors.grey[200]!, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Text(label, style: GoogleFonts.kanit(fontWeight: FontWeight.w600, color: isSelected ? color : cTextMain, fontSize: fBody)),
            const Spacer(),
            Icon(isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: isSelected ? color : Colors.grey[300], size: 20),
          ],
        ),
      ),
    );
  }

  void _showDormDetails(Map<String, dynamic> d) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(28),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 45, height: 5, decoration: BoxDecoration(color: cAccent, borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 25),
            Row(
              children: [
                Container(width: 55, height: 55, decoration: BoxDecoration(color: _statusColor(d["status"]).withOpacity(0.1), borderRadius: BorderRadius.circular(18)), child: Icon(Icons.apartment_rounded, color: _statusColor(d["status"]), size: 30)),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d["dorm_name"] ?? "-", style: GoogleFonts.kanit(fontSize: fHeader, fontWeight: FontWeight.w600, color: cTextMain)),
                  Text("รหัสหอพัก: ${d["dorm_code"] ?? "-"}", style: GoogleFonts.kanit(fontSize: fCaption, color: cDark, fontWeight: FontWeight.normal)),
                ])),
              ],
            ),
            const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(height: 1, thickness: 1, color: cBg)),
            _infoItem(Icons.location_on_rounded, "ที่ตั้งหอพัก", d["dorm_address"] ?? "ไม่ได้ระบุ", const Color(0xFFD84315)),
            const SizedBox(height: 20),
            _infoItem(Icons.phone_rounded, "เบอร์โทรศัพท์", d["dorm_phone"] ?? "ไม่ได้ระบุ", const Color(0xFF2E7D32), canCopy: true),
            const SizedBox(height: 40),
            SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: () => Navigator.pop(context), style: ElevatedButton.styleFrom(backgroundColor: cTextMain, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)), elevation: 0), child: Text("ตกลง", style: GoogleFonts.kanit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: fTitle)))),
            const SizedBox(height: 15),
          ],
        ),
      ),
    );
  }

  Widget _infoItem(IconData icon, String label, String value, Color iconColor, {bool canCopy = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, size: 20, color: iconColor)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.kanit(fontSize: fCaption, color: Colors.grey, fontWeight: FontWeight.normal)),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.kanit(fontSize: fBody, color: cTextMain, height: 1.5, fontWeight: FontWeight.normal)),
        ])),
        if (canCopy && value != "ไม่ได้ระบุเบอร์โทรศัพท์")
          IconButton(onPressed: () { Clipboard.setData(ClipboardData(text: value)); }, icon: const Icon(Icons.copy_all_rounded, size: 20, color: Color(0xFF1565C0))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0.5, toolbarHeight: 60,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: cTextMain), onPressed: () => Navigator.pop(context)),
        title: Text("จัดการหอพัก", style: GoogleFonts.kanit(fontWeight: FontWeight.w600, color: cTextMain, fontSize: fHeader)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildTopSearchAndFilter(),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: cDark))
                : list.isEmpty
                    ? Center(child: Text("ไม่พบข้อมูลหอพัก", style: GoogleFonts.kanit(fontWeight: FontWeight.w600, color: cDark, fontSize: fBody)))
                    : RefreshIndicator(
                        onRefresh: fetchDorms,
                        color: cDark,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 14),
                          itemBuilder: (_, i) => _dormCard(list[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSearchAndFilter() {
    return Container(
      color: Colors.white, padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(children: [
        TextField(
          controller: searchCtrl, onSubmitted: (_) => fetchDorms(),
          style: GoogleFonts.kanit(fontWeight: FontWeight.normal, color: cTextMain, fontSize: fBody),
          decoration: InputDecoration(
            hintText: "ค้นหา ชื่อหอ / โค้ดหอ", hintStyle: GoogleFonts.kanit(color: Colors.grey.shade400, fontWeight: FontWeight.normal, fontSize: fBody),
            prefixIcon: const Icon(Icons.search_rounded, size: 22, color: cTextMain),
            suffixIcon: IconButton(onPressed: fetchDorms, icon: const Icon(Icons.filter_list_rounded, color: cDark)),
            filled: true, fillColor: cBg.withOpacity(0.5), contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: statusMap.entries.map((entry) {
            final isSelected = statusFilter == entry.key;
            final color = _getFilterColor(entry.key);
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: InkWell(
                onTap: () => setState(() => statusFilter = entry.key),
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: isSelected ? color : color.withOpacity(0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: isSelected ? color : color.withOpacity(0.3), width: 1.5)),
                  child: Row(children: [
                    if (isSelected) ...[const Icon(Icons.check_circle_rounded, size: 14, color: Colors.white), const SizedBox(width: 8)],
                    Text(entry.value, style: GoogleFonts.kanit(color: isSelected ? Colors.white : color, fontWeight: FontWeight.w600, fontSize: 12)),
                  ]),
                ),
              ),
            );
          }).toList()),
        ),
      ]),
    );
  }

  Widget _dormCard(Map<String, dynamic> d) {
    final dormId = int.tryParse((d["dorm_id"] ?? "0").toString()) ?? 0;
    final status = d["status"] ?? "active";

    return GestureDetector(
      onTap: () => _showDormDetails(d),
      onLongPress: () => _showStatusPicker(dormId, status), 
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))]),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: _statusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(15)), child: Icon(Icons.apartment_rounded, color: _statusColor(status), size: 26)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d["dorm_name"] ?? "-", style: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: fTitle, color: cTextMain)),
                const SizedBox(height: 2),
                Text("รหัส : ${d["dorm_code"] ?? "-"}", style: GoogleFonts.kanit(color: const Color(0xFF757575), fontSize: fCaption, fontWeight: FontWeight.normal)),
              ])),
              GestureDetector(
                onTap: () => _showStatusPicker(dormId, status),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: _statusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: _statusColor(status).withOpacity(0.2))),
                  child: Row(children: [
                    Text(_statusText(status), style: GoogleFonts.kanit(fontWeight: FontWeight.w600, color: _statusColor(status), fontSize: 10)),
                    const SizedBox(width: 4),
                    Icon(Icons.sync_alt_rounded, size: 10, color: _statusColor(status)),
                  ]),
                ),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: cBg.withOpacity(0.3), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24))),
            child: Row(children: [
              Expanded(child: _miniBox("ผู้เช่า", d["tenant_count"]?.toString() ?? "0", Icons.people_alt_rounded, const Color(0xFF1565C0))),
              Container(width: 1, height: 25, color: cAccent.withOpacity(0.5)),
              Expanded(child: _miniBox("แอดมิน", d["admin_count"]?.toString() ?? "0", Icons.admin_panel_settings_rounded, cDark)),
              Container(width: 1, height: 25, color: cAccent.withOpacity(0.5)),
              Expanded(child: _miniBox("รออนุมัติ", d["pending_count"]?.toString() ?? "0", Icons.hourglass_empty_rounded, const Color(0xFFEF6C00))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _miniBox(String label, String value, IconData icon, Color color) {
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 14, color: color), const SizedBox(width: 6), Text(label, style: GoogleFonts.kanit(color: Colors.grey.shade600, fontSize: fCaption, fontWeight: FontWeight.normal))]),
      const SizedBox(height: 4),
      Text(value, style: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: fTitle, color: cTextMain)),
    ]);
  }

  Color _statusColor(dynamic s) => (s == "active") ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F);
  String _statusText(dynamic s) => (s == "active") ? "ใช้งานอยู่" : "ปิดใช้งาน";
}