import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config.dart';

enum YearMetric { income, water, electric }

class ExpensePage extends StatefulWidget {
  const ExpensePage({super.key});

  @override
  State<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends State<ExpensePage> {
  // 🎨 Palette: Deep Coffee & Cream
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cTextMain = Color(0xFF2A1F17);
  static const Color cDark = Color(0xFF523D2D);

  // 📏 Typography มาตราส่วนใหม่ตามสั่ง
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle = 15.0;  // หัวข้อย่อย
  static const double fBody = 13.0;   // เนื้อหา

  int get thaiYear => selectedYear + 543;
  bool isMonthly = true;
  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;
  int dormId = 0;
  bool loading = true;
  String? loadError;
  YearMetric yearMetric = YearMetric.income;

  final money = NumberFormat("#,##0", "en_US");
  final monthsText = const [
    "มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน",
    "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม"
  ];
  final monthsShort = const [
    "", "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.",
    "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."
  ];

  double expectedIncome = 0, receivedIncome = 0;
  Map<String, double> breakdown = {"rent": 0, "water": 0, "electric": 0};
  List<Map<String, dynamic>> yearMonths = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    dormId = prefs.getInt("dorm_id") ?? 0;
    if (dormId <= 0) {
      setState(() { loading = false; loadError = "ไม่พบรหัสหอพัก"; });
      return;
    }
    await fetchIncomeSummary();
  }

