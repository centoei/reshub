import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config.dart';
import 'expense_page.dart';

class BillPage extends StatefulWidget {
  const BillPage({super.key});

  @override
  State<BillPage> createState() => _BillPageState();
}

class _BillPageState extends State<BillPage> {
  // 📏 Typography System
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle  = 15.0; // หัวข้อย่อย
  static const double fBody   = 13.0; // เนื้อหา
  static const double fDetail = 13.0;
  static const double fCaption = 11.0;

  // 🎨 Palette: Vanilla Teddy Style
  static const Color _bgColor = Color(0xFFF4EFE6);
  static const Color _cardColor = Colors.white;
  static const Color _textColor = Color(0xFF523D2D);
  static const Color _mutedColor = Color(0xFF7D6552);
  static const Color _lineColor = Color(0xFFD7CCC8);

  final picker = ImagePicker();
  File? slip;

  bool _loading = true; // ✅ ตรวจสอบชื่อตัวแปรให้ตรงกัน
  bool _submitting = false;
  bool _pickingSlip = false;
  bool _noBill = false;

  String get apiUrl => AppConfig.url("payment.php");

  int _userId = 0;
  int _paymentId = 0;
  int month = DateTime.now().month;
  int year = DateTime.now().year;

  String roomText = "ไม่มีข้อมูล";
  double rent = 0, water = 0, electric = 0, total = 0;
  double waterUnit = 0, waterPricePerUnit = 0;
  double electricUnit = 0, electricPricePerUnit = 0;

  String status = "unpaid";
  String? slipFromServer;
  String? payDate;
  List<Map<String, dynamic>> bankAccounts = [];

  final _moneyFmt = NumberFormat("#,##0", "en_US");
  late DateFormat _thaiMonthFmt;

  bool get _hasServerSlip => (slipFromServer != null && slipFromServer!.trim().isNotEmpty);
  bool get _isLockedPaid => ["verified", "paid", "done", "pending"].contains(status.toLowerCase().trim());

  @override
  void initState() {
    super.initState();
    _initThaiLocaleThenLoad();
  }

  Future<void> _initThaiLocaleThenLoad() async {
    try {
      await initializeDateFormatting('th_TH', null);
    } catch (_) {}
    _thaiMonthFmt = DateFormat.MMMM('th_TH');
    if (mounted) {
      setState(() {});
      await _loadBill();
    }
  }

  Future<void> _loadBill() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _noBill = false;
      slip = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getInt("user_id") ?? int.tryParse(prefs.getString("user_id") ?? "0") ?? 0;

      if (_userId <= 0) {
        setState(() => _noBill = true);
        return;
      }

