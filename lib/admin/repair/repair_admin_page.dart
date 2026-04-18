import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config.dart';
import 'repair_model.dart';
import 'repair_detail_page.dart';

class RepairAdminPage extends StatefulWidget {
  const RepairAdminPage({super.key});

  @override
  State<RepairAdminPage> createState() => _RepairAdminPageState();
}

class _RepairAdminPageState extends State<RepairAdminPage> {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cTextMain = Color(0xFF2A1F17);
  static const Color cDark = Color(0xFF523D2D);

  // 📏 Typography มาตราส่วนใหม่
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle = 15.0;  // หัวข้อย่อย
  static const double fBody = 13.0;   // เนื้อหา
  static const double fCaption = 11.0;

  List<RepairModel> repairs = [];
  bool loading = true;
  String selectedStatusKey = "all";
  int dormId = 0;

  final Map<String, String> statusKeyToThai = const {
    "all": "ทั้งหมด",
    "pending": "รอดำเนินการ",
    "working": "กำลังดำเนินการ",
    "done": "เสร็จสิ้น",
  };

  @override
  void initState() {
    super.initState();
    _loadDormAndFetch();
  }

  Color _getStatusKeyColor(String key) {
    switch (key) {
      case "all":
        return const Color(0xFF6B4F3A);
      case "pending":
        return const Color(0xFFD65C5C);
      case "working":
        return const Color(0xFFE39A3B);
      case "done":
        return const Color(0xFF4E8B57);
      default:
        return Colors.grey;
    }
  }

  Color _getStatusBgColor(String key, bool isSelected) {
    if (isSelected) return _getStatusKeyColor(key);

    switch (key) {
      case "all":
        return const Color(0xFFF3ECE7);
      case "pending":
        return const Color(0xFFFDEAEA);
      case "working":
        return const Color(0xFFFFF3E3);
      case "done":
        return const Color(0xFFE7F3E8);
      default:
        return const Color(0xFFF5F5F5);
    }
  }