  Future<void> fetchIncomeSummary() async {
    if (!mounted) return;
    setState(() { loading = true; loadError = null; });
    try {
      final scope = isMonthly ? "month" : "year";
      final uri = Uri.parse(AppConfig.url("finance_api.php")).replace(queryParameters: {
        "action": "summary_income",
        "dorm_id": dormId.toString(),
        "scope": scope,
        "year": selectedYear.toString(),
        if (isMonthly) "month": selectedMonth.toString(),
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      final data = _safeJsonMap(res.body);

      if (res.statusCode == 200) {
        setState(() {
          expectedIncome = _toDouble(data["expected_income"]) ?? 0;
          receivedIncome = _toDouble(data["received_income"]) ?? 0;
          final b = data["breakdown"] is Map ? data["breakdown"] : data;
          breakdown = {
            "rent": _pickNumFromAny(b, ["rent", "rent_income"]),
            "water": _pickNumFromAny(b, ["water", "water_total", "water_income"]),
            "electric": _pickNumFromAny(b, ["electric", "electric_total", "electric_income"]),
          };
          yearMonths = List<Map<String, dynamic>>.from(data["months"] ?? []);
        });
      } else {
        setState(() => loadError = data["message"] ?? "เกิดข้อผิดพลาดจากเซิร์ฟเวอร์");
      }
    } catch (e) { 
      setState(() => loadError = "เชื่อมต่อไม่ได้: ${e.toString()}"); 
    } finally { 
      if (mounted) setState(() => loading = false); 
    }
  }

  Map<String, dynamic> _safeJsonMap(String raw) {
    try {
      final body = raw.trimLeft();
      final i = body.indexOf(RegExp(r'[\{\[]'));
      return jsonDecode(i >= 0 ? body.substring(i) : body);
    } catch (_) { return {"ok": false}; }
  }

  double _pickNumFromAny(dynamic obj, List<String> keys) {
    if (obj is Map) {
      for (final k in keys) {
        final d = _toDouble(obj[k]);
        if (d != null && d != 0) return d;
      }
    }
    return 0.0;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(",", "").trim());
  }

  int _toInt(dynamic v) => (v is int) ? v : (int.tryParse(v?.toString() ?? "0") ?? 0);
  String _compact(double v) => v.abs() >= 1000 ? "${(v / 1000).toStringAsFixed(0)}K" : v.toStringAsFixed(0);
  Map<String, dynamic> _monthRowObj(int m) => yearMonths.firstWhere((e) => _toInt(e["month"]) == m, orElse: () => {});
  double _yearTotal(int m) => _toDouble(_monthRowObj(m)["received_income"]) ?? 0;
  double _yearWater(int m) => _pickNumFromAny(_monthRowObj(m), ["water", "water_total"]);
  double _yearElectric(int m) => _pickNumFromAny(_monthRowObj(m), ["electric", "electric_total"]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 55, elevation: 0.5, backgroundColor: Colors.white, centerTitle: true,
        iconTheme: const IconThemeData(color: cTextMain),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("สรุปการเงิน", style: GoogleFonts.kanit(color: cTextMain, fontWeight: FontWeight.w600, fontSize: fHeader)),
      ),
      body: RefreshIndicator(
        onRefresh: fetchIncomeSummary,
        color: cDark,
        child: loading 
          ? const Center(child: CircularProgressIndicator(color: cDark))
          : loadError != null ? _buildErrorState() : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildTopSelector(),
        const SizedBox(height: 20),
        _buildHeroIncomeCard(),
        const SizedBox(height: 24),
        if (isMonthly) ...[
          Text("องค์ประกอบรายรับ", style: GoogleFonts.kanit(fontSize: fTitle, fontWeight: FontWeight.w600, color: cTextMain)),
          const SizedBox(height: 12),
          _buildBreakdownCard(),
        ],
        if (!isMonthly) ...[
          Text("สถิติรายปี $thaiYear", style: GoogleFonts.kanit(fontSize: fTitle, fontWeight: FontWeight.w600, color: cTextMain)),
          const SizedBox(height: 12),
          _buildYearMetricToggle(),
          const SizedBox(height: 16),
          _buildYearMetricChart(),
          const SizedBox(height: 24),
          Text("รายละเอียดรายเดือน", style: GoogleFonts.kanit(fontSize: fTitle, fontWeight: FontWeight.w600, color: cTextMain)),
          const SizedBox(height: 12),
          for (int m = 1; m <= 12; m++) ...[
            _buildYearMonthRow(m),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildTopSelector() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: cAccent.withOpacity(0.5), borderRadius: BorderRadius.circular(15)),
        child: Row(children: [ _toggleItem(0, "รายเดือน"), _toggleItem(1, "รายปี")]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        if (isMonthly) Expanded(child: _dropdownWrapper(child: DropdownButton<int>(value: selectedMonth, isExpanded: true, style: GoogleFonts.kanit(fontSize: fBody, color: cTextMain, fontWeight: FontWeight.normal), items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(monthsText[i]))), onChanged: (v) { setState(() => selectedMonth = v ?? selectedMonth); fetchIncomeSummary(); }))),
        if (isMonthly) const SizedBox(width: 10),
        Expanded(child: _dropdownWrapper(child: DropdownButton<int>(value: selectedYear, isExpanded: true, style: GoogleFonts.kanit(fontSize: fBody, color: cTextMain, fontWeight: FontWeight.normal), items: [2024, 2025, 2026].map((y) => DropdownMenuItem(value: y, child: Text("${y + 543}"))).toList(), onChanged: (v) { setState(() => selectedYear = v ?? selectedYear); fetchIncomeSummary(); }))),
      ]),
    ]);
  }

  Widget _dropdownWrapper({required Widget child}) => Container(padding: const EdgeInsets.symmetric(horizontal: 12), height: 50, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: cAccent.withOpacity(0.8), width: 1.5)), child: DropdownButtonHideUnderline(child: child));

  Widget _toggleItem(int index, String label) {
    final active = (isMonthly && index == 0) || (!isMonthly && index == 1);
    return Expanded(child: GestureDetector(onTap: () { setState(() => isMonthly = index == 0); fetchIncomeSummary(); }, child: AnimatedContainer(duration: const Duration(milliseconds: 250), padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: active ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(12), boxShadow: active ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)] : []), child: Text(label, textAlign: TextAlign.center, style: GoogleFonts.kanit(color: active ? cTextMain : cDark.withOpacity(0.6), fontWeight: FontWeight.w600, fontSize: fBody)))));
  }

  Widget _buildHeroIncomeCard() {
    final progress = (expectedIncome > 0 ? (receivedIncome / expectedIncome) : 0.0).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(28), 
      decoration: BoxDecoration(color: cTextMain, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: cTextMain.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 8))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isMonthly ? "รายรับรวมเดือนนี้" : "รายรับรวมปี $thaiYear", style: GoogleFonts.kanit(color: Colors.white70, fontSize: fBody, fontWeight: FontWeight.normal)),
        const SizedBox(height: 6),
        Text("${money.format(receivedIncome)} ฿", style: GoogleFonts.kanit(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("เป้าหมายรายรับ ${money.format(expectedIncome)}", style: GoogleFonts.kanit(color: Colors.white60, fontSize: fBody, fontWeight: FontWeight.normal)), Text("${(progress * 100).toStringAsFixed(1)}%", style: GoogleFonts.kanit(color: Colors.white, fontSize: fBody, fontWeight: FontWeight.w600))]),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: progress, backgroundColor: Colors.white12, color: cAccent, minHeight: 10)),
      ]),
    );
  }

  Widget _buildYearMetricToggle() {
    return Container(
      padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: cAccent.withOpacity(0.5), borderRadius: BorderRadius.circular(15)),
      child: Row(children: [ _metricItem(YearMetric.income, "รายได้"), _metricItem(YearMetric.water, "ค่าน้ำ"), _metricItem(YearMetric.electric, "ค่าไฟ")]),
    );
  }

  Widget _metricItem(YearMetric m, String label) {
    final active = yearMetric == m;
    return Expanded(child: GestureDetector(onTap: () => setState(() => yearMetric = m), child: AnimatedContainer(duration: const Duration(milliseconds: 250), padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: active ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(12)), child: Text(label, textAlign: TextAlign.center, style: GoogleFonts.kanit(color: active ? cTextMain : cDark.withOpacity(0.6), fontWeight: FontWeight.w600, fontSize: fBody)))));
  }

  Widget _buildYearMetricChart() {
    Color barColor;
    if (yearMetric == YearMetric.income) {
      barColor = const Color(0xFF1565C0);
    } else if (yearMetric == YearMetric.water) barColor = const Color(0xFF0288D1);
    else barColor = const Color(0xFFE65100);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]),
      child: AspectRatio(
        aspectRatio: 1.6,
        child: BarChart(BarChartData(
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.white,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  "${monthsText[group.x.toInt() - 1]}\n",
                  GoogleFonts.kanit(color: cTextMain, fontWeight: FontWeight.w600, fontSize: fBody),
                  children: [
                    TextSpan(
                      text: "${money.format(rod.toY)} ฿",
                      style: GoogleFonts.kanit(color: barColor, fontWeight: FontWeight.bold, fontSize: fBody),
                    ),
                  ],
                );
              },
            ),
          ),
          maxY: _maxSingleYearY(yearMetric == YearMetric.income ? _yearTotal : (yearMetric == YearMetric.water ? _yearWater : _yearElectric)),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: _titlesData(),
          barGroups: List.generate(12, (i) {
            double value = 0;
            if (yearMetric == YearMetric.income) {
              value = _yearTotal(i + 1);
            } else if (yearMetric == YearMetric.water) value = _yearWater(i + 1);
            else value = _yearElectric(i + 1);
            return BarChartGroupData(x: i + 1, barRods: [BarChartRodData(toY: value, color: barColor, width: 12, borderRadius: BorderRadius.circular(4))]);
          }),
        )),
      ),
    );
  }

  FlTitlesData _titlesData() => FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) => Padding(
      padding: const EdgeInsets.only(top: 10.0),
      child: Text(monthsShort[v.toInt() % 13], style: GoogleFonts.kanit(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.normal)),
    ))),
    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, m) => Text(_compact(v), style: GoogleFonts.kanit(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.normal)))),
  );

  Widget _buildYearMonthRow(int m) {
    final val = yearMetric == YearMetric.income ? _yearTotal(m) : (yearMetric == YearMetric.water ? _yearWater(m) : _yearElectric(m));
    final hasData = val > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8)]),
      child: Row(
        children: [
          Text(monthsText[m - 1], style: GoogleFonts.kanit(fontSize: fBody, color: hasData ? cTextMain : Colors.grey.shade400, fontWeight: FontWeight.normal)),
          const Spacer(),
          Text(hasData ? "${money.format(val)} ฿" : "ไม่มีข้อมูล", 
            style: GoogleFonts.kanit(fontSize: fBody, fontWeight: FontWeight.w600, color: hasData ? cTextMain : Colors.grey.shade300)),
        ],
      ),
    );
  }

  Widget _buildBreakdownCard() {
    double total = (breakdown["rent"] ?? 0) + (breakdown["water"] ?? 0) + (breakdown["electric"] ?? 0);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12)]),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(height: 14, width: double.infinity,
              child: Row(children: [
                if (total > 0 && (breakdown["rent"] ?? 0) > 0) Expanded(flex: ((breakdown["rent"]! / total) * 100).toInt(), child: Container(color: const Color(0xFF1565C0))),
                if (total > 0 && (breakdown["water"] ?? 0) > 0) Expanded(flex: ((breakdown["water"]! / total) * 100).toInt(), child: Container(color: const Color(0xFF0288D1))),
                if (total > 0 && (breakdown["electric"] ?? 0) > 0) Expanded(flex: ((breakdown["electric"]! / total) * 100).toInt(), child: Container(color: const Color(0xFFEF6C00))),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          _legendRow("ค่าเช่าห้องรวม", breakdown["rent"] ?? 0, const Color(0xFF1565C0)),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, thickness: 0.5)),
          _legendRow("ค่าน้ำประปา", breakdown["water"] ?? 0, const Color(0xFF0288D1)),
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, thickness: 0.5)),
          _legendRow("ค่าไฟฟ้า", breakdown["electric"] ?? 0, const Color(0xFFEF6C00)),
        ],
      ),
    );
  }

  Widget _legendRow(String label, double val, Color color) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Row(children: [ Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 12), Text(label, style: GoogleFonts.kanit(fontSize: fBody, fontWeight: FontWeight.normal, color: Colors.black87))]),
      Text("${money.format(val)} ฿", style: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: fBody, color: cTextMain)),
    ],
  );

  Widget _buildErrorState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.error_outline, size: 54, color: Color(0xFFD32F2F)),
    const SizedBox(height: 16),
    Text(loadError ?? "เกิดข้อผิดพลาดในการโหลดข้อมูล", style: GoogleFonts.kanit(fontSize: fBody, fontWeight: FontWeight.normal, color: cTextMain)),
    const SizedBox(height: 12),
    TextButton(onPressed: fetchIncomeSummary, child: Text("ลองใหม่อีกครั้ง", style: GoogleFonts.kanit(fontWeight: FontWeight.w600, color: const Color(0xFF1565C0)))),
  ]));

  double _maxSingleYearY(double Function(int month) getter) {
    double maxY = 0;
    for (int m = 1; m <= 12; m++) {
      final v = getter(m);
      if (v > maxY) maxY = v;
    }
    return maxY <= 0 ? 1000 : (maxY * 1.2);
  }
}