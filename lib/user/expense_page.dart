import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config.dart';

enum YearMetric { paid, water, electric }

// =============================================================
// 1. หน้าสรุปรายปี (ExpensePage) - ปรับปรุงเป็นกราฟเส้น
// =============================================================
class ExpensePage extends StatefulWidget {
  const ExpensePage({super.key});

  @override
  State<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends State<ExpensePage> {
  static const Color _bgColor = Color(0xFFF4EFE6);
  static const Color _textColor = Color(0xFF523D2D);
  static const Color _mutedColor = Color(0xFF8D7456);
  static const Color _lineColor = Color(0xFFDCD2C1);
  static const Color _primaryColor = Color(0xFF523D2D);

  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle  = 15.0; // หัวข้อย่อย
  static const double fBody   = 13.0; // เนื้อหา
  static const double fCaption = 11.0;

  int selectedYear = DateTime.now().year;
  int userId = 0;
  bool loading = true;
  String? loadError;
  YearMetric yearMetric = YearMetric.paid;

  final money = NumberFormat("#,##0", "en_US");

  final monthsText = const [
    "มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน",
    "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม"
  ];

  final monthsShort = const [
    "", "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.",
    "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."
  ];

  double yearPaidSum = 0;
  List<Map<String, dynamic>> yearMonths = [];

  int _be(int ad) => ad + 543;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getInt("user_id") ?? int.tryParse(prefs.getString("user_id") ?? "0") ?? 0;
    await fetchYearSummary();
  }

