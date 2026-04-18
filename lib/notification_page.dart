import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config.dart';
import 'admin/admin_pending_page.dart';

// ✅ bill pages
import 'admin/bill/bill_detail_page.dart';
import 'admin/bill/bill_admin_page.dart';

// ✅ repair pages/model
import 'admin/repair/repair_model.dart';
import 'admin/repair/repair_detail_page.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  // 🎨 Palette สี: Vanilla Bean & Teddy Bear
  static const Color cVanilla  = Color(0xFFF4EFE6); 
  static const Color cTeddy    = Color(0xFF523D2D); 
  static const Color cBrown    = Color(0xFF8D7456); 
  static const Color cAccent   = Color(0xFFDCD2C1); 
  static const Color cWhite    = Colors.white;

  // 📏 Typography System
  static const double fHeader  = 18.0; // หัวข้อใหญ่
  static const double fTitle   = 15.0; // หัวข้อย่อย
  static const double fBody    = 13.0; // เนื้อหา
  static const double fCaption = 11.0;

  Uri get _notiApi => Uri.parse(AppConfig.url("notifications.php"));
  Uri get _repairApi => Uri.parse(AppConfig.url("repairs_api.php"));
  Uri get _billApi => Uri.parse(AppConfig.url("bills_api.php"));

  bool loading = true;
  int userId = 0;
  int dormId = 0;
  String platformRole = "user";
  String roleInDorm = "tenant";

  bool get isAdmin => platformRole == "platform_admin" || roleInDorm == "owner" || roleInDorm == "admin" || roleInDorm == "a" || roleInDorm == "o";
  String get roleForApi => isAdmin ? "admin" : "tenant";

  List<Map<String, dynamic>> items = [];
  int unread = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.kanit(fontSize: fBody, color: cVanilla)), 
        backgroundColor: cTeddy,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Map<String, dynamic>? _tryJson(String body) {
    try {
      final d = jsonDecode(body);
      return d is Map<String, dynamic> ? d : Map<String, dynamic>.from(d);
    } catch (_) { return null; }
  }

  Future<void> _init() async {
    setState(() => loading = true);
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getInt("user_id") ?? int.tryParse(prefs.getString("user_id") ?? "0") ?? 0;
    dormId = prefs.getInt("dorm_id") ?? int.tryParse(prefs.getString("dorm_id") ?? "0") ?? 0;
    platformRole = (prefs.getString("platform_role") ?? "user").toLowerCase();
    roleInDorm = (prefs.getString("role_in_dorm") ?? "tenant").toLowerCase();
    
    await _loadAll();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => loading = true);
    await Future.wait([_loadUnreadCount(), _loadList()]);
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadUnreadCount() async {
    try {
      final body = {"action": "unreadCount", "user_id": userId.toString()};
      if (dormId > 0) body["dorm_id"] = dormId.toString();
      final res = await http.post(_notiApi, body: body).timeout(const Duration(seconds: 10));
      final data = _tryJson(res.body);
      if (data != null && (data["success"] == true || data["ok"] == true)) {
        if (mounted) setState(() => unread = int.tryParse("${data["count"]}") ?? 0);
      }
    } catch (_) {}
  }

  Future<void> _loadList() async {
    try {
      final body = {"action": "listNotifications", "user_id": userId.toString()};
      if (dormId > 0) body["dorm_id"] = dormId.toString();
      final res = await http.post(_notiApi, body: body).timeout(const Duration(seconds: 10));
      final data = _tryJson(res.body);
      if (data != null && (data["success"] == true || data["ok"] == true)) {
        final List raw = (data["data"] ?? []) as List;
        if (mounted) {
          setState(() {
            items = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            items.sort((a, b) => (int.tryParse("${b["notification_id"]}") ?? 0).compareTo(int.tryParse("${a["notification_id"]}") ?? 0));
          });
        }
      }
    } catch (e) { debugPrint("Error: $e"); }
  }

  Future<void> _markRead(int notificationId) async {
    try {
      final body = {"action": "markRead", "notification_id": notificationId.toString(), "user_id": userId.toString()};
      await http.post(_notiApi, body: body);
      final idx = items.indexWhere((x) => int.tryParse("${x["notification_id"]}") == notificationId);
      if (idx >= 0 && mounted) setState(() => items[idx]["is_read"] = 1);
      _loadUnreadCount();
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      final body = {"action": "markAllRead", "user_id": userId.toString()};
      if (dormId > 0) body["dorm_id"] = dormId.toString();
      await http.post(_notiApi, body: body);
      if (mounted) setState(() { for (var it in items) { it["is_read"] = 1; } unread = 0; });
    } catch (_) {}
  }

  Future<void> _deleteAllNotifications() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("ลบแจ้งเตือนทั้งหมด", style: GoogleFonts.kanit(fontWeight: FontWeight.w600, color: cTeddy, fontSize: fHeader)),
        content: Text("คุณแน่ใจใช่ไหมที่จะลบการแจ้งเตือนทั้งหมด?", style: GoogleFonts.kanit(fontSize: fBody)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("ยกเลิก", style: GoogleFonts.kanit(fontSize: fBody))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("ลบทั้งหมด", style: GoogleFonts.kanit(color: Colors.red, fontSize: fBody))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await http.post(_notiApi, body: {"action": "deleteAll", "user_id": userId.toString(), "dorm_id": dormId.toString()});
        _loadAll();
      } catch (_) {}
    }
  }

  Future<void> _openByNotification(Map<String, dynamic> it) async {
    final String type = (it["type"] ?? "").toString().toLowerCase();
    final int refId = int.tryParse("${it["ref_id"]}") ?? 0;
    
    if (mounted) setState(() => loading = true);
    
    try {
      if (type == "new_registration") {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPendingPage()));
      } 
      else if (type.contains("repair")) {
        if (refId > 0) {
          final m = await _fetchRepairById(refId);
          if (m != null && mounted) {
            await Navigator.push(context, MaterialPageRoute(
              builder: (_) => RepairDetailPage(repair: _repairFromApi(m), canEdit: isAdmin)
            ));
          } else {
            _snack("ไม่พบรายการแจ้งซ่อม ข้อมูลอาจถูกลบไปแล้ว");
          }
        }
      } 
      else if (type.contains("bill")) {
        if (refId > 0) {
          final bill = await _fetchBillByPaymentId(refId);
          if (bill != null && mounted) {
            await Navigator.push(context, MaterialPageRoute(
              builder: (_) => BillDetailPage(item: bill, isAdmin: isAdmin)
            ));
          } else {
            _snack("ไม่พบข้อมูลบิล รายการอาจถูกยกเลิกแล้ว");
          }
        }
      }
      await _loadAll();
    } catch (e) {
      _snack("เข้าถึงข้อมูลไม่ได้");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<Map<String, dynamic>?> _fetchRepairById(int repairId) async {
    try {
      final res = await http.post(_repairApi, body: {
        "action": "getRepairById", 
        "repair_id": repairId.toString(), 
        "dorm_id": dormId.toString()
      });
      final data = _tryJson(res.body);
      if (data != null && (data["success"] == true || data["ok"] == true)) {
        return Map<String, dynamic>.from(data["data"]);
      }
      return null;
    } catch (_) { return null; }
  }

  Future<BillItem?> _fetchBillByPaymentId(int paymentId) async {
    try {
      final res = await http.post(_billApi, body: {
        "action": "getPaymentById", 
        "payment_id": paymentId.toString(), 
        "user_id": userId.toString(), 
        "role": roleForApi, 
        "dorm_id": dormId.toString()
      });
      final data = _tryJson(res.body);
      if (data != null && (data["success"] == true || data["ok"] == true)) {
        return BillItem.fromJson(Map<String, dynamic>.from(data["data"]));
      }
      return null;
    } catch (_) { return null; }
  }

  RepairModel _repairFromApi(Map<String, dynamic> m) {
    return RepairModel(
      repairId: int.tryParse("${m["repair_id"]}") ?? 0,
      type: (m["repair_type"] ?? m["type_name"] ?? "ทั่วไป").toString(),
      room: "${m['building_name'] ?? ''} ${m['room_number'] ?? ''}".trim(),
      status: (m["status"] ?? "pending").toString(),
      statusTh: (m["status_th"] ?? "รอดำเนินการ").toString(),
      detail: (m["detail"] ?? "").toString(),
      image: (m["image_path"] ?? "").toString(),
      createdAt: (m["created_at"] ?? "").toString(),
      fullName: (m["full_name"] ?? "").toString(),
      phone: (m["phone"] ?? "").toString(),
    );
  }

  String _prettyThaiDate(String raw) {
    if (raw.isEmpty) return "";
    try {
      final dt = DateTime.parse(raw.replaceFirst(" ", "T"));
      const thMonths = ["ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."];
      return "${dt.day} ${thMonths[dt.month - 1]} ${dt.year + 543} • ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) { return raw; }
  }

  Widget _getIconByType(String type, bool isRead) {
    IconData icon; Color color;
    if (type.contains("repair")) { icon = Icons.build_rounded; color = isRead ? Colors.grey : const Color(0xFFAD8B73); } 
    else if (type.contains("bill")) { icon = Icons.receipt_long_rounded; color = isRead ? Colors.grey : const Color(0xFF6B8E4E); } 
    else if (type == "new_registration") { icon = Icons.person_add_alt_1_rounded; color = isRead ? Colors.grey : const Color(0xFF548CA8); } 
    else { icon = Icons.notifications_none_rounded; color = isRead ? Colors.grey : cTeddy; }
    
    return Container(
      padding: const EdgeInsets.all(8), 
      decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), 
      child: Icon(icon, color: color, size: 18)
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cVanilla,
      appBar: AppBar(
        backgroundColor: cWhite, elevation: 0.5, centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: cTeddy), onPressed: () => Navigator.pop(context)),
        title: Text("แจ้งเตือน ${unread > 0 ? '($unread)' : ''}", style: GoogleFonts.kanit(fontWeight: FontWeight.w600, color: cTeddy, fontSize: fHeader)),
        actions: [
          TextButton(onPressed: unread > 0 ? _markAllRead : null, child: Text("อ่านทั้งหมด", style: GoogleFonts.kanit(fontSize: 12, fontWeight: FontWeight.w600, color: unread > 0 ? cBrown : Colors.grey))),
          IconButton(onPressed: items.isEmpty ? null : _deleteAllNotifications, icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 20)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll, color: cTeddy,
        child: loading
            ? const Center(child: CircularProgressIndicator(color: cTeddy))
            : items.isEmpty
                ? Center(child: Text("ยังไม่มีแจ้งเตือน", style: GoogleFonts.kanit(color: cBrown, fontSize: fBody)))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final it = items[i];
                      final isRead = (int.tryParse("${it["is_read"]}") ?? 0) == 1;
                      final nid = int.tryParse("${it["notification_id"]}") ?? 0;
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15), color: cWhite,
                          border: isRead ? Border.all(color: cTeddy.withOpacity(0.05)) : Border.all(color: cAccent, width: 1.2),
                          boxShadow: [BoxShadow(color: cTeddy.withOpacity(0.02), blurRadius: 5, offset: const Offset(0, 2))]
                        ),
                        child: ListTile(
                          onTap: () async {
                            if (!isRead && nid > 0) await _markRead(nid);
                            await _openByNotification(it);
                          },
                          leading: _getIconByType(it["type"]?.toString().toLowerCase() ?? "", isRead),
                          title: Text(it["title"] ?? "", style: GoogleFonts.kanit(fontWeight: isRead ? FontWeight.normal : FontWeight.w600, fontSize: fTitle, color: isRead ? cTeddy.withOpacity(0.7) : cTeddy)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(it["message"] ?? "", maxLines: 2, style: GoogleFonts.kanit(fontSize: fBody, color: cTeddy.withOpacity(0.8), height: 1.4)),
                              const SizedBox(height: 4),
                              Text(_prettyThaiDate(it["created_at"] ?? ""), style: GoogleFonts.kanit(fontSize: fCaption, color: cBrown.withOpacity(0.6))),
                            ],
                          ),
                          trailing: isRead ? null : const Icon(Icons.circle, size: 8, color: Colors.redAccent),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}