  Color _getTypeColor(String type) {
    if (type.contains("ไฟฟ้า")) return const Color(0xFFFBC02D);
    if (type.contains("น้ำ") || type.contains("ประปา")) {
      return const Color(0xFF0288D1);
    }
    if (type.contains("แอร์")) return const Color(0xFF009688);
    if (type.contains("เฟอร์นิเจอร์")) return const Color(0xFF795548);
    return const Color(0xFF455A64);
  }

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains("pending") || s.contains("รอ")) {
      return const Color(0xFFD32F2F);
    }
    if (s.contains("working") || s.contains("กำลัง")) {
      return const Color(0xFFEF6C00);
    }
    if (s.contains("done") || s.contains("เสร็จ")) {
      return const Color(0xFF2E7D32);
    }
    return Colors.grey.shade700;
  }

  IconData _getTypeIcon(String type) {
    if (type.contains("ไฟฟ้า")) return Icons.bolt_rounded;
    if (type.contains("น้ำ") || type.contains("ประปา")) {
      return Icons.water_drop_rounded;
    }
    if (type.contains("แอร์")) return Icons.ac_unit_rounded;
    if (type.contains("เฟอร์นิเจอร์")) return Icons.chair_rounded;
    return Icons.construction_rounded;
  }

  String _thaiDate(String? raw) {
    if (raw == null || raw.isEmpty || raw == "-") return "-";
    try {
      final dt = DateTime.parse(raw.replaceFirst(" ", "T"));
      const months = [
        "", "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.",
        "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."
      ];
      return "${dt.day} ${months[dt.month]} ${dt.year + 543}";
    } catch (_) {
      return raw;
    }
  }

  Future<void> _loadDormAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    dormId = prefs.getInt("dorm_id") ?? prefs.getInt("selected_dorm_id") ?? 0;
    await fetchRepairs();
  }

  Future<void> fetchRepairs() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      final body = {
        "action": "list",
        "dorm_id": dormId.toString(),
        "status": selectedStatusKey,
      };

      final res = await http.post(
        Uri.parse(AppConfig.url("repairs_api.php")),
        body: body,
      );
      final data = jsonDecode(res.body);

      if (data is Map && (data["ok"] == true || data["success"] == true)) {
        final List list = (data["data"] as List?) ?? [];
        setState(() {
          repairs = list
              .map((e) => RepairModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        });
      } else {
        setState(() => repairs = []);
      }
    } catch (e) {
      debugPrint("Error fetching repairs: $e");
      setState(() => repairs = []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 55,
        elevation: 0.5,
        backgroundColor: Colors.white,
        centerTitle: true,
        title: Text(
          "จัดการงานซ่อม",
          style: GoogleFonts.kanit(
            color: cTextMain,
            fontWeight: FontWeight.w600,
            fontSize: fHeader,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: cTextMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: cDark))
                : RefreshIndicator(
                    onRefresh: fetchRepairs,
                    color: cDark,
                    child: repairs.isEmpty
                        ? Center(
                            child: Text(
                              "ไม่มีรายการแจ้งซ่อม",
                              style: GoogleFonts.kanit(
                                fontSize: fTitle,
                                color: cTextMain,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          )
                        : _buildRepairList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: statusKeyToThai.entries.map((entry) {
            final isSelected = selectedStatusKey == entry.key;
            final chipColor = _getStatusKeyColor(entry.key);

            return InkWell(
              borderRadius: BorderRadius.circular(25),
              onTap: () {
                if (selectedStatusKey != entry.key) {
                  setState(() => selectedStatusKey = entry.key);
                  fetchRepairs();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: _getStatusBgColor(entry.key, isSelected),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: isSelected
                        ? chipColor
                        : chipColor.withOpacity(0.35),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    if (isSelected) ...[
                      const Icon(
                        Icons.check_circle,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      entry.value,
                      style: GoogleFonts.kanit(
                        color: isSelected ? Colors.white : chipColor,
                        fontWeight: FontWeight.w600,
                        fontSize: fBody,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRepairList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: repairs.length,
      itemBuilder: (context, index) {
        final r = repairs[index];
        final typeColor = _getTypeColor(r.type);
        final statusColor = _getStatusColor(r.status);
        final String imageUrl = r.image.isNotEmpty ? AppConfig.url(r.image) : "";

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RepairDetailPage(repair: r),
                ),
              );
              if (result != null) fetchRepairs();
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Row(
                children: [
                  Container(width: 6, height: 115, color: statusColor),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          _buildRepairImage(imageUrl, r.type, typeColor),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "ห้อง ${r.room}",
                                  style: GoogleFonts.kanit(
                                    fontWeight: FontWeight.w600,
                                    fontSize: fTitle,
                                    color: cTextMain,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                _buildTypeBadge(r.type, typeColor),
                                const SizedBox(height: 10),
                                Text(
                                  r.detail.isEmpty
                                      ? "ไม่มีรายละเอียด"
                                      : r.detail,
                                  style: GoogleFonts.kanit(
                                    fontSize: fBody,
                                    color: Colors.black87,
                                    fontWeight: FontWeight.normal,
                                    height: 1.3,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _thaiDate(r.createdAt),
                                  style: GoogleFonts.kanit(
                                    fontSize: fCaption,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.grey,
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRepairImage(String url, String type, Color color) {
    return Container(
      width: 85,
      height: 85,
      decoration: BoxDecoration(
        color: cBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (c, e, s) =>
                    Icon(_getTypeIcon(type), color: color, size: 30),
              )
            : Icon(_getTypeIcon(type), color: color, size: 32),
      ),
    );
  }

  Widget _buildTypeBadge(String type, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getTypeIcon(type), size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            type,
            style: GoogleFonts.kanit(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: fCaption,
            ),
          ),
        ],
      ),
    );
  }
}