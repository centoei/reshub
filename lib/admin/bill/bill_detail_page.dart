import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config.dart';
import 'bill_admin_page.dart';

class BillDetailPage extends StatefulWidget {
  final BillItem item;
  final bool isAdmin;

  const BillDetailPage({
    super.key,
    required this.item,
    this.isAdmin = false,
  });

  @override
  State<BillDetailPage> createState() => _BillDetailPageState();
}

class _BillDetailPageState extends State<BillDetailPage> {
  static const Color cBg = Color(0xFFF4EFE6);       // ครีมสว่าง
  static const Color cAccent = Color(0xFFDCD2C1);   // ครีมเข้ม
  static const Color cIcon = Color(0xFF523D2D);     // น้ำตาลไอคอน
  static const Color cTextMain = Color(0xFF2A1F17); // Deep Coffee

  // 📏 มาตราส่วน Font ตามที่กำหนด
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle = 15.0;  // หัวข้อย่อย
  static const double fBody = 13.0;   // เนื้อหา
  static const double fCaption = 11.0;

  late BillItem it;
  late String statusKey;
  bool loading = true;
  bool saving = false;
  int userId = 0;

  @override
  void initState() {
    super.initState();
    it = widget.item;
    _updateStatusKey();
    _init();
  }

  void _updateStatusKey() {
    statusKey = (it.statusKey ?? "unpaid").toLowerCase().trim();
    const validStatuses = ["paid", "unpaid", "overdue", "no_tenant"];
    if (!validStatuses.contains(statusKey)) {
      statusKey = "unpaid";
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getInt("user_id") ?? int.tryParse(prefs.getString("user_id") ?? "") ?? 0;
    await _refreshDetail();
  }

  double get _calculateTotal {
    double sum = it.rent + it.waterBill + it.elecBill + it.commonFee;
    double otherCharges = it.utilityTotal - (it.waterBill + it.elecBill);
    if (otherCharges > 0.1) {
      sum += otherCharges;
    }
    if (sum == 0 && it.total > 0) return it.total;
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 50,
        title: Text("รายละเอียดบิล",
            style: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: fHeader, color: cTextMain)),
        centerTitle: true,
        elevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: cTextMain,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: cTextMain, strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _refreshDetail,
              color: cTextMain,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRoomInfoCard(),
                    const SizedBox(height: 16),
                    Text("สรุปค่าใช้จ่าย", style: GoogleFonts.kanit(fontSize: fTitle, fontWeight: FontWeight.w600, color: cTextMain)),
                    const SizedBox(height: 8),
                    _buildBillSummaryCard(),
                    const SizedBox(height: 16),
                    Text("หลักฐานการชำระเงิน", style: GoogleFonts.kanit(fontSize: fTitle, fontWeight: FontWeight.w600, color: cTextMain)),
                    const SizedBox(height: 8),
                    _buildSlipBox(),
                    const SizedBox(height: 24),
                    _buildActionSection(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRoomInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cTextMain, borderRadius: BorderRadius.circular(15)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("ห้อง ${it.roomDisplay}", style: GoogleFonts.kanit(color: Colors.white, fontSize: fHeader, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text("ผู้เช่า: ${it.fullName ?? 'ไม่มีข้อมูล'}", style: GoogleFonts.kanit(color: Colors.white.withOpacity(0.8), fontSize: fBody)),
        ],
      ),
    );
  }

