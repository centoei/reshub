import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import '../config.dart';

const double fHeader = 18.0;
const double fTitle = 15.0;
const double fBody = 13.0;
const double fDetail = 13.0;
const double fCaption = 11.0;

// 🎨 ปรับให้ตรงโทนหน้าผู้ดูแลหอพัก
const Color cBg = Color(0xFFF4EFE6);
const Color cTextMain = Color(0xFF2A1F17);
const Color cDark = Color(0xFF523D2D);
const Color cAccent = Color(0xFFD7CCC8);

const List<Map<String, dynamic>> kRepairTypeOptions = [
  {
    "id": 1,
    "name": "ไฟฟ้า",
    "icon": Icons.bolt_rounded
  },
  {
    "id": 2,
    "name": "ประปา",
    "icon": Icons.water_drop_rounded
  },
  {
    "id": 3,
    "name": "แอร์",
    "icon": Icons.ac_unit_rounded
  },
  {
    "id": 4,
    "name": "เฟอร์นิเจอร์",
    "icon": Icons.chair_rounded
  },
  {
    "id": 5,
    "name": "อื่น ๆ",
    "icon": Icons.construction_rounded
  },
];

int repairTypeIdByName(String? name) {
  switch ((name ?? "").trim()) {
    case "ไฟฟ้า":
      return 1;
    case "ประปา":
      return 2;
    case "แอร์":
      return 3;
    case "เฟอร์นิเจอร์":
      return 4;
    case "อื่น ๆ":
      return 5;
    default:
      return 0;
  }
}

Color repairTypeColor(String type) {
  switch (type.trim()) {
    case "ไฟฟ้า":
      return const Color(0xFFFBC02D);
    case "ประปา":
      return const Color(0xFF0288D1);
    case "แอร์":
      return const Color(0xFF009688);
    case "เฟอร์นิเจอร์":
      return const Color(0xFF795548);
    default:
      return const Color(0xFF455A64);
  }
}

IconData repairTypeIcon(String type) {
  switch (type.trim()) {
    case "ไฟฟ้า":
      return Icons.bolt_rounded;
    case "ประปา":
      return Icons.water_drop_rounded;
    case "แอร์":
      return Icons.ac_unit_rounded;
    case "เฟอร์นิเจอร์":
      return Icons.chair_rounded;
    default:
      return Icons.construction_rounded;
  }
}

String _prettyThaiDate(String raw) {
  if (raw.isEmpty || raw == "-") return "-";
  try {
    final dt = DateTime.parse(raw.replaceFirst(" ", "T"));
    const thMonths = [
      "ม.ค.",
      "ก.พ.",
      "มี.ค.",
      "เม.ย.",
      "พ.ค.",
      "มิ.ย.",
      "ก.ค.",
      "ส.ค.",
      "ก.ย.",
      "ต.ค.",
      "พ.ย.",
      "ธ.ค."
    ];
    return "${dt.day} ${thMonths[dt.month - 1]} ${dt.year + 543}";
  } catch (_) {
    return raw;
  }
}

String? _extractImageUrl(dynamic imagePath) {
  try {
    if (imagePath == null) return null;

    final raw = imagePath.toString().trim();

    if (raw.isEmpty ||
        raw == "null" ||
        raw == "[]" ||
        raw == "[null]" ||
        raw == '[""]') {
      return null;
    }

    if (raw.startsWith("[")) {
      final List imgs = jsonDecode(raw);
      if (imgs.isEmpty) return null;

      final first = imgs.first?.toString().trim() ?? "";
      if (first.isEmpty || first == "null") return null;

      return AppConfig.url(first);
    }

    return AppConfig.url(raw);
  } catch (_) {
    return null;
  }
}

class RepairPage extends StatefulWidget {
  const RepairPage({super.key});

  @override
  State<RepairPage> createState() => _RepairPageState();
}

