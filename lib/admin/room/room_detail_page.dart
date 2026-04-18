import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import '../../config.dart';
import 'room_model.dart';

class RoomDetailPage extends StatefulWidget {
  final int dormId;
  final Room room;

  const RoomDetailPage({
    super.key,
    required this.dormId,
    required this.room,
  });

  @override
  State<RoomDetailPage> createState() => _RoomDetailPageState();
}

class _RoomDetailPageState extends State<RoomDetailPage> {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cIcon = Color(0xFF523D2D);
  static const Color cTextMain = Color(0xFF2A1F17);
  static const Color cSoft = Color(0xFFEEE6DA);
  static const Color cBorder = Color(0xFFCBBBA7);
  static const Color cDanger = Color(0xFFC62828);

  // 📏 มาตราส่วน Font ตามที่กำหนด
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle = 15.0;  // หัวข้อย่อย
  static const double fBody = 13.0;   // เนื้อหา
  static const double fCaption = 11.0;

  late TextEditingController rentController;
  late RoomType type;
  late RoomStatus status;
  late int rent;

  bool isEdit = false;
  bool saving = false;
  late Room _room;

  int defaultRentFan = 0;
  int defaultRentAir = 0;

  @override
  void initState() {
    super.initState();
    _room = widget.room;
    rent = _room.rent;
    rentController = TextEditingController(text: rent.toString());
    type = _room.type;
    status = _room.status;
    _fetchDefaultPrices();
  }

  Future<void> _fetchDefaultPrices() async {
    try {
      final res = await http.get(
        Uri.parse(
          "${AppConfig.url("rooms_api.php")}?action=defaults&dorm_id=${widget.dormId}",
        ),
      );
      final data = jsonDecode(res.body);
      if (data["ok"] == true && mounted) {
        setState(() {
          defaultRentFan = (data["settings"]?["default_rent_fan"] ?? 0).toInt();
          defaultRentAir = (data["settings"]?["default_rent_air"] ?? 0).toInt();
        });
      }
    } catch (e) {
      debugPrint("Fetch Default Price Error: $e");
    }
  }

  @override
  void dispose() {
    rentController.dispose();
    super.dispose();
  }