  Future<void> fetchYearSummary() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      loadError = null;
    });

    try {
      final uri = Uri.parse(AppConfig.url("finance_api.php")).replace(
        queryParameters: {
          "action": "summary_income",
          "user_id": userId.toString(),
          "year": selectedYear.toString(),
        },
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      final data = jsonDecode(res.body);

      if (data["ok"] == true || data["success"] == true) {
        setState(() {
          yearPaidSum = (data["received_income"] as num?)?.toDouble() ?? 0;
          yearMonths = List<Map<String, dynamic>>.from(data["months"] ?? []);
        });
      } else {
        throw Exception(data["message"] ?? "โหลดข้อมูลไม่สำเร็จ");
      }
    } catch (e) {
      setState(() => loadError = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  double _yearValue(int m) {
    final row = yearMonths.firstWhere((e) => (e["month"] ?? 0) == m, orElse: () => {});
    if (yearMetric == YearMetric.paid) return (row["received_income"] as num?)?.toDouble() ?? 0;
    if (yearMetric == YearMetric.water) return (row["water"] as num?)?.toDouble() ?? 0;
    return (row["electric"] as num?)?.toDouble() ?? 0;
  }

  double _yearMonthsMax() {
    double m = 0;
    for (int i = 1; i <= 12; i++) {
      double v = _yearValue(i);
      if (v > m) m = v;
    }
    return m > 0 ? m : 1000;
  }

  int _yearBillCount(int m) {
    final row = yearMonths.firstWhere((e) => (e["month"] ?? 0) == m, orElse: () => {});
    return int.tryParse("${row["bill_count"] ?? 0}") ?? 0;
  }

  String _compact(double v) => v.abs() >= 1000 ? "${(v / 1000).toStringAsFixed(1)}K" : v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        centerTitle: true,
        elevation: 0.5,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 28, color: _textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "สรุปค่าใช้จ่ายรายปี",
          style: GoogleFonts.kanit(color: _textColor, fontWeight: FontWeight.w600, fontSize: fHeader),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
          : loadError != null ? _buildErrorState() : _buildBody(),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildYearSelector(),
        const SizedBox(height: 16),
        _buildHeroYearPaidCard(),
        const SizedBox(height: 20),
        Text(
          "สถิติรายปี ${_be(selectedYear)}",
          style: GoogleFonts.kanit(fontSize: fTitle, fontWeight: FontWeight.w600, color: _textColor),
        ),
        const SizedBox(height: 12),
        _buildYearMetricToggle(),
        const SizedBox(height: 16),
        _buildYearMetricChart(),
        const SizedBox(height: 20),
        for (int m = 1; m <= 12; m++) ...[
          _buildYearMonthRow(m),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildYearSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _lineColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: selectedYear,
          isExpanded: true,
          dropdownColor: Colors.white,
          style: GoogleFonts.kanit(color: _textColor, fontSize: fBody, fontWeight: FontWeight.w600),
          items: [2024, 2025, 2026, 2027].map((y) => DropdownMenuItem(value: y, child: Text(" ${_be(y)}"))).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() => selectedYear = v);
              fetchYearSummary();
            }
          },
        ),
      ),
    );
  }

  Widget _buildHeroYearPaidCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _primaryColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: _primaryColor.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("ยอดชำระรวมทั้งปี", style: GoogleFonts.kanit(color: Colors.white70, fontSize: fBody)),
          const SizedBox(height: 8),
          Text(
            "${money.format(yearPaidSum)} ฿",
            style: GoogleFonts.kanit(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildYearMetricToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: _lineColor.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _toggleItem("ยอดรวม", YearMetric.paid),
          _toggleItem("ค่าน้ำ", YearMetric.water),
          _toggleItem("ค่าไฟ", YearMetric.electric),
        ],
      ),
    );
  }

  Widget _toggleItem(String label, YearMetric m) {
    final active = yearMetric == m;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => yearMetric = m),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.kanit(color: active ? _textColor : _mutedColor, fontWeight: FontWeight.w600, fontSize: fCaption),
          ),
        ),
      ),
    );
  }

  Widget _buildYearMetricChart() {
    Color mainColor = yearMetric == YearMetric.paid
        ? _primaryColor
        : yearMetric == YearMetric.water
            ? const Color(0xFF548CA8)
            : const Color(0xFFAD8B73);

    double maxVal = _yearMonthsMax();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _lineColor),
      ),
      child: AspectRatio(
        aspectRatio: 1.8,
        child: LineChart(
          LineChartData(
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (spot) => _primaryColor,
                getTooltipItems: (List<LineBarSpot> touchedSpots) {
                  return touchedSpots.map((spot) {
                    return LineTooltipItem(
                      "${monthsText[spot.x.toInt() - 1]}\n",
                      GoogleFonts.kanit(color: Colors.white70, fontSize: 10),
                      children: [
                        TextSpan(
                          text: "${money.format(spot.y)} ฿",
                          style: GoogleFonts.kanit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ],
                    );
                  }).toList();
                },
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) => FlLine(color: _lineColor.withOpacity(0.5), strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 2,
                  getTitlesWidget: (value, meta) {
                    if (value < 1 || value > 12) return const SizedBox();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(monthsShort[value.toInt()], style: GoogleFonts.kanit(fontSize: 10, color: _mutedColor)),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) => Text(_compact(value), style: GoogleFonts.kanit(fontSize: 10, color: _mutedColor)),
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 1, maxX: 12, minY: 0,
            maxY: (maxVal * 1.3).ceilToDouble(),
            lineBarsData: [
              LineChartBarData(
                spots: List.generate(12, (i) => FlSpot(i + 1.0, _yearValue(i + 1))),
                isCurved: true,
                color: mainColor,
                barWidth: 4,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, p, bar, i) => FlDotCirclePainter(radius: 4, color: Colors.white, strokeWidth: 3, strokeColor: mainColor),
                ),
                belowBarData: BarAreaData(show: true, color: mainColor.withOpacity(0.1)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildYearMonthRow(int m) {
    final val = _yearValue(m);
    final hasData = _yearBillCount(m) > 0;

    return InkWell(
      onTap: hasData
          ? () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BillHistoryPage(
                  userId: userId,
                  year: selectedYear,
                  month: m,
                  monthName: monthsText[m - 1],
                ),
              ))
          : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: _lineColor),
        ),
        child: Row(
          children: [
            Text(
              monthsText[m - 1],
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w600,
                fontSize: fBody,
                color: hasData ? _textColor : _mutedColor.withOpacity(0.5),
              ),
            ),
            const Spacer(),
            Text(
              hasData ? "${money.format(val)} ฿" : "ยังไม่มีข้อมูล",
              style: GoogleFonts.kanit(
                fontWeight: hasData ? FontWeight.w600 : FontWeight.normal,
                fontSize: fBody,
                color: hasData ? _textColor : Colors.grey.shade400,
              ),
            ),
            if (hasData) ...[
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: _mutedColor, size: 22),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 16),
          Text("เกิดข้อผิดพลาด: $loadError", textAlign: TextAlign.center, style: GoogleFonts.kanit(color: _textColor)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: fetchYearSummary,
            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
            child: Text("ลองใหม่", style: GoogleFonts.kanit(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// 2. หน้าประวัติบิลรายเดือน (BillHistoryPage)
// =============================================================
class BillHistoryPage extends StatefulWidget {
  final int userId, year, month;
  final String monthName;

  const BillHistoryPage({
    super.key,
    required this.userId,
    required this.year,
    required this.month,
    required this.monthName,
  });

  @override
  State<BillHistoryPage> createState() => _BillHistoryPageState();
}

class _BillHistoryPageState extends State<BillHistoryPage> {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cText = Color(0xFF523D2D);
  static const Color cMuted = Color(0xFF8D7456);
  static const Color cLine = Color(0xFFDCD2C1);

  final money = NumberFormat("#,##0", "en_US");
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    _fetchBills();
  }

  Future<void> _fetchBills() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final res = await http.get(Uri.parse(AppConfig.url("finance_api.php?action=bill_list&user_id=${widget.userId}&year=${widget.year}&month=${widget.month}"))).timeout(const Duration(seconds: 12));
      final data = jsonDecode(res.body);

      if (data["ok"] == true) {
        setState(() => items = List<Map<String, dynamic>>.from(data["items"] ?? []));
      } else {
        error = data["message"]?.toString() ?? "โหลดข้อมูลไม่สำเร็จ";
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s == "verified" || s == "paid") return const Color(0xFF4CAF50);
    if (s == "pending") return const Color(0xFFEF6C00);
    return const Color(0xFFD32F2F);
  }

  String _statusText(String status) {
    final s = status.toLowerCase();
    if (s == "verified" || s == "paid") return "ชำระแล้ว";
    if (s == "pending") return "รอตรวจสอบ";
    return "ยังไม่ชำระ";
  }

  double _d(dynamic v) => double.tryParse(v.toString()) ?? 0;
  int _i(dynamic v) => int.tryParse(v.toString()) ?? 0;

  String _formatSlipDate(dynamic raw) {
    final text = (raw ?? "").toString().trim();
    if (text.isEmpty) return "";
    try {
      final dt = DateTime.parse(text.replaceFirst(" ", "T")).toLocal();
      const months = ["ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."];
      return "${dt.day} ${months[dt.month - 1]} ${dt.year + 543} • ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} น.";
    } catch (_) { return text; }
  }

  String _roomLabel(Map<String, dynamic> it) {
    final building = (it["building"] ?? it["building_name"] ?? it["zone"] ?? "").toString().trim();
    final roomNumber = (it["room_number"] ?? it["room_no"] ?? it["room"] ?? "").toString().trim();
    if (building.isNotEmpty && roomNumber.isNotEmpty) return "ห้อง $building-$roomNumber";
    if (roomNumber.isNotEmpty) return "ห้อง $roomNumber";
    if (building.isNotEmpty) return "ห้อง $building";
    return "ห้อง -";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        elevation: 0.5,
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 28, color: cText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "บิลเดือน${widget.monthName} ${widget.year + 543}",
          style: GoogleFonts.kanit(color: cText, fontWeight: FontWeight.w600, fontSize: 18),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: cText))
          : error != null
              ? Center(child: Text(error!, style: GoogleFonts.kanit(color: cText)))
              : items.isEmpty
                  ? Center(child: Text("ไม่มีบิลในเดือนนี้", style: GoogleFonts.kanit(color: cText)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _buildBillCard(items[i]),
                    ),
    );
  }

  Widget _buildBillCard(Map<String, dynamic> it) {
    final status = (it["status"] ?? "").toString();
    final slipUrl = (it["slip_url"] ?? "").toString().trim();
    final slipDateText = _formatSlipDate(it["pay_date"]);

    final double rent = _d(it["rent"]);
    final double water = _d(it["water"]);
    final double electric = _d(it["electric"]);
    final double totalFromApi = _d(it["total"]);
    final double finalTotal = totalFromApi > 0 ? totalFromApi : (rent + water + electric);

    final int waterUnit = _i(it["water_unit"]);
    final int electricUnit = _i(it["electric_unit"]);
    final double waterRate = _d(it["water_rate"]);
    final double electricRate = _d(it["electric_rate"]);

    final Color statusColor = _statusColor(status);
    final String statusText = _statusText(status);
    final bool isPaid = status.toLowerCase() == "verified" || status.toLowerCase() == "paid";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cLine),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              color: cText,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        "ห้อง ",
                        style: GoogleFonts.kanit(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.normal),
                      ),
                      Text(
                        _roomLabel(it).replaceFirst("ห้อง ", ""),
                        style: GoogleFonts.kanit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isPaid ? Icons.check_circle_rounded : Icons.access_time_filled_rounded, size: 15, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: GoogleFonts.kanit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (slipUrl.isNotEmpty) ...[
                  InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SlipPreviewPage(imageUrl: slipUrl))),
                    child: Container(
                      height: 190,
                      width: double.infinity,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: cLine)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(slipUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 42))),
                      ),
                    ),
                  ),
                  if (slipDateText.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Center(child: Text("วันที่ส่งสลิป: $slipDateText", style: GoogleFonts.kanit(color: cMuted, fontSize: 11, fontWeight: FontWeight.w600))),
                  ],
                  const SizedBox(height: 12),
                ],
                _summaryTile(title: "ค่าเช่า", subtitle: "", value: "${money.format(rent)} ฿"),
                const SizedBox(height: 10),
                _summaryTile(title: "ค่าน้ำ", subtitle: "$waterUnit หน่วย × ${money.format(waterRate)} ฿/หน่วย", value: "${money.format(water)} ฿"),
                const SizedBox(height: 10),
                _summaryTile(title: "ค่าไฟ", subtitle: "$electricUnit หน่วย × ${money.format(electricRate)} ฿/หน่วย", value: "${money.format(electric)} ฿"),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFDCD2C1).withOpacity(0.35), borderRadius: BorderRadius.circular(16), border: Border.all(color: cLine)),
                  child: Row(
                    children: [
                      Expanded(child: Text("รวมสุทธิ", style: GoogleFonts.kanit(color: cText, fontWeight: FontWeight.w600, fontSize: 15))),
                      Text("${money.format(finalTotal)} ฿", style: GoogleFonts.kanit(color: cText, fontWeight: FontWeight.w600, fontSize: 22)),
                    ],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _summaryTile({required String title, required String subtitle, required String value}) {
    final hasSubtitle = subtitle.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFDCD2C1).withOpacity(0.18), borderRadius: BorderRadius.circular(16), border: Border.all(color: cLine)),
      child: Row(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(title, style: GoogleFonts.kanit(color: cText, fontWeight: FontWeight.w600, fontSize: 13)),
                if (hasSubtitle) ...[
                  const SizedBox(width: 8),
                  Flexible(child: Text("($subtitle)", style: GoogleFonts.kanit(color: cMuted, fontSize: 11), overflow: TextOverflow.ellipsis)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(value, style: GoogleFonts.kanit(color: cText, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

// =============================================================
// 3. หน้าพรีวิวสลิป (SlipPreviewPage)
// =============================================================
class SlipPreviewPage extends StatelessWidget {
  final String imageUrl;
  const SlipPreviewPage({super.key, required this.imageUrl});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        title: Text("สลิป", style: GoogleFonts.kanit(color: Colors.white, fontSize: 18)),
      ),
      body: Center(child: InteractiveViewer(child: Image.network(imageUrl))),
    );
  }
}