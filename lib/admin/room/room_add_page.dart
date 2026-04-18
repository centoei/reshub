import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import '../../config.dart';
import 'room_model.dart';

class RoomAddPage extends StatefulWidget {
  final int dormId;
  const RoomAddPage({super.key, required this.dormId});

  @override
  State<RoomAddPage> createState() => _RoomAddPageState();
}

class _RoomAddPageState extends State<RoomAddPage> {
  final roomNoController = TextEditingController();
  final rentController = TextEditingController();

  // 📏 Typography มาตราส่วนใหม่
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle = 15.0;  // หัวข้อย่อย
  static const double fBody = 13.0;   // เนื้อหา

  String building = "A";
  int floor = 1;

  RoomType type = RoomType.air;
  RoomStatus status = RoomStatus.available;

  final buildings = ["A", "B", "C"];
  final floors = [1, 2, 3, 4];

  bool saving = false;

  @override
  void dispose() {
    roomNoController.dispose();
    rentController.dispose();
    super.dispose();
  }

  String _typeToDb(RoomType t) => t == RoomType.air ? "air" : "fan";
  String _statusToDb(RoomStatus s) => s == RoomStatus.available ? "available" : "occupied";

  Map<String, dynamic> _mustJson(http.Response res) {
    final raw = res.body.trim();
    final looksJson = raw.startsWith('{') || raw.startsWith('[');

    if (res.statusCode != 200) {
      throw Exception("HTTP ${res.statusCode}\n${res.body}");
    }
    if (!looksJson) {
      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      throw Exception("API ไม่ได้ส่ง JSON\ncontent-type: $ct\n${res.body}");
    }

    final data = jsonDecode(res.body);
    if (data is! Map) throw Exception("JSON shape ไม่ถูกต้อง");
    return Map<String, dynamic>.from(data);
  }

  Future<void> _save() async {
    if (saving) return;

    final roomNo = roomNoController.text.trim();
    final rent = int.tryParse(rentController.text.trim()) ?? 0;

    if (roomNo.isEmpty || rent <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("กรุณากรอกเลขห้องและค่าเช่าให้ถูกต้อง", style: GoogleFonts.kanit(fontSize: fBody))),
      );
      return;
    }

    setState(() => saving = true);

    try {
      final url = Uri.parse(AppConfig.url("rooms_api.php"));

      final res = await http.post(url, body: {
        "action": "add",
        "dorm_id": widget.dormId.toString(),
        "room_number": roomNo,
        "building": building,
        "floor": floor.toString(),
        "type": _typeToDb(type),
        "rent_price": rent.toString(),
        "status": _statusToDb(status),
      }).timeout(const Duration(seconds: 10));

      final data = _mustJson(res);

      if (!mounted) return;

      if (data["success"] == true || data["ok"] == true) {
        final newId = int.tryParse(data["room_id"]?.toString() ?? "") ?? 0;

        Navigator.pop(
          context,
          Room(
            roomId: newId,
            dormId: widget.dormId,
            roomNo: roomNo,
            building: building,
            floor: floor,
            type: type,
            status: status,
            rent: rent,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data["message"]?.toString() ?? "เพิ่มไม่สำเร็จ", style: GoogleFonts.kanit(fontSize: fBody))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("เชื่อมต่อไม่ได้: $e", style: GoogleFonts.kanit(fontSize: fBody))),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("เพิ่มห้องพัก", style: GoogleFonts.kanit(fontSize: fHeader, fontWeight: FontWeight.w500)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            _dropStr("ตึก", building, buildings, (v) => setState(() => building = v ?? "A")),

            _dropInt("ชั้น", floor, floors, (v) => setState(() => floor = v ?? 1)),

            _tf("เลขห้อง", roomNoController),
            _tf("ค่าเช่า", rentController, keyboardType: TextInputType.number),

            DropdownButtonFormField<RoomType>(
              initialValue: type,
              decoration: InputDecoration(
                labelText: "ประเภทห้อง", 
                labelStyle: GoogleFonts.kanit(fontSize: fTitle),
                border: const OutlineInputBorder(), 
                isDense: true
              ),
              items: [
                DropdownMenuItem(value: RoomType.air, child: Text("แอร์", style: GoogleFonts.kanit(fontSize: fBody))),
                DropdownMenuItem(value: RoomType.fan, child: Text("พัดลม", style: GoogleFonts.kanit(fontSize: fBody))),
              ],
              onChanged: (v) => setState(() => type = v ?? RoomType.air),
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: RadioListTile<RoomStatus>(
                    title: Text("ห้องว่าง", style: GoogleFonts.kanit(fontSize: fBody)),
                    value: RoomStatus.available,
                    groupValue: status,
                    onChanged: (v) => setState(() => status = v ?? RoomStatus.available),
                  ),
                ),
                Expanded(
                  child: RadioListTile<RoomStatus>(
                    title: Text("ไม่ว่าง", style: GoogleFonts.kanit(fontSize: fBody)),
                    value: RoomStatus.occupied,
                    groupValue: status,
                    onChanged: (v) => setState(() => status = v ?? RoomStatus.occupied),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            ElevatedButton.icon(
              icon: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(saving ? "กำลังบันทึก..." : "บันทึก", style: GoogleFonts.kanit(fontSize: fTitle)),
              onPressed: saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tf(String label, TextEditingController c, {TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: c,
        keyboardType: keyboardType,
        style: GoogleFonts.kanit(fontSize: fBody),
        decoration: InputDecoration(
          border: const OutlineInputBorder(), 
          isDense: true,
          labelText: label,
          labelStyle: GoogleFonts.kanit(fontSize: fTitle),
        ),
      ),
    );
  }

  Widget _dropStr(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          border: const OutlineInputBorder(), 
          isDense: true,
          labelText: label,
          labelStyle: GoogleFonts.kanit(fontSize: fTitle),
        ),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: GoogleFonts.kanit(fontSize: fBody)))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _dropInt(String label, int value, List<int> items, ValueChanged<int?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<int>(
        initialValue: value,
        decoration: InputDecoration(
          border: const OutlineInputBorder(), 
          isDense: true,
          labelText: label,
          labelStyle: GoogleFonts.kanit(fontSize: fTitle),
        ),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e.toString(), style: GoogleFonts.kanit(fontSize: fBody)))).toList(),
        onChanged: onChanged,
      ),
    );
  }
}