  Future<bool?> _showCustomConfirmDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
    String confirmText = "ยืนยัน",
    Color? confirmBtnColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: iconColor),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: GoogleFonts.kanit(
                  fontSize: fHeader,
                  fontWeight: FontWeight.w600,
                  color: cTextMain,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: GoogleFonts.kanit(
                  fontSize: fBody,
                  color: Colors.black54,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: confirmBtnColor ?? cIcon,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        confirmText,
                        style: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: fTitle),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: cBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
  }

  Future<void> _deleteRoom() async {
    final bool? confirm = await _showCustomConfirmDialog(
      title: "ลบห้องพัก",
      message: "คุณแน่ใจใช่ไหมที่จะลบห้อง ${_room.roomNo}?\nข้อมูลจะหายไปอย่างถาวร",
      icon: Icons.delete_forever_rounded,
      iconColor: cDanger,
      confirmText: "ลบห้องพัก",
      confirmBtnColor: cDanger,
    );
    if (confirm != true) return;

    setState(() => saving = true);
    try {
      final res = await http.post(
        Uri.parse(AppConfig.url("rooms_api.php")),
        body: {
          "action": "delete",
          "dorm_id": widget.dormId.toString(),
          "room_id": _room.roomId.toString(),
        },
      );
      final data = jsonDecode(res.body);
      if (data["ok"] == true && mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _toggleEditSave() async {
    if (saving) return;
    if (!isEdit) {
      setState(() => isEdit = true);
      return;
    }

    final newRent = int.tryParse(rentController.text.trim());
    if (newRent == null || newRent <= 0) return;

    setState(() => saving = true);
    try {
      final res = await http.post(
        Uri.parse(AppConfig.url("rooms_api.php")),
        body: {
          "action": "update",
          "dorm_id": widget.dormId.toString(),
          "room_id": _room.roomId.toString(),
          "rent_price": rentController.text.trim(),
          "room_type": type.dbValue,
          "status": status.dbValue,
        },
      );
      final data = jsonDecode(res.body);
      if (data["ok"] == true && mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 60,
        elevation: 0.5,
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: cTextMain,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "ห้อง ${_room.roomNo}",
          style: GoogleFonts.kanit(
            color: cTextMain,
            fontWeight: FontWeight.w600,
            fontSize: fHeader,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: saving ? null : _toggleEditSave,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cIcon,
                      ),
                    )
                  : Icon(
                      isEdit
                          ? Icons.check_circle_rounded
                          : Icons.edit_note_rounded,
                      color: cIcon,
                    ),
              label: Text(
                isEdit ? "บันทึก" : "แก้ไข",
                style: GoogleFonts.kanit(
                  color: cIcon,
                  fontWeight: FontWeight.w600,
                  fontSize: fTitle,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildPriceHeader(),
                const SizedBox(height: 24),
                _buildSectionTitle("ข้อมูลห้องพัก"),
                _buildInfoCard(),
                const SizedBox(height: 24),
                _buildSectionTitle("ข้อมูลผู้เช่า"),
                _buildTenantCard(_room.tenant),
              ],
            ),
          ),
          if (isEdit)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: saving ? null : _deleteRoom,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: cIcon,
                  ),
                  label: Text(
                    "ลบห้องพักนี้ออกจากระบบ",
                    style: GoogleFonts.kanit(
                      color: cTextMain,
                      fontWeight: FontWeight.w600,
                      fontSize: fBody,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: cBorder, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: cSoft,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title,
        style: GoogleFonts.kanit(
          color: cTextMain,
          fontWeight: FontWeight.w600,
          fontSize: fTitle,
        ),
      ),
    );
  }

  Widget _buildPriceHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.payments_rounded,
                    size: 20,
                    color: cIcon,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "ค่าเช่าต่อเดือน",
                    style: GoogleFonts.kanit(
                      color: Colors.black87,
                      fontSize: fTitle,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
              if (!isEdit) _statusBadge(status),
            ],
          ),
          const SizedBox(height: 20),
          if (isEdit)
            TextField(
              controller: rentController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: cTextMain,
              ),
              decoration: InputDecoration(
                suffixText: "บาท",
                suffixStyle: GoogleFonts.kanit(fontSize: fBody),
                filled: true,
                fillColor: cBg.withOpacity(0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  "$rent",
                  style: GoogleFonts.kanit(
                    fontSize: 36,
                    fontWeight: FontWeight.w600,
                    color: cTextMain,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "บาท / เดือน",
                  style: GoogleFonts.kanit(
                    fontSize: fTitle,
                    fontWeight: FontWeight.normal,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          _rowInfo("อาคาร", _room.building, Icons.business),
          const Divider(height: 24, color: cBg, thickness: 1),
          Row(
            children: [
              Expanded(
                child: _rowInfoSmall(
                  "ชั้น",
                  "${_room.floor}",
                  Icons.layers,
                ),
              ),
              Container(
                width: 1,
                height: 30,
                color: cAccent.withOpacity(0.5),
                margin: const EdgeInsets.symmetric(horizontal: 10),
              ),
              Expanded(
                child: _rowInfoSmall(
                  "เลขห้อง",
                  _room.roomNo,
                  Icons.tag,
                ),
              ),
            ],
          ),
          const Divider(height: 32, color: cBg, thickness: 2),
          if (isEdit)
            _buildNewEditSelectors()
          else ...[
            _rowInfo(
              "ประเภท",
              type.label,
              type == RoomType.air ? Icons.ac_unit : Icons.wind_power,
            ),
            _rowInfo(
              "สถานะห้อง",
              _getStatusLabel(status),
              Icons.info_outline,
              valueColor: cTextMain,
            ),
          ],
        ],
      ),
    );
  }

  Widget _rowInfoSmall(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: cSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: cIcon),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.kanit(
                color: Colors.black54,
                fontSize: fCaption,
                fontWeight: FontWeight.normal,
              ),
            ),
            Text(
              value,
              style: GoogleFonts.kanit(
                fontSize: fTitle,
                fontWeight: FontWeight.w600,
                color: cTextMain,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNewEditSelectors() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "ประเภทห้องพัก",
          style: GoogleFonts.kanit(
            fontWeight: FontWeight.w600,
            fontSize: fTitle,
            color: cTextMain,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _typeButton(
                isSelected: type == RoomType.air,
                label: "แอร์",
                icon: Icons.ac_unit_rounded,
                onTap: () => setState(() => type = RoomType.air),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _typeButton(
                isSelected: type == RoomType.fan,
                label: "พัดลม",
                icon: Icons.wind_power_rounded,
                onTap: () => setState(() => type = RoomType.fan),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          "สถานะห้องพัก",
          style: GoogleFonts.kanit(
            fontWeight: FontWeight.w600,
            fontSize: fTitle,
            color: cTextMain,
          ),
        ),
        const SizedBox(height: 14),
        _statusButton(
          isSelected: status == RoomStatus.available,
          label: "ว่าง",
          icon: Icons.check_circle_outline,
          onTap: () => setState(() => status = RoomStatus.available),
        ),
        const SizedBox(height: 10),
        _statusButton(
          isSelected: status == RoomStatus.occupied,
          label: "ไม่ว่าง",
          icon: Icons.person_off_outlined,
          onTap: () => setState(() => status = RoomStatus.occupied),
        ),
        const SizedBox(height: 10),
        _statusButton(
          isSelected: status == RoomStatus.maintenance,
          label: "ซ่อม",
          icon: Icons.build_circle_outlined,
          onTap: () => setState(() => status = RoomStatus.maintenance),
        ),
      ],
    );
  }

  Widget _typeButton({
    required bool isSelected,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? cIcon : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isSelected ? cIcon : cBorder,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
              color: isSelected ? Colors.white : cIcon,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.kanit(
                color: isSelected ? Colors.white : cTextMain,
                fontWeight: FontWeight.w600,
                fontSize: fBody,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusButton({
    required bool isSelected,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? cIcon : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isSelected ? cIcon : cBorder,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? Colors.white : cIcon,
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: GoogleFonts.kanit(
                color: isSelected ? Colors.white : cTextMain,
                fontWeight: FontWeight.w600,
                fontSize: fBody,
              ),
            ),
            const Spacer(),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.white,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTenantCard(TenantInfo? tenant) {
    if (tenant == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            "ไม่มีข้อมูลผู้เช่า",
            style: GoogleFonts.kanit(
              color: Colors.black54,
              fontWeight: FontWeight.normal,
              fontSize: fBody,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          _rowInfo("ชื่อผู้เช่า", tenant.name ?? "-", Icons.person),
          _rowInfo("เบอร์โทร", tenant.phone ?? "-", Icons.phone),
          _rowInfo(
            "สถานะ",
            tenant.statusLabel,
            Icons.assignment_ind,
            valueColor: cTextMain,
          ),
        ],
      ),
    );
  }

  String _getStatusLabel(RoomStatus s) =>
      s == RoomStatus.available
          ? "ห้องว่าง"
          : (s == RoomStatus.occupied ? "มีผู้เช่าแล้ว" : "ซ่อมแซมอยู่");

  Widget _statusBadge(RoomStatus s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cSoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cBorder),
      ),
      child: Text(
        _getStatusLabel(s),
        style: GoogleFonts.kanit(
          color: cTextMain,
          fontSize: fCaption,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _rowInfo(
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cIcon),
          const SizedBox(width: 14),
          Text(
            label,
            style: GoogleFonts.kanit(
              color: Colors.black87,
              fontSize: fBody,
              fontWeight: FontWeight.normal,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.kanit(
              fontSize: fBody,
              fontWeight: FontWeight.w600,
              color: valueColor ?? cTextMain,
            ),
          ),
        ],
      ),
    );
  }
}