  Widget _buildBillSummaryCard() {
    double otherService = it.utilityTotal - (it.waterBill + it.elecBill);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)]),
      child: Column(
        children: [
          _rowItem("ค่าเช่าห้อง", it.rent),
          if (it.commonFee > 0) _rowItem("ค่าส่วนกลาง", it.commonFee),
          _rowItemWithDetail("ค่าน้ำ", it.waterBill, it.waterUnit, it.waterPricePerUnit),
          _rowItemWithDetail("ค่าไฟ", it.elecBill, it.elecUnit, it.elecPricePerUnit),
          if (otherService > 0.1) _rowItem("ค่าบริการอื่นๆ", otherService),
          const Divider(height: 20, thickness: 0.5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("รวมสุทธิ", style: GoogleFonts.kanit(fontSize: fBody, fontWeight: FontWeight.normal, color: cIcon)),
              Text("${_calculateTotal.toStringAsFixed(0)} บาท",
                  style: GoogleFonts.kanit(fontSize: 22, fontWeight: FontWeight.w600, color: cTextMain)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rowItem(String label, double value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: GoogleFonts.kanit(color: cIcon, fontSize: fBody)),
          Text("${value.toStringAsFixed(0)} บาท", style: GoogleFonts.kanit(fontWeight: FontWeight.normal, fontSize: fBody, color: cTextMain)),
        ]),
      );

  Widget _rowItemWithDetail(String label, double totalValue, double unit, double pricePerUnit) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.kanit(color: cIcon, fontSize: fBody),
                children: [
                  TextSpan(text: label),
                  if (unit > 0)
                    TextSpan(
                      text: " (${unit.toStringAsFixed(0)} หน่วย x ${pricePerUnit.toStringAsFixed(0)} บาท)",
                      style: GoogleFonts.kanit(color: Colors.grey.shade600, fontSize: fCaption),
                    ),
                ],
              ),
            ),
          ),
          Text("${totalValue.toStringAsFixed(0)} บาท",
              style: GoogleFonts.kanit(fontWeight: FontWeight.normal, fontSize: fBody, color: cTextMain)),
        ]),
      );

  Widget _buildSlipBox() {
    final imgUrl = _toImageUrl((it.slipImage ?? "").trim());
    return GestureDetector(
      onTap: imgUrl.isEmpty ? null : () => _openImageViewer(imgUrl),
      child: Container(
        height: 220,
        width: double.infinity,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cAccent.withOpacity(0.5))),
        child: imgUrl.isEmpty
            ? Center(child: Text("ยังไม่มีสลิปชำระเงิน", style: GoogleFonts.kanit(color: Colors.grey, fontSize: fBody)))
            : ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imgUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 40)),
                ),
              ),
      ),
    );
  }

  Widget _buildActionSection() {
    if (widget.isAdmin) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("จัดการสถานะบิล", style: GoogleFonts.kanit(fontSize: fTitle, fontWeight: FontWeight.w600, color: cTextMain)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: statusKey,
            style: GoogleFonts.kanit(fontSize: fBody, color: cTextMain, fontWeight: FontWeight.normal),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: cAccent, width: 1.5)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: cTextMain, width: 1.5)),
            ),
            items: const [
              DropdownMenuItem(value: "paid", child: Text("ชำระแล้ว")),
              DropdownMenuItem(value: "unpaid", child: Text("ค้างชำระ")),
              DropdownMenuItem(value: "overdue", child: Text("เลยกำหนด")),
              DropdownMenuItem(value: "no_tenant", child: Text("ว่าง")),
            ],
            onChanged: (v) => setState(() => statusKey = v ?? statusKey),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: saving ? null : _saveStatus,
              style: ElevatedButton.styleFrom(backgroundColor: cTextMain, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              child: saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text("บันทึกการเปลี่ยนแปลง", style: GoogleFonts.kanit(color: Colors.white, fontSize: fTitle, fontWeight: FontWeight.normal)),
            ),
          ),
        ],
      );
    } else {
      // ส่วนของผู้เช่า (Tenant View)
      Color statusColor = statusKey == "paid" ? const Color(0xFF2E7D32) : (statusKey == "overdue" ? const Color(0xFFE65100) : const Color(0xFFC62828));
      String statusText = statusKey == "paid" ? "ชำระเงินเรียบร้อยแล้ว" : (statusKey == "overdue" ? "เลยกำหนดชำระเงิน" : "ค้างชำระ");

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: statusColor.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(statusKey == "paid" ? Icons.check_circle_outline : Icons.info_outline, color: statusColor, size: 26),
            const SizedBox(width: 12),
            Text(statusText, style: GoogleFonts.kanit(color: statusColor, fontWeight: FontWeight.w600, fontSize: fTitle)),
          ],
        ),
      );
    }
  }

  String _toImageUrl(String raw) => raw.isEmpty ? "" : (raw.startsWith("http") ? raw : AppConfig.url(raw));

  Future<void> _refreshDetail() async {
    final pid = (it.paymentId ?? 0);
    if (pid <= 0) {
      if (mounted) setState(() => loading = false);
      return;
    }

    try {
      final res = await http.post(Uri.parse(AppConfig.url("bills_api.php")), body: {
        "action": "getPaymentById",
        "payment_id": pid.toString(),
      });

      final data = jsonDecode(res.body);
      if (data["ok"] == true && data["data"] != null) {
        final Map<String, dynamic> result = Map<String, dynamic>.from(data["data"]);
        
        if (mounted) {
          setState(() {
            it = BillItem.fromJson(result);
            _updateStatusKey();
          });
        }
      }
    } catch (e) {
      debugPrint("Refresh Error: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _saveStatus() async {
    setState(() => saving = true);
    try {
      final res = await http.post(Uri.parse(AppConfig.url("bills_api.php")), body: {
        "action": "set_status",
        "dorm_id": it.dormId.toString(),
        "room_id": it.roomId.toString(),
        "month": it.month.toString(),
        "year": it.year.toString(),
        "status_key": statusKey,
        "user_id": userId.toString(),
      });
      final j = jsonDecode(res.body);
      if (j["ok"] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("บันทึกสำเร็จ", style: GoogleFonts.kanit(fontSize: fBody))));
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _openImageViewer(String imgUrl) {
    showDialog(
        context: context,
        builder: (_) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: EdgeInsets.zero,
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                InteractiveViewer(child: Center(child: Image.network(imgUrl))),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context)),
                ),
              ],
            )));
  }
}