import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../notification_page.dart';

class HomeMainPage extends StatefulWidget {
  const HomeMainPage({super.key});

  @override
  State<HomeMainPage> createState() => _HomeMainPageState();
}

class _HomeMainPageState extends State<HomeMainPage> {
static const Color cBg = Color(0xFFF4EFE6);
  static const Color cCard = Color(0xFFFFFFFF);
  static const Color cAccent = Color(0xFFD7CCC8);
  static const Color cTextMain = Color(0xFF523D2D);
  static const Color cIcon = Color(0xFF7D6552);

  // 📏 Typography System
  static const double fHeader = 14.0;
  static const double fBody = 13.0;
  static const double fDetail = 12.0;
  static const double fCaption = 10.0;

  String displayName = "ผู้ใช้งาน", dormName = "หอพักของคุณ", dormAddress = "", dormPhone = "";
  String userProfile = ""; 
  int dormId = 0, userId = 0, unreadNotiCount = 0;
  bool loadingAnn = true, sortNewestFirst = true;
  List<Map<String, dynamic>> announcements = [];

  @override
  void initState() {
    super.initState();
    loadUser();
  }

  int _toInt(dynamic v) => (v is int) ? v : int.tryParse(v?.toString() ?? "0") ?? 0;

  String _userImgUrl(dynamic path) {
    final raw = (path ?? "").toString().trim().replaceAll("\\", "/");
    if (raw.isEmpty) return "";
    return Uri.encodeFull(AppConfig.url(raw.startsWith("uploads/") ? raw : "uploads/profiles/$raw"));
  }

  String _announcementImgUrl(dynamic path) {
    final raw = (path ?? "").toString().trim().replaceAll("\\", "/");
    if (raw.isEmpty) return "";
    return Uri.encodeFull(AppConfig.url(raw));
  }