      final res = await http.post(
        Uri.parse(apiUrl),
        body: {
          "action": "get",
          "user_id": _userId.toString(),
          "month": month.toString(),
          "year": year.toString(),
        },
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (data is Map && data["success"] == true) {
        final p = Map<String, dynamic>.from(data["data"] ?? {});
        setState(() {
          _paymentId = int.tryParse("${p["payment_id"]}") ?? 0;
          roomText = p["room_number"]?.toString() ?? "ไม่ทราบเลขห้อง";
          water = _toDouble(p["water_price"]);
          electric = _toDouble(p["electric_price"]);
          waterUnit = _toDouble(p["water_unit"]);
          waterPricePerUnit = _toDouble(p["water_rate"]);
          electricUnit = _toDouble(p["electric_unit"]);
          electricPricePerUnit = _toDouble(p["electric_rate"]);
          total = _toDouble(p["total_price"]);
          rent = total - water - electric;
          status = (p["status"] ?? "unpaid").toString();
          slipFromServer = p["slip_image"]?.toString();
          payDate = p["pay_date"]?.toString();
          bankAccounts = (p["accounts"] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
          _noBill = false;
        });
      } else {
        setState(() => _noBill = true);
      }
    } catch (e) {
      setState(() => _noBill = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _toDouble(dynamic v) => double.tryParse(v.toString().replaceAll(",", "")) ?? 0;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: GoogleFonts.kanit()), behavior: SnackBarBehavior.floating));
  }

  String _statusText(String s) {
    final v = s.toLowerCase().trim();
    if (v == "verified" || v == "paid" || v == "done") return "ชำระแล้ว";
    if (v == "pending") return "รอตรวจสอบ";
    return "ยังไม่ชำระ";
  }

  Color _statusColor(String s) {
    final v = s.toLowerCase().trim();
    if (v == "verified" || v == "paid" || v == "done") return Colors.green;
    if (v == "pending") return Colors.orange;
    return Colors.redAccent;
  }

  String _formatSlipDate(dynamic raw) {
    final text = (raw ?? "").toString().trim();
    if (text.isEmpty) return "";
    try {
      final dt = DateTime.parse(text.replaceFirst(" ", "T")).toLocal();
      const months = ["ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."];
      return "${dt.day} ${months[dt.month - 1]} ${dt.year + 543} • ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} น.";
    } catch (_) { return text; }
  }

  String _thaiMonthText() => "${_thaiMonthFmt.format(DateTime(year, month, 1))} ${year + 543}";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        toolbarHeight: 50,
        backgroundColor: Colors.white,
        centerTitle: true,
        elevation: 0.5,
        title: Text("บิลค่าเช่าห้อง", style: GoogleFonts.kanit(color: _textColor, fontSize: fHeader, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpensePage())),
            icon: const Icon(Icons.receipt_long, color: _textColor, size: 20),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _textColor, strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _loadBill,
              color: _textColor,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                children: [
                  _buildMonthPicker(),
                  const SizedBox(height: 10),
                  if (_noBill) _buildNoDataView() else _buildMainBillCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildMainBillCard() {
    final String slipDateText = _formatSlipDate(payDate);
    final Color statusColor = _statusColor(status);
    final String statusText = _statusText(status);
    final bool isPaid = ["verified", "paid", "done"].contains(status.toLowerCase());
    final String imageUrl = _hasServerSlip ? AppConfig.url(slipFromServer!) : "";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: _lineColor)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: const BoxDecoration(color: _textColor, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
            child: Row(
              children: [
                Expanded(child: RichText(text: TextSpan(children: [
                  TextSpan(text: "ห้อง ", style: GoogleFonts.kanit(color: Colors.white70, fontSize: fBody)),
                  TextSpan(text: roomText, style: GoogleFonts.kanit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: fTitle)),
                ]))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(999)),
                  child: Row(children: [
                    Icon(isPaid ? Icons.check_circle_rounded : Icons.access_time_filled_rounded, size: 15, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(statusText, style: GoogleFonts.kanit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                  ]),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                if (_hasServerSlip || slip != null) ...[
                  Stack(
                    children: [
                      InkWell(
                        onTap: () {
                          if (_hasServerSlip) Navigator.push(context, MaterialPageRoute(builder: (_) => SlipPreviewPage(imageUrl: imageUrl)));
                        },
                        child: Container(
                          height: 250, 
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _lineColor),
                            color: Colors.grey.shade50,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: _hasServerSlip 
                              ? Image.network(imageUrl, fit: BoxFit.contain) 
                              : Image.file(slip!, fit: BoxFit.contain), 
                          ),
                        ),
                      ),
                      if (status.toLowerCase() == "pending" && _hasServerSlip)
                        Positioned(top: 8, right: 8, child: GestureDetector(
                          onTap: () async { if (await _showConfirmDeleteDialog()) _deleteServerSlip(); },
                          child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close_rounded, color: Colors.white, size: 20)),
                        )),
                      if (slip != null && !_hasServerSlip)
                        Positioned(top: 8, right: 8, child: GestureDetector(
                          onTap: () => setState(() => slip = null),
                          child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle), child: const Icon(Icons.close_rounded, color: Colors.white, size: 20)),
                        )),
                    ],
                  ),
                  if (slipDateText.isNotEmpty && _hasServerSlip) ...[
                    const SizedBox(height: 10),
                    Text("วันที่ส่งสลิป: $slipDateText", style: GoogleFonts.kanit(color: _mutedColor, fontSize: fCaption, fontWeight: FontWeight.w500)),
                  ],
                  const SizedBox(height: 12),
                ] else if (!_isLockedPaid) ...[
                  InkWell(
                    onTap: pickSlip,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 165,
                      width: double.infinity,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: _lineColor), color: _bgColor.withOpacity(0.18)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.add_photo_alternate_rounded, color: _mutedColor, size: 42),
                        const SizedBox(height: 8),
                        Text("แตะเพื่อแนบรูปภาพสลิป", style: GoogleFonts.kanit(fontSize: fBody, color: _mutedColor, fontWeight: FontWeight.w500)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _summaryTile("ค่าเช่า", "${_moneyFmt.format(rent)} ฿"),
                const SizedBox(height: 8),
                _summaryTile("ค่าน้ำ", "${_moneyFmt.format(water)} ฿", sub: "${waterUnit.toStringAsFixed(0)} หน่วย × ${_moneyFmt.format(waterPricePerUnit)} ฿/หน่วย"),
                const SizedBox(height: 8),
                _summaryTile("ค่าไฟ", "${_moneyFmt.format(electric)} ฿", sub: "${electricUnit.toStringAsFixed(0)} หน่วย × ${_moneyFmt.format(electricPricePerUnit)} ฿/หน่วย"),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: _bgColor.withOpacity(0.35), borderRadius: BorderRadius.circular(14), border: Border.all(color: _lineColor)),
                  child: Row(children: [
                    Expanded(child: Text("รวมสุทธิ", style: GoogleFonts.kanit(color: _textColor, fontWeight: FontWeight.w600, fontSize: fTitle))),
                    Text("${_moneyFmt.format(total)} ฿", style: GoogleFonts.kanit(color: _textColor, fontWeight: FontWeight.w900, fontSize: 22)),
                  ]),
                ),
                if (slip != null && !_isLockedPaid) ...[
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, height: 46, child: ElevatedButton(
                    onPressed: _submitting ? null : _submitSlip,
                    style: ElevatedButton.styleFrom(backgroundColor: _textColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: Text(_submitting ? "กำลังส่งข้อมูล..." : "ยืนยันการชำระเงิน", style: GoogleFonts.kanit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: fBody)),
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _lineColor.withOpacity(0.5))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: _textColor), onPressed: () { setState(() { if (month == 1) { month = 12; year--; } else { month--; } }); _loadBill(); }),
        Text(_thaiMonthText(), style: GoogleFonts.kanit(fontSize: fBody, fontWeight: FontWeight.w600, color: _textColor)),
        IconButton(icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: _textColor), onPressed: () { setState(() { if (month == 12) { month = 1; year++; } else { month++; } }); _loadBill(); }),
      ]),
    );
  }

  Widget _buildNoDataView() {
    String monthName = _thaiMonthFmt.format(DateTime(year, month, 1));
    return Container(padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.receipt_long_outlined, size: 80, color: _mutedColor.withOpacity(0.1)),
      const SizedBox(height: 24),
      Text("ยังไม่มีข้อมูลบิล", style: GoogleFonts.kanit(fontSize: fTitle, fontWeight: FontWeight.w600, color: _textColor.withOpacity(0.8))),
      const SizedBox(height: 8),
      Text("ประจำเดือน $monthName พ.ศ. ${year + 543}", style: GoogleFonts.kanit(fontSize: fBody, color: Colors.grey.shade500)),
    ]));
  }

  Widget _summaryTile(String title, String price, {String? sub}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _lineColor)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Row(children: [
          Text(title, style: GoogleFonts.kanit(fontSize: fBody, fontWeight: FontWeight.w500, color: _textColor)),
          if (sub != null && sub.trim().isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.kanit(fontSize: fCaption, color: Colors.grey))),
          ],
        ])),
        const SizedBox(width: 10),
        Text(price, style: GoogleFonts.kanit(fontSize: fBody, fontWeight: FontWeight.w600, color: _textColor)),
      ]),
    );
  }

  Future<void> pickSlip() async {
    if (_pickingSlip || _isLockedPaid) return;
    setState(() => _pickingSlip = true);
    final XFile? img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (img != null) setState(() => slip = File(img.path));
    setState(() => _pickingSlip = false);
  }

  Future<void> _submitSlip() async {
    if (slip == null || _submitting) return;
    if (await _showConfirmSendDialog()) {
      setState(() => _submitting = true);
      try {
        final request = http.MultipartRequest("POST", Uri.parse(apiUrl));
        request.fields['action'] = "pay";
        request.fields['user_id'] = _userId.toString();
        request.fields['payment_id'] = _paymentId.toString();
        request.files.add(await http.MultipartFile.fromPath('slip', slip!.path));
        final response = await http.Response.fromStream(await request.send());
        if (jsonDecode(response.body)["success"] == true) {
          _toast("ส่งหลักฐานสำเร็จ ✅ รอนิติบุคคลตรวจสอบ");
          _loadBill();
        } else { _toast("ส่งหลักฐานไม่สำเร็จ"); }
      } catch (_) { _toast("เกิดข้อผิดพลาดในการส่ง"); }
      finally { setState(() => _submitting = false); }
    }
  }

  Future<void> _deleteServerSlip() async {
    try {
      final res = await http.post(Uri.parse(apiUrl), body: {"action": "delete_slip", "user_id": _userId.toString(), "payment_id": _paymentId.toString()});
      if (jsonDecode(res.body)["success"] == true) { _toast("ยกเลิกสลิปเรียบร้อย"); _loadBill(); }
    } catch (_) {}
  }

  Future<bool> _showConfirmDeleteDialog() async {
    return await showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 80, height: 80, decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle), child: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 45)),
        const SizedBox(height: 20),
        Text("ยืนยันการลบ", style: GoogleFonts.kanit(fontSize: fTitle, fontWeight: FontWeight.w600, color: _textColor)),
        const SizedBox(height: 10),
        Text("คุณต้องการลบหลักฐานการโอน\nใช่หรือไม่?", textAlign: TextAlign.center, style: GoogleFonts.kanit(fontSize: fBody, color: Colors.grey)),
        const SizedBox(height: 30),
        Row(children: [
          Expanded(child: ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: _textColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Text("ยืนยันลบ", style: GoogleFonts.kanit(color: Colors.white, fontWeight: FontWeight.w600)))),
          const SizedBox(width: 12),
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), style: OutlinedButton.styleFrom(side: const BorderSide(color: _lineColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Text("ยกเลิก", style: GoogleFonts.kanit(color: _textColor, fontWeight: FontWeight.w600)))),
        ])
      ]))
    )) ?? false;
  }

  Future<bool> _showConfirmSendDialog() async {
    return await showDialog(context: context, builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 80, height: 80, decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle), child: const Icon(Icons.send_rounded, color: Colors.blueAccent, size: 40)),
        const SizedBox(height: 20),
        const Text("ยืนยันการส่งสลิป", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _textColor)),
        const SizedBox(height: 10),
        const Text("คุณตรวจสอบความถูกต้อง\nของรูปภาพสลิปเรียบร้อยแล้วใช่หรือไม่?", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 30),
        Row(children: [
          Expanded(child: ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: _textColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Text("ยืนยัน", style: GoogleFonts.kanit(color: Colors.white, fontWeight: FontWeight.w600)))),
          const SizedBox(width: 12),
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), style: OutlinedButton.styleFrom(side: const BorderSide(color: _lineColor), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: Text("ยกเลิก", style: GoogleFonts.kanit(color: _textColor, fontWeight: FontWeight.w600)))),
        ])
      ]))
    )) ?? false;
  }
}

class SlipPreviewPage extends StatelessWidget {
  final String imageUrl;
  const SlipPreviewPage({super.key, required this.imageUrl});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, 
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white), title: Text("สลิป", style: GoogleFonts.kanit(color: Colors.white, fontSize: 18))), 
      body: Center(child: InteractiveViewer(child: Image.network(imageUrl, fit: BoxFit.contain)))
    );
  }
}