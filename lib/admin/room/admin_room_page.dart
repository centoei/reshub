import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config.dart';
import 'room_model.dart';
import 'room_detail_page.dart';

class AdminRoomPage extends StatefulWidget {
  const AdminRoomPage({super.key});

  @override
  State<AdminRoomPage> createState() => _AdminRoomPageState();
}

class _AdminRoomPageState extends State<AdminRoomPage> {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cIcon = Color(0xFF523D2D);
  static const Color cTextMain = Color(0xFF523D2D);

  // 📏 มาตราส่วน Font ตามที่กำหนด
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle = 15.0;  // หัวข้อย่อย
  static const double fBody = 13.0;   // เนื้อหา
  static const double fCaption = 11.0;

  int dormId = 0;
  List<Room> rooms = [];
  bool loading = true;

  RoomStatus? selectedStatus;
  RoomType? selectedType;

  Map<String, Map<int, List<Room>>> get groupedRooms {
    final Map<String, Map<int, List<Room>>> groups = {};
    for (final room in filteredRooms) {
      groups.putIfAbsent(room.building, () => {});
      groups[room.building]!.putIfAbsent(room.floor, () => []);
      groups[room.building]![room.floor]!.add(room);
    }
    return groups;
  }

  List<Room> get filteredRooms {
    return rooms.where((room) {
      final statusOk = selectedStatus == null || room.status == selectedStatus;
      final typeOk = selectedType == null || room.type == selectedType;
      return statusOk && typeOk;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    dormId = prefs.getInt("dorm_id") ?? prefs.getInt("selected_dorm_id") ?? 0;
    if (dormId > 0) {
      await fetchRooms();
    } else if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> fetchRooms() async {
    if (!mounted) return;
    setState(() => loading = true);

    try {
      final res = await http.post(
        Uri.parse(AppConfig.url("rooms_api.php")),
        body: {
          "action": "list",
          "dorm_id": dormId.toString(),
        },
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (data["ok"] == true || data["success"] == true) {
        final List list = data["data"] ?? data["rooms"] ?? [];
        if (mounted) {
          setState(() {
            rooms = list
                .map((e) => Room.fromJson(Map<String, dynamic>.from(e)))
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget _buildFilterSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: _dropClassic<RoomStatus?>(
              label: "สถานะ",
              val: selectedStatus,
              items: const [
                DropdownMenuItem(value: null, child: Text("ทั้งหมด")),
                DropdownMenuItem(value: RoomStatus.available, child: Text("ห้องว่าง")),
                DropdownMenuItem(value: RoomStatus.occupied, child: Text("ไม่ว่าง")),
                DropdownMenuItem(value: RoomStatus.maintenance, child: Text("ซ่อมแซม")),
              ],
              on: (v) => setState(() => selectedStatus = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _dropClassic<RoomType?>(
              label: "ประเภท",
              val: selectedType,
              items: const [
                DropdownMenuItem(value: null, child: Text("ทั้งหมด")),
                DropdownMenuItem(value: RoomType.air, child: Text("แอร์")),
                DropdownMenuItem(value: RoomType.fan, child: Text("พัดลม")),
              ],
              on: (v) => setState(() => selectedType = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropClassic<T>({
    required String label,
    required T val,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> on,
  }) {
    return SizedBox(
      height: 46,
      child: DropdownButtonFormField<T>(
        initialValue: val,
        selectedItemBuilder: (context) => items.map((i) {
          return Text(
            (i.child as Text).data ?? "",
            style: GoogleFonts.kanit(
              fontSize: fBody,
              color: cTextMain,
              fontWeight: FontWeight.normal,
            ),
          );
        }).toList(),
        items: items.map((i) {
          return DropdownMenuItem<T>(
            value: i.value,
            child: Text(
              (i.child as Text).data ?? "",
              style: GoogleFonts.kanit(fontSize: fBody, fontWeight: FontWeight.normal),
            ),
          );
        }).toList(),
        onChanged: on,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: cIcon, size: 18),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.kanit(color: cIcon, fontSize: 12, fontWeight: FontWeight.normal),
          filled: true,
          fillColor: cAccent.withOpacity(0.25),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
    );
  }

  Widget _roomListWithGroupHeaders() {
    if (filteredRooms.isEmpty) {
      return Center(
        child: Text(
          "ไม่พบข้อมูลห้องพัก",
          style: GoogleFonts.kanit(color: cTextMain, fontSize: fBody, fontWeight: FontWeight.normal),
        ),
      );
    }

    final groups = groupedRooms;
    final buildings = groups.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: fetchRooms,
      color: cTextMain,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        itemCount: buildings.length,
        itemBuilder: (context, bIndex) {
          final bName = buildings[bIndex];
          final floors = groups[bName]!.keys.toList()..sort();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: floors.map((fNum) {
              final roomsInFloor = groups[bName]![fNum]!;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.business, size: 15, color: cIcon),
                        const SizedBox(width: 8),
                        Text(
                          " $bName - ชั้น $fNum",
                          style: GoogleFonts.kanit(
                            fontSize: fTitle,
                            fontWeight: FontWeight.w600,
                            color: cTextMain,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Divider(
                            color: cAccent.withOpacity(0.5),
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final crossAxisCount = width > 700 ? 4 : 3;

                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.92,
                        ),
                        itemCount: roomsInFloor.length,
                        itemBuilder: (_, rIndex) => _roomCard(roomsInFloor[rIndex]),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _roomCard(Room room) {
    Color sColor;
    String sLabel;
    IconData sIcon;
    Color bgColor;

    if (room.status == RoomStatus.available) {
      sColor = Colors.green.shade700;
      sLabel = "ว่าง";
      sIcon = room.type == RoomType.air ? Icons.ac_unit_rounded : Icons.air_rounded;
      bgColor = Colors.green.shade50;
    } else if (room.status == RoomStatus.occupied) {
      sColor = Colors.red.shade700;
      sLabel = "ไม่ว่าง";
      sIcon = room.type == RoomType.air ? Icons.ac_unit_rounded : Icons.air_rounded;
      bgColor = Colors.red.shade50;
    } else {
      sColor = cIcon;
      sLabel = "ซ่อม";
      sIcon = Icons.build_circle_rounded;
      bgColor = cAccent.withOpacity(0.2);
    }

    return InkWell(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RoomDetailPage(dormId: dormId, room: room),
          ),
        );
        if (result == true) fetchRooms();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                    ),
                    child: Icon(sIcon, size: 22, color: sColor),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          room.roomNo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.kanit(
                            fontWeight: FontWeight.w600,
                            fontSize: 12.0,
                            color: cTextMain,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _statusBadgeSmall(sLabel, sColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: cTextMain.withOpacity(0.08),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  room.type == RoomType.air ? "แอร์" : "พัดลม",
                  style: GoogleFonts.kanit(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: room.type == RoomType.air
                        ? Colors.blue.shade700
                        : Colors.orange.shade800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadgeSmall(String label, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: GoogleFonts.kanit(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.normal,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 50,
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Text(
          "จัดการห้องพัก",
          style: GoogleFonts.kanit(
            color: cTextMain,
            fontWeight: FontWeight.w600,
            fontSize: fHeader,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: cTextMain, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          _buildFilterSection(),
          Expanded(
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: cTextMain,
                      strokeWidth: 2,
                    ),
                  )
                : _roomListWithGroupHeaders(),
          ),
        ],
      ),
    );
  }
}