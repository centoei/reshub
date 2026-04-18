import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config.dart';
import 'bill_detail_page.dart';

// --- 1. Data Model ---
class BillItem {
  final int roomId, dormId, floor, month, year;
  final String roomNumber, building, dueDate, statusKey, statusLabel, statusColor;
  final int? tenantId, paymentId;
  final String? fullName, phone, paymentStatus, slipImage, payDate;
  final double rent, utilityTotal, commonFee, total;
  final double waterBill, elecBill;
  final double waterUnit, waterPricePerUnit;
  final double elecUnit, elecPricePerUnit;

  BillItem({
    required this.roomId,
    required this.dormId,
    required this.roomNumber,
    required this.building,
    required this.floor,
    required this.tenantId,
    required this.fullName,
    required this.phone,
    required this.month,
    required this.year,
    required this.dueDate,
    required this.paymentId,
    required this.paymentStatus,
    required this.statusKey,
    required this.statusLabel,
    required this.statusColor,
    required this.rent,
    required this.utilityTotal,
    required this.commonFee,
    required this.total,
    required this.slipImage,
    required this.payDate,
    required this.waterBill,
    required this.elecBill,
    required this.waterUnit,
    required this.waterPricePerUnit,
    required this.elecUnit,
    required this.elecPricePerUnit,
  });

  factory BillItem.fromJson(Map<String, dynamic> j) {
    int toInt(dynamic v, {int def = 0}) =>
        int.tryParse(v?.toString() ?? "") ?? def;
    double toDouble(dynamic v, {double def = 0}) =>
        double.tryParse(v?.toString() ?? "") ?? def;

    return BillItem(
      roomId: toInt(j["room_id"]),
      dormId: toInt(j["dorm_id"]),
      roomNumber: (j["room_number"] ?? "").toString(),
      building: (j["building"] ?? "A").toString(),
      floor: toInt(j["floor"]),
      tenantId: j["tenant_id"] == null ? null : toInt(j["tenant_id"]),
      fullName: j["full_name"]?.toString(),
      phone: j["phone"]?.toString(),
      month: toInt(j["month"]),
      year: toInt(j["year"]),
      dueDate: (j["due_date"] ?? "").toString(),
      paymentId: (j["payment_id"] == null || toInt(j["payment_id"]) == 0)
          ? null
          : toInt(j["payment_id"]),
      paymentStatus: j["payment_status"]?.toString(),
      statusKey: (j["status_key"] ?? "unpaid").toString(),
      statusLabel: (j["status_label"] ?? "ค้างชำระ").toString(),
      statusColor: (j["status_color"] ?? "#F44336").toString(),
      rent: toDouble(j["rent"]),
      utilityTotal: toDouble(j["utility_total"]),
      commonFee: toDouble(j["common_fee"]),
      total: toDouble(j["total"]),
      slipImage: j["slip_image"]?.toString(),
      payDate: j["pay_date"]?.toString(),
      waterBill: toDouble(j["water_bill"]),
      elecBill: toDouble(j["elec_bill"]),
      waterUnit: toDouble(j["water_unit"]),
      waterPricePerUnit:
          toDouble(j["water_price_per_unit"] ?? j["water_price"]),
      elecUnit: toDouble(j["elec_unit"]),
      elecPricePerUnit: toDouble(j["elec_price_per_unit"] ?? j["elec_price"]),
    );
  }

  String get roomDisplay => "$building-$roomNumber";
}

// --- 2. Main Admin Page ---
class BillAdminPage extends StatefulWidget {
  const BillAdminPage({super.key});

  @override
  State<BillAdminPage> createState() => _BillAdminPageState();
}

class _BillAdminPageState extends State<BillAdminPage> {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cIcon = Color(0xFF523D2D);
  static const Color cTextMain = Color(0xFF2A1F17);

  // 📏 มาตราส่วน Font ตามที่กำหนด
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle = 15.0;  // หัวข้อย่อย
  static const double fBody = 13.0;   // เนื้อหา
  static const double fCaption = 11.0;

  int dormId = 0, userId = 0;
  bool loading = true;
  String selectedStatusKey = "all";
  String selectedBuilding = "ทั้งหมด";
  String selectedFloor = "ทั้งหมด";
  late int selectedMonth, selectedYear;