class _RepairPageState extends State<RepairPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  File? _image;
  String? repairType;
  final TextEditingController detailCtrl = TextEditingController();

  bool _submitting = false;
  int _userId = 0;
  int _dormId = 0;

  final List<Map<String, dynamic>> categoryList = kRepairTypeOptions;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId = prefs.getInt("user_id") ?? 0;
      _dormId = prefs.getInt("dorm_id") ?? 0;
    });
  }

  Future<void> _handleSubmit() async {
    if (_submitting) return;

    if (repairType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("กรุณาเลือกประเภทงานซ่อม"),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    try {
      final req = http.MultipartRequest(
        "POST",
        Uri.parse(AppConfig.url("repair.php")),
      );

      req.fields.addAll({
        "action": "create",
        "user_id": _userId.toString(),
        "dorm_id": _dormId.toString(),
        "type_id": repairTypeIdByName(repairType).toString(),
        "detail": detailCtrl.text.trim(),
      });

      if (_image != null) {
        req.files.add(
          await http.MultipartFile.fromPath("image", _image!.path),
        );
      }

      final streamedRes = await req.send();
      final res = await http.Response.fromStream(streamedRes);
      final data = jsonDecode(res.body);

      if (data["success"] == true) {
        detailCtrl.clear();
        setState(() {
          repairType = null;
          _image = null;
        });

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const RepairHistoryPage(),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data["message"] ?? "บันทึกไม่สำเร็จ"),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("เกิดข้อผิดพลาดในการส่งข้อมูล"),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    detailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 55,
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        title: Text(
          "แจ้งซ่อม",
          style: GoogleFonts.kanit(
            fontWeight: FontWeight.w600,
            color: cTextMain,
            fontSize: fHeader,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const RepairHistoryPage(),
              ),
            ),
            icon: const Icon(
              Icons.history_rounded,
              color: cTextMain,
              size: 18,
            ),
            label: Text(
              "ประวัติ",
              style: GoogleFonts.kanit(
                color: cTextMain,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildFormCard(),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cDark,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _submitting
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                        )
                      : Text(
                          "ยืนยันส่งข้อมูล",
                          style: GoogleFonts.kanit(
                            fontSize: fHeader,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "เลือกประเภทงานซ่อม",
            style: GoogleFonts.kanit(
              fontSize: fTitle,
              fontWeight: FontWeight.w600,
              color: cTextMain,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: categoryList.length,
            itemBuilder: (ctx, i) {
              final item = categoryList[i];
              final key = (item["name"] ?? "").toString();
              final isSel = repairType == key;
              final tColor = repairTypeColor(key);

              return InkWell(
                onTap: () => setState(() => repairType = key),
                borderRadius: BorderRadius.circular(15),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isSel ? tColor : tColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: isSel ? tColor : tColor.withOpacity(0.35),
                      width: 1.4,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        repairTypeIcon(key),
                        size: 18,
                        color: isSel ? Colors.white : tColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        key,
                        style: GoogleFonts.kanit(
                          fontSize: fBody,
                          fontWeight: FontWeight.w600,
                          color: isSel ? Colors.white : tColor,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const Divider(height: 40),
          Text(
            "รายละเอียดเพิ่มเติม",
            style: GoogleFonts.kanit(
              fontSize: fTitle,
              fontWeight: FontWeight.w600,
              color: cTextMain,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: detailCtrl,
            maxLines: 4,
            style: GoogleFonts.kanit(
              color: cTextMain,
              fontSize: fBody,
              fontWeight: FontWeight.normal,
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? "กรุณากรอกรายละเอียด" : null,
            decoration: InputDecoration(
              hintText: "ระบุอาการเสียที่พบ...",
              hintStyle: GoogleFonts.kanit(
                color: Colors.grey.shade600,
              ),
              filled: true,
              fillColor: cBg,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: cAccent),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: cAccent),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: cDark, width: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _buildImagePicker(),
        ],
      ),
    );
  }

  Widget _buildImagePicker() {
    return GestureDetector(
      onTap: _image != null
          ? null
          : () async {
              final XFile? p =
                  await _picker.pickImage(source: ImageSource.gallery);
              if (p != null) {
                setState(() => _image = File(p.path));
              }
            },
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: cBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cAccent, width: 1.3),
        ),
        child: _image == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.add_a_photo_rounded,
                    color: cDark,
                    size: 42,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "เพิ่มรูปภาพ",
                    style: GoogleFonts.kanit(
                      color: cTextMain,
                      fontSize: fBody,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : Stack(
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(19),
                      child: Image.file(
                        _image!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () => setState(() => _image = null),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  )
                ],
              ),
      ),
    );
  }
}

class RepairHistoryPage extends StatefulWidget {
  const RepairHistoryPage({super.key});

  @override
  State<RepairHistoryPage> createState() => _RepairHistoryPageState();
}

class _RepairHistoryPageState extends State<RepairHistoryPage> {
  bool loading = true;
  List<Map<String, dynamic>> items = [];
  int _userId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getInt("user_id") ?? 0;

    try {
      final res = await http.post(
        Uri.parse(AppConfig.url("repair.php")),
        body: {
          "action": "listMyRepairs",
          "user_id": _userId.toString(),
          "dorm_id": (prefs.getInt("dorm_id") ?? 0).toString(),
        },
      );
      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        setState(() {
          items = List<Map<String, dynamic>>.from(data["data"] ?? []);
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<bool> _showConfirmDeleteDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_forever_rounded,
                      color: Colors.redAccent,
                      size: 45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "ยืนยันการลบ",
                    style: GoogleFonts.kanit(
                      fontSize: fHeader,
                      fontWeight: FontWeight.w600,
                      color: cTextMain,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "คุณต้องการลบรายการแจ้งซ่อมนี้\nใช่หรือไม่?",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.kanit(
                      fontSize: fDetail,
                      color: Colors.grey,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cDark,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: Text(
                            "ยืนยันลบ",
                            style: GoogleFonts.kanit(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
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
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: Text(
                            "ยกเลิก",
                            style: GoogleFonts.kanit(
                              color: cTextMain,
                              fontWeight: FontWeight.w600,
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
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 55,
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: cTextMain,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "ประวัติการแจ้งซ่อม",
          style: GoogleFonts.kanit(
            fontWeight: FontWeight.w600,
            color: cTextMain,
            fontSize: fHeader,
          ),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: cDark))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 15, 14, 100),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final it = items[i];

                final String? firstImg = _extractImageUrl(it["image_path"]);
                final repairType = (it["repair_type"] ?? "").toString();

                final Color sColor = it["status"].toString().contains("pending")
                    ? const Color(0xFFD32F2F)
                    : (it["status"].toString().contains("working"))
                        ? const Color(0xFFEF6C00)
                        : const Color(0xFF2E7D32);

                return _RepairCardNoStatus(
                  statusColor: sColor,
                  title: "แจ้งซ่อม$repairType",
                  typeText: repairType,
                  createdText: _prettyThaiDate(it["created_at"] ?? "-"),
                  imageUrl: firstImg,
                  onTap: () async {
                    final res = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditRepairPage(item: it),
                      ),
                    );
                    if (res == true) _load();
                  },
                  onDelete: () async {
                    final ok = await _showConfirmDeleteDialog(context);
                    if (ok == true) {
                      await http.post(
                        Uri.parse(AppConfig.url("repair.php")),
                        body: {
                          "action": "deleteMyRepair",
                          "repair_id": it["repair_id"].toString(),
                          "user_id": _userId.toString(),
                        },
                      );
                      _load();
                    }
                  },
                );
              },
            ),
    );
  }
}

class EditRepairPage extends StatefulWidget {
  final Map<String, dynamic> item;
  const EditRepairPage({super.key, required this.item});

  @override
  State<EditRepairPage> createState() => _EditRepairPageState();
}

class _EditRepairPageState extends State<EditRepairPage> {
  late TextEditingController detailCtrl;
  final ImagePicker _picker = ImagePicker();

  File? _newImage;
  String? _oldImageUrl;
  bool _isImageDeleted = false;
  bool submitting = false;
  int _userId = 0;

  @override
  void initState() {
    super.initState();
    detailCtrl = TextEditingController(text: widget.item['detail'] ?? "");
    _loadUser();
    _oldImageUrl = _extractImageUrl(widget.item["image_path"]);
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userId = prefs.getInt("user_id") ?? 0;
    });
  }

  Widget _buildTypeBadgeSmall(String type) {
    final Color tColor = repairTypeColor(type);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tColor.withOpacity(0.45)),
      ),
      child: Text(
        type,
        style: GoogleFonts.kanit(
          fontSize: fCaption,
          fontWeight: FontWeight.w600,
          color: tColor,
        ),
      ),
    );
  }

  Widget _buildStatusTimeline(String status) {
    final int currentStep = status.contains("pending")
        ? 0
        : (status.contains("working"))
            ? 1
            : 2;
    final List<String> labels = ["รอดำเนินการ", "กำลังซ่อม", "เสร็จสิ้น"];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cAccent.withOpacity(0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Text(
            "สถานะงานซ่อมปัจจุบัน",
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w600,
              color: cTextMain,
              fontSize: fDetail,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(3, (i) {
              final bool isDone = i <= currentStep;
              final Color activeColor = (currentStep == 0)
                  ? const Color(0xFFD32F2F)
                  : (currentStep == 1)
                      ? const Color(0xFFEF6C00)
                      : const Color(0xFF2E7D32);
              final Color color = isDone ? activeColor : Colors.grey.shade300;

              return Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 2,
                            color: i == 0
                                ? Colors.transparent
                                : (i <= currentStep
                                    ? color
                                    : Colors.grey.shade300),
                          ),
                        ),
                        Icon(
                          isDone
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: color,
                          size: 22,
                        ),
                        Expanded(
                          child: Container(
                            height: 2,
                            color: i == 2
                                ? Colors.transparent
                                : (i < currentStep
                                    ? color
                                    : Colors.grey.shade300),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[i],
                      style: GoogleFonts.kanit(
                        fontSize: 10,
                        fontWeight:
                            isDone ? FontWeight.w600 : FontWeight.normal,
                        color: isDone ? cTextMain : Colors.grey,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    detailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repairType = (widget.item['repair_type'] ?? "").toString();
    final repairTypeId =
        int.tryParse(widget.item['type_id']?.toString() ?? "0") ??
            repairTypeIdByName(repairType);

    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 55,
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        title: Text(
          "รายละเอียดการแจ้งซ่อม",
          style: GoogleFonts.kanit(
            fontSize: fHeader,
            fontWeight: FontWeight.w600,
            color: cTextMain,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStatusTimeline(widget.item['status'] ?? "pending"),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "ข้อมูลการแจ้งซ่อม",
                        style: GoogleFonts.kanit(
                          fontSize: fTitle,
                          fontWeight: FontWeight.w600,
                          color: cTextMain,
                        ),
                      ),
                      _buildTypeBadgeSmall(repairType),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "วันที่แจ้ง: ${_prettyThaiDate(widget.item['created_at'] ?? '-')}",
                      style: GoogleFonts.kanit(
                        fontSize: fCaption,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: detailCtrl,
                    maxLines: 5,
                    style: GoogleFonts.kanit(
                      color: cTextMain,
                      fontWeight: FontWeight.normal,
                      fontSize: fBody,
                    ),
                    decoration: InputDecoration(
                      hintText: "ระบุรายละเอียด...",
                      hintStyle: GoogleFonts.kanit(),
                      filled: true,
                      fillColor: cBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: cAccent.withOpacity(0.5)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(color: cAccent.withOpacity(0.8)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(color: cDark, width: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "รูปภาพประกอบ (แตะเพื่อเปลี่ยน)",
                      style: GoogleFonts.kanit(
                        fontSize: fTitle,
                        fontWeight: FontWeight.w600,
                        color: cTextMain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildImagePreview(),
                ],
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (submitting || widget.item['status'] != 'pending')
                    ? null
                    : () async {
                        setState(() => submitting = true);
                        try {
                          final req = http.MultipartRequest(
                            "POST",
                            Uri.parse(AppConfig.url("repair.php")),
                          );
                          req.fields.addAll({
                            "action": "update",
                            "repair_id": widget.item['repair_id'].toString(),
                            "user_id": _userId.toString(),
                            "type_id": repairTypeId.toString(),
                            "detail": detailCtrl.text.trim(),
                            "is_image_deleted": _isImageDeleted ? "1" : "0",
                          });

                          if (_newImage != null) {
                            req.files.add(
                              await http.MultipartFile.fromPath(
                                "image",
                                _newImage!.path,
                              ),
                            );
                          }

                          final streamedRes = await req.send();
                          final res = await http.Response.fromStream(streamedRes);
                          final data = jsonDecode(res.body);

                          if (data["success"] == true && mounted) {
                            Navigator.pop(context, true);
                          }
                        } catch (_) {
                        } finally {
                          if (mounted) setState(() => submitting = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: cDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: submitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        "บันทึกการแก้ไข",
                        style: GoogleFonts.kanit(
                          color: Colors.white,
                          fontSize: fTitle,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    final bool hasImg =
        _newImage != null || (_oldImageUrl != null && !_isImageDeleted);

    return GestureDetector(
      onTap: widget.item['status'] != 'pending'
          ? null
          : () async {
              final XFile? p =
                  await _picker.pickImage(source: ImageSource.gallery);
              if (p != null) {
                setState(() {
                  _newImage = File(p.path);
                  _isImageDeleted = false;
                });
              }
            },
      child: Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          color: cBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cAccent.withOpacity(0.8)),
        ),
        child: Stack(
          children: [
            Center(
              child: _newImage != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        _newImage!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                      ),
                    )
                  : (_oldImageUrl != null && !_isImageDeleted)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            _oldImageUrl!,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            loadingBuilder:
                                (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: cDark,
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(
                                  Icons.image_not_supported_rounded,
                                  color: Colors.grey,
                                  size: 50,
                                ),
                              );
                            },
                          ),
                        )
                      : const Icon(
                          Icons.add_photo_alternate_rounded,
                          color: cDark,
                          size: 50,
                        ),
            ),
            if (hasImg && widget.item['status'] == 'pending')
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => setState(() {
                    _newImage = null;
                    _isImageDeleted = true;
                  }),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }
}

class _RepairCardNoStatus extends StatelessWidget {
  final Color statusColor;
  final String title;
  final String typeText;
  final String createdText;
  final String? imageUrl;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _RepairCardNoStatus({
    required this.statusColor,
    required this.title,
    required this.typeText,
    required this.createdText,
    this.imageUrl,
    required this.onDelete,
    required this.onTap,
  });

  IconData _getTypeIcon(String type) => repairTypeIcon(type);

  @override
  Widget build(BuildContext context) {
    final Color tColor = repairTypeColor(typeText);

    return Stack(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
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
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 102,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(18),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 78,
                            height: 78,
                            color: cBg,
                            child: (imageUrl == null || imageUrl!.trim().isEmpty)
                                ? Icon(
                                    _getTypeIcon(typeText),
                                    color: tColor,
                                    size: 30,
                                  )
                                : Image.network(
                                    imageUrl!,
                                    fit: BoxFit.cover,
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return const Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: cDark,
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder:
                                        (context, error, stackTrace) {
                                      return Icon(
                                        _getTypeIcon(typeText),
                                        color: tColor,
                                        size: 30,
                                      );
                                    },
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.kanit(
                                  fontWeight: FontWeight.w600,
                                  fontSize: fBody,
                                  color: cTextMain,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: tColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: tColor.withOpacity(0.45),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _getTypeIcon(typeText),
                                      size: 12,
                                      color: tColor,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      typeText,
                                      style: GoogleFonts.kanit(
                                        fontSize: fCaption,
                                        color: tColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    )
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                createdText,
                                style: GoogleFonts.kanit(
                                  fontSize: fCaption,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.normal,
                                ),
                              )
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (statusColor == const Color(0xFFD32F2F))
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              onPressed: onDelete,
              icon: const Icon(
                Icons.delete_rounded,
                size: 18,
                color: Colors.redAccent,
              ),
            ),
          ),
      ],
    );
  }
}