  String _formatThaiDate(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return "";
    try {
      final dt = DateTime.parse(dateStr.trim().replaceFirst(" ", "T"));
      const months = ["ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."];
      return "${dt.day} ${months[dt.month - 1]} ${dt.year + 543} • ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} น.";
    } catch (_) { return dateStr ?? ""; }
  }

  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      dormId = prefs.getInt("dorm_id") ?? 0;
      userId = prefs.getInt("user_id") ?? 0;
      displayName = (prefs.getString("full_name") ?? prefs.getString("username") ?? "ผู้ใช้งาน").trim();
      dormName = (prefs.getString("dorm_name") ?? "หอพักของคุณ").trim();
      userProfile = prefs.getString("user_profile") ?? ""; 
    });
    await Future.wait([fetchDormContact(), fetchAnnouncements(), fetchUnreadNotiCount()]);
  }

  Future<void> fetchDormContact() async {
    if (dormId == 0) return;
    try {
      final res = await http.get(Uri.parse(AppConfig.url("dorm_setup.php?action=get&dorm_id=$dormId")));
      final data = jsonDecode(res.body);
      if (data["ok"] == true && data["dorm"] != null) {
        setState(() {
          dormName = data["dorm"]["dorm_name"] ?? dormName;
          dormAddress = data["dorm"]["dorm_address"] ?? "";
          dormPhone = data["dorm"]["dorm_phone"] ?? "";
        });
      }
    } catch (e) { debugPrint("Fetch Dorm Error: $e"); }
  }

  Future<void> fetchAnnouncements() async {
    if (dormId == 0) return;
    setState(() => loadingAnn = true);
    try {
      final res = await http.get(Uri.parse(AppConfig.url("announcements.php?action=list&dorm_id=$dormId")));
      final data = jsonDecode(res.body);
      if (data["ok"] == true) {
        final list = List<Map<String, dynamic>>.from(data["data"] ?? []);
        list.sort((a, b) {
          final ap = _toInt(a["is_pinned"]), bp = _toInt(b["is_pinned"]);
          if (ap != bp) return bp.compareTo(ap);
          return sortNewestFirst 
            ? b["created_at"].toString().compareTo(a["created_at"].toString()) 
            : a["created_at"].toString().compareTo(b["created_at"].toString());
        });
        setState(() => announcements = list);
      }
    } catch (e) { debugPrint("Ann Error: $e"); }
    finally { if (mounted) setState(() => loadingAnn = false); }
  }

  Future<void> fetchUnreadNotiCount() async {
    if (userId == 0) return;
    try {
      final res = await http.post(Uri.parse(AppConfig.url("notifications.php")), body: {
        "action": "unreadCount", 
        "user_id": userId.toString(),
        "dorm_id": dormId.toString(),
      });
      final data = jsonDecode(res.body);
      if (data["ok"] == true || data["success"] == true) {
        setState(() => unreadNotiCount = _toInt(data["count"]));
      }
    } catch (e) { debugPrint("Noti Error: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 100, 
        automaticallyImplyLeading: false,
        title: _buildAppBarTitle(),
        actions: [_notiBellStyleAdmin()],
      ),
      body: RefreshIndicator(
        onRefresh: loadUser,
        color: cTextMain,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
          children: [
            _buildDormContactCard(),
            const SizedBox(height: 24),
            _announcementHeader(),
            const SizedBox(height: 12),
            if (loadingAnn) 
              const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: cTextMain, strokeWidth: 3)))
            else if (announcements.isEmpty) 
              _emptyPlaceholder()
            else 
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: announcements.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) => _buildPostCard(announcements[index]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBarTitle() {
    return Row(
      children: [
        Container(
          width: 54, height: 54,
          decoration: const BoxDecoration(color: cAccent, shape: BoxShape.circle),
          child: ClipOval(
            child: userProfile.isNotEmpty 
              ? Image.network(
                  _userImgUrl(userProfile), 
                  fit: BoxFit.cover,
                  errorBuilder: (_,__,___) => const Icon(Icons.person, color: cIcon, size: 30),
                  loadingBuilder: (context, child, progress) => progress == null ? child : const CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_rounded, color: cIcon, size: 32),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_getGreetingText(), style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
              Text(displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.apartment_rounded, size: 14, color: cIcon),
                  const SizedBox(width: 4),
                  Expanded(child: Text(dormName, style: const TextStyle(fontSize: 12, color: cIcon, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getGreetingText() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'สวัสดีตอนเช้า ☀️';
    if (hour < 17) return 'สวัสดีตอนบ่าย 🌤️';
    return 'สวัสดีตอนเย็น 🌙';
  }

  Widget _notiBellStyleAdmin() {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            InkWell(
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationPage()));
                fetchUnreadNotiCount();
              },
              borderRadius: BorderRadius.circular(50),
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                child: const Icon(Icons.notifications_none_rounded, size: 26, color: cTextMain),
              ),
            ),
            if (unreadNotiCount > 0)
              Positioned(
                right: 2, top: 2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(unreadNotiCount > 99 ? "99+" : unreadNotiCount.toString(), 
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDormContactCard() => Container(
    width: double.infinity, 
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: cCard, 
      borderRadius: BorderRadius.circular(20), 
      boxShadow: [BoxShadow(color: cTextMain.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
    ),
    child: Column(children: [
      Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: cBg, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.business_rounded, color: cTextMain, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Text(dormName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cTextMain))),
      ]),
      const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1)),
      if (dormPhone.isNotEmpty) _contactItem(Icons.phone_iphone_rounded, dormPhone),
      if (dormAddress.isNotEmpty) _contactItem(Icons.location_on_rounded, dormAddress),
    ]),
  );

  Widget _contactItem(IconData i, String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(i, size: 16, color: cIcon.withOpacity(0.7)),
        const SizedBox(width: 10),
        Expanded(child: Text(t, style: const TextStyle(color: cTextMain, fontSize: fDetail), maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        InkWell(
          onTap: () { Clipboard.setData(ClipboardData(text: t)); _snack("คัดลอกลงคลิปบอร์ดแล้ว"); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: cBg.withOpacity(0.4), borderRadius: BorderRadius.circular(8)),
            child: const Text("คัดลอก", style: TextStyle(color: cIcon, fontWeight: FontWeight.bold, fontSize: 10)),
          ),
        ),
      ],
    ),
  );

  Widget _announcementHeader() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      const Text("ความเคลื่อนไหวล่าสุด", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cTextMain)),
      TextButton.icon(
        onPressed: () { setState(() => sortNewestFirst = !sortNewestFirst); fetchAnnouncements(); },
        icon: Icon(Icons.sort_rounded, size: 18, color: cTextMain.withOpacity(0.7)),
        label: Text(sortNewestFirst ? "ใหม่ที่สุด" : "เก่าที่สุด", style: const TextStyle(fontSize: 12, color: cTextMain, fontWeight: FontWeight.bold)),
        style: TextButton.styleFrom(backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      ),
    ],
  );

  Widget _buildPostCard(Map<String, dynamic> item) {
    final isPinned = (item["is_pinned"]?.toString() == "1");
    final imgUrl = _announcementImgUrl(item["image"]);
    
    return Container(
      decoration: BoxDecoration(
        color: cCard, 
        borderRadius: BorderRadius.circular(20), 
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))]
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(backgroundColor: cBg, child: const Icon(Icons.campaign_rounded, color: cIcon)),
          title: Row(children: [
            Expanded(child: Text(item["title"] ?? "แจ้งข่าวสาร", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cTextMain))),
            if (isPinned) const Icon(Icons.push_pin_rounded, size: 16, color: Colors.orange),
          ]),
          subtitle: Text(_formatThaiDate(item["created_at"]), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), 
          child: Text(item["detail"] ?? "", style: const TextStyle(fontSize: fBody, color: cTextMain, height: 1.5)),
        ),
        if (imgUrl.isNotEmpty) 
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)), 
            child: Image.network(
              imgUrl, 
              width: double.infinity, 
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => const SizedBox.shrink(),
            )
          ),
      ]),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Kanit')), 
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Widget _emptyPlaceholder() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 50),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 60, color: cIcon.withOpacity(0.2)),
          const SizedBox(height: 10),
          Text("ยังไม่มีประกาศในขณะนี้", style: TextStyle(color: cIcon.withOpacity(0.4), fontSize: 14)),
        ],
      ),
    ),
  );
}