  List<BillItem> items = [];
  List<String> buildingOptions = ["ทั้งหมด"];
  List<String> floorOptions = ["ทั้งหมด"];

  final List<Map<String, dynamic>> monthOptions = const [
    {"value": 1, "label": "ม.ค."},
    {"value": 2, "label": "ก.พ."},
    {"value": 3, "label": "มี.ค."},
    {"value": 4, "label": "เม.ย."},
    {"value": 5, "label": "พ.ค."},
    {"value": 6, "label": "มิ.ย."},
    {"value": 7, "label": "ก.ค."},
    {"value": 8, "label": "ส.ค."},
    {"value": 9, "label": "ก.ย."},
    {"value": 10, "label": "ต.ค."},
    {"value": 11, "label": "พ.ย."},
    {"value": 12, "label": "ธ.ค."},
  ];

  List<int> get yearOptions {
    final nowY = DateTime.now().year;
    return List.generate(5, (i) => nowY - 2 + i);
  }

  String _getMonthFull(int month) {
    const months = [
      "มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน",
      "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม"
    ];
    return months[month - 1];
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedMonth = now.month;
    selectedYear = now.year;
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    dormId = prefs.getInt("dorm_id") ??
        int.tryParse(prefs.getString("dorm_id") ?? "") ??
        0;
    if (dormId == 0) dormId = prefs.getInt("selected_dorm_id") ?? 0;
    userId = prefs.getInt("user_id") ?? 0;
    await fetchBills();
  }

  Future<void> fetchBills() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      final res = await http.post(
        Uri.parse(AppConfig.url("bills_api.php")),
        body: {
          "action": "list",
          "dorm_id": dormId.toString(),
          "month": selectedMonth.toString(),
          "year": selectedYear.toString(),
          "status": selectedStatusKey,
        },
      );

