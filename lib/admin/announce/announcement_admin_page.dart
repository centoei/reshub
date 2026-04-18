import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config.dart';

class AnnouncementAdminPage extends StatefulWidget {
  final bool openAddOnStart;
  const AnnouncementAdminPage({super.key, this.openAddOnStart = false});

  @override
  State<AnnouncementAdminPage> createState() => _AnnouncementAdminPageState();
}

class _AnnouncementAdminPageState extends State<AnnouncementAdminPage> {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cTextMain = Color(0xFF2A1F17);
  static const Color cDark = Color(0xFF523D2D);
  static const Color cCard = Colors.white;

  // 📏 มาตราส่วน Font ตามที่กำหนด
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle = 15.0;  // หัวข้อย่อย
  static const double fBody = 13.0;   // เนื้อหา
  static const double fCaption = 11.0;

  final ImagePicker _picker = ImagePicker();

  bool loading = true;
  bool saving = false;
  bool isAdding = false;
  bool isAscending = false;

  int dormId = 0;
  int userId = 0;

  final List<Map<String, dynamic>> items = [];
  final titleCtrl = TextEditingController();
  final detailCtrl = TextEditingController();

  bool pinned = false;
  File? pickedImage;
  Map<String, dynamic>? editingItem;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    detailCtrl.dispose();
    super.dispose();
  }

  String _formatPostDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return "ไม่ระบุวันที่";
    try {
      final DateTime dt = DateTime.parse(dateStr);
      const months = [
        "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.",
        "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."
      ];
      return "โพสต์เมื่อ: ${dt.day} ${months[dt.month - 1]} ${dt.year + 543}";
    } catch (e) {
      return dateStr;
    }
  }

  String _imgUrl(dynamic path) {
    final String p = (path ?? "").toString().trim();
    if (p.isEmpty) return "";
    return p.startsWith("http") ? p : AppConfig.url(p);
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      dormId = prefs.getInt("dorm_id") ?? 0;
      userId = prefs.getInt("user_id") ?? 0;
    });
    await fetchList();
    if (widget.openAddOnStart) {
      _goToForm();
    }
  }

  Future<void> fetchList() async {
    if (!mounted) return;
    setState(() => loading = true);

    try {
      final res = await http.get(
        Uri.parse(
          "${AppConfig.url("announcements.php")}?action=list&dorm_id=$dormId",
        ),
      );

      final data = jsonDecode(res.body);

      if (data["ok"] == true) {
        setState(() {
          items.clear();
          items.addAll(List<Map<String, dynamic>>.from(data["data"] ?? []));
          _sortItems(items);
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _sortItems(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final int idA = int.tryParse(a["announce_id"].toString()) ?? 0;
      final int idB = int.tryParse(b["announce_id"].toString()) ?? 0;
      return isAscending ? idA.compareTo(idB) : idB.compareTo(idA);
    });
  }

  void _toggleSort() {
    setState(() {
      isAscending = !isAscending;
      _sortItems(items);
    });
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1000,
        imageQuality: 80,
      );
      if (image != null) {
        setState(() => pickedImage = File(image.path));
      }
    } catch (_) {}
  }

  void _goToForm({Map<String, dynamic>? current}) {
    setState(() {
      isAdding = true;
      editingItem = current;
      titleCtrl.text = current?["title"] ?? "";
      detailCtrl.text = current?["detail"] ?? "";
      pinned = (current?["is_pinned"]?.toString() ?? "0") == "1";
      pickedImage = null;
    });
  }

  void _goBack() {
    setState(() {
      isAdding = false;
      editingItem = null;
      pickedImage = null;
      titleCtrl.clear();
      detailCtrl.clear();
      pinned = false;
    });
  }

  Future<void> toggleVisibility(String id, bool currentlyVisible) async {
    setState(() => loading = true);
    try {
      final res = await http.post(
        Uri.parse(AppConfig.url("announcements.php")),
        body: {
          "action": "update_visibility",
          "announce_id": id,
          "status": currentlyVisible ? "hidden" : "active",
        },
      );

      if (jsonDecode(res.body)["ok"] == true) {
        await fetchList();
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return isAdding ? _buildFormPage() : _buildListPage();
  }

  Widget _buildListPage() {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 60,
        centerTitle: true,
        title: Text(
          "จัดการประกาศ",
          style: GoogleFonts.kanit(
            color: cTextMain,
            fontWeight: FontWeight.w600,
            fontSize: fHeader,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: cTextMain,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            onPressed: () => _goToForm(),
            icon: const Icon(
              Icons.add_circle_rounded,
              color: cDark,
              size: 28,
            ),
            tooltip: 'เพิ่มข้อมูล',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildListHeader(),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(color: cDark),
                  )
                : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "ข่าวสารทั้งหมด (${items.length})",
            style: GoogleFonts.kanit(
              color: cTextMain,
              fontWeight: FontWeight.w600,
              fontSize: fTitle,
            ),
          ),
          InkWell(
            onTap: _toggleSort,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cAccent, width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.swap_vert_rounded, size: 16, color: cDark),
                  const SizedBox(width: 4),
                  Text(
                    isAscending ? "เก่าไปใหม่" : "ใหม่ไปเก่า",
                    style: GoogleFonts.kanit(
                      fontSize: fCaption,
                      fontWeight: FontWeight.normal,
                      color: cDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (items.isEmpty) {
      return Center(
        child: Text(
          "ยังไม่มีประกาศ",
          style: GoogleFonts.kanit(
            color: cDark,
            fontWeight: FontWeight.normal,
            fontSize: fBody,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 100),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final a = items[i];
        final id = a["announce_id"].toString();
        final bool isVisible =
            (a["status"]?.toString().toLowerCase() != "hidden");

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => _goToForm(current: a),
              child: Ink(
                decoration: BoxDecoration(
                  color: cCard,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(22),
                          ),
                          child: (a["image"] ?? "").toString().isNotEmpty
                              ? Opacity(
                                  opacity: isVisible ? 1.0 : 0.6,
                                  child: Image.network(
                                    _imgUrl(a["image"]),
                                    width: double.infinity,
                                    height: 200,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: double.infinity,
                                        height: 100,
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0xFFE0E0E0),
                                              Color(0xFFF5F5F5),
                                            ],
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.broken_image_rounded,
                                          color: Colors.grey,
                                          size: 38,
                                        ),
                                      );
                                    },
                                  ),
                                )
                              : Container(
                                  width: double.infinity,
                                  height: 100,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFFE0E0E0),
                                        Color(0xFFF5F5F5),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: (isVisible
                                      ? const Color(0xFF2E7D32)
                                      : Colors.grey)
                                  .withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isVisible ? "กำลังแสดง" : "ซ่อนอยู่",
                              style: GoogleFonts.kanit(
                                color: Colors.white,
                                fontSize: fCaption,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                        if ((a["is_pinned"]?.toString() ?? "0") == "1")
                          Positioned(
                            top: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFFE65100),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.push_pin_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a["title"] ?? "",
                            style: GoogleFonts.kanit(
                              fontSize: fTitle,
                              fontWeight: FontWeight.w600,
                              color: isVisible
                                  ? cTextMain
                                  : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            a["detail"] ?? "",
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.kanit(
                              fontSize: fBody,
                              color: isVisible
                                  ? Colors.black87
                                  : Colors.grey.shade500,
                              height: 1.5,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Divider(height: 1, thickness: 1, color: cBg),
                          const SizedBox(height: 15),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _formatPostDate(a["created_at"]),
                                    style: GoogleFonts.kanit(
                                      fontSize: fCaption,
                                      color: const Color(0xFF757575),
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _buildMiniBtn(
                                      icon: isVisible
                                          ? Icons.visibility_rounded
                                          : Icons.visibility_off_rounded,
                                      color: isVisible
                                          ? const Color(0xFF2E7D32)
                                          : Colors.grey,
                                      label: isVisible ? "ซ่อน" : "โชว์",
                                      onTap: () =>
                                          toggleVisibility(id, isVisible),
                                    ),
                                    _buildMiniBtn(
                                      icon: Icons.delete_sweep_rounded,
                                      color: const Color(0xFFD32F2F),
                                      label: "ลบ",
                                      onTap: () => deleteItem(id),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniBtn({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.kanit(
                color: color,
                fontSize: fCaption,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormPage() {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 60,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: cTextMain,
            size: 20,
          ),
          onPressed: _goBack,
        ),
        title: Text(
          editingItem != null ? "แก้ไขประกาศ" : "เพิ่มข้อมูล",
          style: GoogleFonts.kanit(
            color: cTextMain,
            fontWeight: FontWeight.w600,
            fontSize: fHeader,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImageFromGallery,
              child: Container(
                width: double.infinity,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: cAccent, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: _buildImagePreview(),
              ),
            ),
            const SizedBox(height: 25),
            _buildField(titleCtrl, "หัวข้อประกาศ", "พิมพ์หัวข้อ..."),
            const SizedBox(height: 20),
            _buildField(
              detailCtrl,
              "รายละเอียด",
              "พิมพ์ข้อมูลที่ต้องการแจ้ง...",
              maxLines: 6,
            ),
            const SizedBox(height: 15),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: cAccent.withOpacity(0.5)),
              ),
              child: CheckboxListTile(
                title: Text(
                  "ปักหมุดประกาศ",
                  style: GoogleFonts.kanit(
                    fontSize: fBody,
                    fontWeight: FontWeight.normal,
                    color: cTextMain,
                  ),
                ),
                value: pinned,
                activeColor: cDark,
                onChanged: (v) => setState(() => pinned = v ?? false),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
            const SizedBox(height: 35),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: saving ? null : _performSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cDark,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      )
                    : Text(
                        editingItem != null ? "บันทึกการแก้ไข" : "เพิ่มข้อมูล",
                        style: GoogleFonts.kanit(
                          color: Colors.white,
                          fontSize: fTitle,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    if (pickedImage != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.file(
              pickedImage!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: () => setState(() => pickedImage = null),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFFD32F2F),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      );
    } else if (editingItem != null &&
        (editingItem?["image"] ?? "").toString().isNotEmpty) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.network(
              _imgUrl(editingItem?["image"]),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.broken_image_rounded,
                    color: Colors.grey,
                    size: 42,
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              onTap: () => setState(() {
                editingItem?["image"] = "";
              }),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFFD32F2F),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.add_photo_alternate_rounded, color: cDark, size: 60),
        const SizedBox(height: 12),
        Text(
          "แตะเพื่อเลือกรูปภาพประกอบ",
          style: GoogleFonts.kanit(
            color: cDark,
            fontWeight: FontWeight.normal,
            fontSize: fBody,
          ),
        ),
      ],
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String label,
    String hint, {
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            label,
            style: GoogleFonts.kanit(
              fontSize: fTitle,
              fontWeight: FontWeight.w600,
              color: cTextMain,
            ),
          ),
        ),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: GoogleFonts.kanit(
            color: cTextMain,
            fontSize: fBody,
            fontWeight: FontWeight.normal,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.kanit(
              color: Colors.grey.shade400,
              fontSize: fBody,
            ),
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(
                color: cAccent.withOpacity(0.8),
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: cDark, width: 2),
            ),
            contentPadding: const EdgeInsets.all(20),
          ),
        ),
      ],
    );
  }

  Future<void> _performSave() async {
    if (titleCtrl.text.trim().isEmpty) return;

    setState(() => saving = true);

    try {
      final req = http.MultipartRequest(
        "POST",
        Uri.parse(AppConfig.url("announcements.php")),
      );

      req.fields.addAll({
        "action": editingItem != null ? "update" : "add",
        "dorm_id": dormId.toString(),
        "user_id": userId.toString(),
        "title": titleCtrl.text.trim(),
        "detail": detailCtrl.text.trim(),
        "is_pinned": pinned ? "1" : "0",
      });

      if (editingItem != null) {
        req.fields["announce_id"] =
            editingItem!["announce_id"].toString();
        if ((editingItem?["image"] ?? "").toString().isEmpty &&
            pickedImage == null) {
          req.fields["delete_image"] = "1";
        }
      }

      if (pickedImage != null) {
        req.files.add(
          await http.MultipartFile.fromPath("image", pickedImage!.path),
        );
      }

      final streamedRes = await req.send();
      final res = await http.Response.fromStream(streamedRes);

      if (jsonDecode(res.body)["ok"] == true) {
        _goBack();
        await fetchList();
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> deleteItem(String id) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
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
                  color: const Color(0xFFD32F2F).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Color(0xFFD32F2F),
                  size: 45,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "ลบประกาศ",
                style: GoogleFonts.kanit(
                  fontSize: fHeader,
                  fontWeight: FontWeight.w600,
                  color: cTextMain,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "คุณแน่ใจหรือไม่ที่จะลบประกาศนี้?\nข้อมูลจะหายไปอย่างถาวร",
                textAlign: TextAlign.center,
                style: GoogleFonts.kanit(
                  fontSize: fBody,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      child: Text(
                        "ลบข้อมูล",
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
                        side: const BorderSide(
                          color: Color(0xFFFFDBB5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        "ยกเลิก",
                        style: GoogleFonts.kanit(
                          color: const Color(0xFF6C4E31),
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

    if (ok == true) {
      setState(() => loading = true);
      try {
        final res = await http.post(
          Uri.parse(AppConfig.url("announcements.php")),
          body: {
            "action": "delete",
            "announce_id": id,
            "dorm_id": dormId.toString(),
          },
        );

        if (jsonDecode(res.body)["ok"] == true) {
          await fetchList();
        }
      } catch (_) {
      } finally {
        if (mounted) setState(() => loading = false);
      }
    }
  }
}