      final data = jsonDecode(res.body);
      if (data["ok"] == true) {
        final List list = data["data"] ?? [];
        final fetched = list
            .map((e) => BillItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();

        final bSet = {"ทั้งหมด"}, fSet = {"ทั้งหมด"};
        for (var it in fetched) {
          if (it.building.isNotEmpty) bSet.add(it.building);
          if (it.floor > 0) fSet.add(it.floor.toString());
        }

        setState(() {
          items = fetched;
          buildingOptions = bSet.toList()..sort();
          floorOptions = fSet.toList()
            ..sort((a, b) {
              if (a == "ทั้งหมด") return -1;
              if (b == "ทั้งหมด") return 1;
              return int.parse(a).compareTo(int.parse(b));
            });
        });
      }
    } catch (e) {
      debugPrint("Fetch Error: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> bulkSendBills() async {
    final confirm = await showDialog<bool>(
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
                  color: Color(0xFFE3F2FD),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Color(0xFF1976D2),
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "ยืนยันส่งบิล",
                style: GoogleFonts.kanit(
                  fontSize: fHeader,
                  fontWeight: FontWeight.w600,
                  color: cTextMain,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "ต้องการส่งบิลเดือน ${_getMonthFull(selectedMonth)} $selectedYear\nให้กับผู้เช่าทุกห้องใช่หรือไม่?",
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(
                  fontSize: fBody,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: cIcon,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        "ยืนยันส่ง",
                        style: GoogleFonts.kanit(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: fTitle,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: cAccent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        "ยกเลิก",
                        style: GoogleFonts.kanit(
                          color: cTextMain,
                          fontWeight: FontWeight.w600,
                          fontSize: fTitle,
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

    if (confirm != true) return;

    setState(() => loading = true);
    try {
      final res = await http.post(
        Uri.parse(AppConfig.url("bills_api.php")),
        body: {
          "action": "bulk_send",
          "dorm_id": dormId.toString(),
          "month": selectedMonth.toString(),
          "year": selectedYear.toString(),
        },
      );

      final data = jsonDecode(res.body);
      if (data["ok"] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("ส่งบิลสำเร็จ ${data['created']} ห้อง", style: GoogleFonts.kanit(fontSize: fBody)),
            backgroundColor: cTextMain,
          ),
        );
        await fetchBills();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("ผิดพลาด: ${data['message']}", style: GoogleFonts.kanit(fontSize: fBody))),
        );
        if (mounted) setState(() => loading = false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("เกิดข้อผิดพลาดในการส่งข้อมูล", style: GoogleFonts.kanit(fontSize: fBody))),
      );
      if (mounted) setState(() => loading = false);
    }
  }

  Color _statusChipColor(String key) {
    switch (key) {
      case "all":
        return const Color(0xFF6B4E3D);
      case "paid":
        return const Color(0xFF6DAE74);
      case "unpaid":
        return const Color(0xFFE57C7C);
      case "no_tenant":
        return const Color(0xFFB9C9B8);
      default:
        return Colors.grey;
    }
  }

  Color _statusChipBg(String key) {
    switch (key) {
      case "all":
        return const Color(0xFFF3ECE7);
      case "paid":
        return const Color(0xFFF6FBF7);
      case "unpaid":
        return const Color(0xFFFFF6F6);
      case "no_tenant":
        return const Color(0xFFF7FAF7);
      default:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = items.where((it) {
      bool bOk = selectedBuilding == "ทั้งหมด" || it.building == selectedBuilding;
      bool fOk = selectedFloor == "ทั้งหมด" || it.floor.toString() == selectedFloor;
      return bOk && fOk;
    }).toList();

    Map<String, List<BillItem>> groupedByBuilding = {};
    for (var item in filteredItems) {
      groupedByBuilding.putIfAbsent(item.building, () => []).add(item);
    }
    var sortedBuildings = groupedByBuilding.keys.toList()..sort();

    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 50,
        elevation: 0.5,
        backgroundColor: Colors.white,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          "จัดการบิล",
          style: GoogleFonts.kanit(
            color: cTextMain,
            fontWeight: FontWeight.w600,
            fontSize: fHeader,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.send_rounded, color: cIcon, size: 22),
            onPressed: bulkSendBills,
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: fetchBills,
        color: cTextMain,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  _buildClassicFilters(),
                  _buildStatusScroll(),
                ],
              ),
            ),
            if (loading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(
                    color: cTextMain,
                    strokeWidth: 2,
                  ),
                ),
              )
            else if (filteredItems.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    "ไม่มีข้อมูล",
                    style: GoogleFonts.kanit(
                      fontSize: fTitle,
                      color: cTextMain,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
              )
            else
              for (var bName in sortedBuildings) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.business_rounded, size: 18, color: cIcon),
                        const SizedBox(width: 8),
                        Text(
                          "ตึก $bName",
                          style: GoogleFonts.kanit(
                            fontSize: fTitle,
                            fontWeight: FontWeight.w600,
                            color: cTextMain,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Divider(
                            thickness: 1,
                            color: cTextMain.withOpacity(0.1),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "${groupedByBuilding[bName]!.length} ห้อง",
                          style: GoogleFonts.kanit(
                            fontSize: fBody,
                            color: Colors.black54,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _buildModernBillCard(groupedByBuilding[bName]![index]),
                      childCount: groupedByBuilding[bName]!.length,
                    ),
                  ),
                ),
              ],
            const SliverToBoxAdapter(child: SizedBox(height: 30)),
          ],
        ),
      ),
    );
  }

  Widget _buildModernBillCard(BillItem it) {
    bool isNoTenant = it.statusKey == "no_tenant" || it.tenantId == null;
    Color sColor;
    try {
      sColor = Color(int.parse(it.statusColor.replaceFirst('#', '0xFF')));
    } catch (_) {
      sColor = isNoTenant ? Colors.blueGrey : Colors.red;
    }
    bool isSent = it.paymentId != null && it.paymentId! > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () async {
          final up = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BillDetailPage(item: it, isAdmin: true),
            ),
          );
          if (up == true) fetchBills();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: sColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isNoTenant ? Icons.door_front_door_outlined : Icons.meeting_room_rounded,
                      color: sColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "ห้อง ${it.roomNumber}",
                          style: GoogleFonts.kanit(
                            fontWeight: FontWeight.w600,
                            fontSize: fTitle,
                            color: cTextMain,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "${it.total.toStringAsFixed(0)} ฿",
                        style: GoogleFonts.kanit(
                          fontWeight: FontWeight.w600,
                          fontSize: fTitle,
                          color: cTextMain,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: sColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: sColor.withOpacity(0.2)),
                        ),
                        child: Text(
                          it.statusLabel,
                          style: GoogleFonts.kanit(
                            color: sColor,
                            fontSize: 10,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 20, thickness: 0.5),
              Row(
                children: [
                  _badge(
                    isSent ? "ส่งบิลแล้ว" : "ยังไม่ส่งบิล",
                    isSent ? const Color(0xFF1976D2) : const Color(0xFFF57C00),
                    isSent ? Icons.send : Icons.hourglass_empty,
                  ),
                  if (it.slipImage != null && it.slipImage!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _badge("แจ้งชำระแล้ว", const Color(0xFF388E3C), Icons.check_circle_outline)
                  ],
                  const Spacer(),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.grey),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClassicFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              _dropClassic(
                label: "เดือน",
                val: selectedMonth,
                items: monthOptions.map((m) => DropdownMenuItem(
                  value: m["value"] as int,
                  child: Text(_getMonthFull(m["value"] as int), style: GoogleFonts.kanit(fontSize: fBody)),
                )).toList(),
                on: (v) { setState(() => selectedMonth = v!); fetchBills(); },
              ),
              const SizedBox(width: 8),
              _dropClassic(
                label: "ปี",
                val: selectedYear,
                items: yearOptions.map((y) => DropdownMenuItem(
                  value: y,
                  child: Text((y + 543).toString(), style: GoogleFonts.kanit(fontSize: fBody)),
                )).toList(),
                on: (v) { setState(() => selectedYear = v!); fetchBills(); },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _dropClassic(
                label: "ตึก",
                val: selectedBuilding,
                items: buildingOptions.map((b) => DropdownMenuItem(
                  value: b,
                  child: Text(b, style: GoogleFonts.kanit(fontSize: fBody)),
                )).toList(),
                on: (v) => setState(() => selectedBuilding = v!),
              ),
              const SizedBox(width: 8),
              _dropClassic(
                label: "ชั้น",
                val: selectedFloor,
                items: floorOptions.map((f) => DropdownMenuItem(
                  value: f,
                  child: Text(f, style: GoogleFonts.kanit(fontSize: fBody)),
                )).toList(),
                on: (v) => setState(() => selectedFloor = v!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dropClassic<T>({required String label, required T val, required List<DropdownMenuItem<T>> items, required ValueChanged<T?> on}) {
    return Expanded(
      child: SizedBox(
        height: 50,
        child: DropdownButtonFormField<T>(
          isExpanded: true,
          initialValue: val,
          items: items,
          onChanged: on,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
            labelText: label,
            labelStyle: GoogleFonts.kanit(color: cIcon, fontSize: 12, fontWeight: FontWeight.normal),
            filled: true,
            fillColor: cBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusScroll() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 12, top: 2),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _statusChip("all", "ทั้งหมด"),
                _statusChip("paid", "ชำระแล้ว"),
                _statusChip("unpaid", "ค้างชำระ"),
                _statusChip("no_tenant", "ห้องว่าง"),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String key, String label) {
    final bool sel = selectedStatusKey == key;
    final Color color = _statusChipColor(key);
    return GestureDetector(
      onTap: () { if (selectedStatusKey != key) { setState(() => selectedStatusKey = key); fetchBills(); } },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? color : _statusChipBg(key),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? color : color.withOpacity(0.45), width: 1.15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sel) ...[const Icon(Icons.check_circle, size: 15, color: Colors.white), const SizedBox(width: 6)],
            Text(label, style: GoogleFonts.kanit(color: sel ? Colors.white : color, fontWeight: FontWeight.normal, fontSize: fTitle)),
          ],
        ),
      ),
    );
  }

  Widget _badge(String t, Color c, IconData i) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withOpacity(0.2))),
      child: Row(
        children: [
          Icon(i, size: 12, color: c),
          const SizedBox(width: 4),
          Text(t, style: GoogleFonts.kanit(color: c, fontSize: 10, fontWeight: FontWeight.normal)),
        ],
      ),
    );
  }
}