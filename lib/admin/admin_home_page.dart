import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';

import '../config.dart';
import '../notification_page.dart';

import 'admin_pending_page.dart';
import 'meter_entry_page.dart';
import 'dorm_setup_page.dart';
import 'expense_page.dart';
import 'repair/repair_admin_page.dart';
import 'tenant_list_admin_page.dart';
import 'announce/announcement_admin_page.dart';
import 'dorm_link_settings_page.dart';
import 'bank_accounts_admin_page.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  // 🎨 Palette: Earth Tone (น้ำตาล-ครีม แบบในรูป)
  static const Color cCream = Color(0xFFF4EFE6);   // พื้นหลังครีมนวล
  static const Color cBrown = Color(0xFF8D7456);   // น้ำตาลกลางสำหรับไอคอน
  static const Color cDark  = Color(0xFF523D2D);   // น้ำตาลเข้มสำหรับตัวหนังสือหลัก

  bool loadingNoti = true;
  int unreadNotiCount = 0;
  int userId = 0, dormId = 0;
  String displayName = "ผู้ดูแล", dormName = "";

  int pendingApproveCount = 0;
  int pendingRepairCount = 0;
  int announcementCount = 0;

  List<dynamic> announcements = [];
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  String getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'สวัสดีตอนเช้า ☀️';
    if (hour < 17) return 'สวัสดีตอนบ่าย 🌤️';
    return 'สวัสดีตอนเย็น 🌙';
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        userId = prefs.getInt("user_id") ?? int.tryParse(prefs.getString("user_id") ?? "0") ?? 0;
        dormId = prefs.getInt("dorm_id") ?? int.tryParse(prefs.getString("dorm_id") ?? "0") ?? 0;
        dormName = (prefs.getString("dorm_name") ?? "").trim();
      });
    }
    await _fetchProfileAndNoti();
    await _fetchDormName();
  }

  Future<void> _fetchDormName() async {
    if (dormId == 0) return;
    try {
      final res = await http.get(Uri.parse(AppConfig.url("dorm_setup.php?action=get&dorm_id=$dormId")));
      final data = jsonDecode(res.body);
      if (data["ok"] == true && data["dorm"] != null) {
        if (mounted) {
          setState(() {
            dormName = (data["dorm"]["dorm_name"] ?? dormName).toString();
          });
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("dorm_name", dormName);
      }
    } catch (e) {
      debugPrint("DormName Error: $e");
    }
  }

  Future<void> _fetchProfileAndNoti() async {
    if (userId == 0) return;
    try {
      final resProfile = await http.post(
        Uri.parse(AppConfig.url("profile.php")),
        body: {"action": "get", "user_id": userId.toString()},
      );
      final dataProfile = jsonDecode(resProfile.body);
      if (dataProfile["success"] == true && dataProfile["data"] != null) {
        final profile = dataProfile["data"] as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            displayName = (profile["full_name"] ?? "ผู้ดูแล").toString().trim();
          });
        }
      }

      final resStats = await http.post(
        Uri.parse(AppConfig.url("dashboard_stats.php")),
        body: {
          "action": "get_all_stats",
          "dorm_id": dormId.toString(),
          "user_id": userId.toString(),
        },
      );

      final data = jsonDecode(resStats.body);
      if (mounted && data is Map && data["success"] == true) {
        setState(() {
          unreadNotiCount = int.tryParse(data["unread_count"].toString()) ?? 0;
          pendingApproveCount = int.tryParse(data["pending_approve"].toString()) ?? 0;
          pendingRepairCount = int.tryParse(data["pending_repair"].toString()) ?? 0;
          announcementCount = int.tryParse(data["total_announcements"].toString()) ?? 0;
          announcements = (data["announcements_list"] as List?) ?? [];
          loadingNoti = false;
        });
        if (announcements.isNotEmpty) _startAutoSlider();
      }
    } catch (e) {
      if (mounted) setState(() => loadingNoti = false);
    }
  }

  void _startAutoSlider() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!_pageController.hasClients || announcements.isEmpty) return;
      int next = _currentPage + 1;
      if (next >= announcements.length) next = 0;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
    });
  }

  String _normalizeImageUrl(dynamic rawImage) {
    final image = (rawImage ?? "").toString().trim();
    if (image.isEmpty || image == "DEL") return "";
    if (image.startsWith("http")) return image;
    return AppConfig.url(image);
  }

  Future<bool> _ensureAdmin(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final roleInDorm = (prefs.getString("role_in_dorm") ?? "").toLowerCase();
    final approveStatus = (prefs.getString("approve_status") ?? "").toLowerCase();
    return (approveStatus == "approved" && (roleInDorm == "admin" || roleInDorm == "owner"));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cCream,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 110,
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Container(
                width: 58, height: 58,
                decoration: const BoxDecoration(color: Color(0xFFDCD2C1), shape: BoxShape.circle),
                child: const Center(child: Icon(Icons.person_rounded, color: cDark, size: 38)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(getGreeting(), style: GoogleFonts.kanit(fontSize: 12, color: Colors.grey.shade600)),
                    Text(displayName, style: GoogleFonts.kanit(fontSize: 18, fontWeight: FontWeight.bold, color: cDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.apartment_rounded, size: 14, color: cBrown),
                        const SizedBox(width: 4),
                        Expanded(child: Text(dormName.isEmpty ? "ข้อมูลหอพัก" : dormName, style: GoogleFonts.kanit(fontSize: 12, color: cBrown, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [_notificationButton()],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchProfileAndNoti();
          await _fetchDormName();
        },
        color: cDark,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
          children: [
            _announcementSlider(),
            const SizedBox(height: 25),
            _statsSection(),
            const SizedBox(height: 20),
            _menuGrid(),
          ],
        ),
      ),
    );
  }

  Widget _notificationButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 16, top: 10),
      child: Center(
        child: InkWell(
          onTap: () async {
            if (await _ensureAdmin(context)) {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationPage()));
              _fetchProfileAndNoti();
            }
          },
          borderRadius: BorderRadius.circular(50),
          child: Container(
            width: 45, height: 45,
            decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.notifications_none_rounded, size: 28, color: cDark),
                if (!loadingNoti && unreadNotiCount > 0)
                  Positioned(
                    right: 10, top: 10,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(unreadNotiCount.toString(), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statsSection() {
    return Row(
      children: [
        _statCard("รออนุมัติ", pendingApproveCount.toString(), cBrown, Icons.person_add_alt_1_rounded,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPendingPage()))),
        const SizedBox(width: 8),
        _statCard("แจ้งซ่อม", pendingRepairCount.toString(), cBrown, Icons.build_circle_rounded,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RepairAdminPage()))),
        const SizedBox(width: 8),
        _statCard("ประกาศ", announcementCount.toString(), cBrown, Icons.campaign_rounded,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnouncementAdminPage()))),
      ],
    );
  }

  Widget _menuGrid() {
    return Column(
      children: [
        _row2(
          _menuTileCompact(icon: Icons.speed_rounded, title: "กรอกมิเตอร์", iconColor: cBrown, 
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MeterEntryPage()))),
          _menuTileCompact(icon: Icons.payments_rounded, title: "สรุปการเงิน", iconColor: cBrown,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpensePage()))),
        ),
        const SizedBox(height: 10),
        _row2(
          _menuTileCompact(icon: Icons.people_alt_rounded, title: "จัดการผู้เช่า", iconColor: cBrown,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TenantListAdminPage()))),
          _menuTileCompact(icon: Icons.add_home_work_rounded, title: "สร้างห้องพัก", iconColor: cBrown,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DormSetupPage()))),
        ),
        const SizedBox(height: 10),
        _row2(
          _menuTileCompact(icon: Icons.account_balance_wallet_rounded, title: "บัญชีธนาคาร", iconColor: cBrown,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BankAccountsAdminPage(dormId: dormId)))),
          _menuTileCompact(icon: Icons.settings_rounded, title: "ตั้งค่าหอพัก", iconColor: cBrown,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DormLinkSettingsPage()))),
        ),
      ],
    );
  }

  Widget _announcementSlider() {
    if (announcements.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: 110,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemCount: announcements.length,
            itemBuilder: (context, index) {
              final item = announcements[index];
              final String imageUrl = _normalizeImageUrl(item['image']);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 4))]),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnouncementAdminPage())),
                    child: Row(
                      children: [
                        if (imageUrl.isNotEmpty) SizedBox(width: 110, height: double.infinity, child: Image.network(imageUrl, fit: BoxFit.cover)),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item['title'] ?? 'ประกาศ', style: GoogleFonts.kanit(fontSize: 14, fontWeight: FontWeight.bold, color: cDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text(item['detail'] ?? '', style: GoogleFonts.kanit(fontSize: 12, color: Colors.grey.shade600), maxLines: 2, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(announcements.length, (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 5,
            width: _currentPage == index ? 15 : 5,
            decoration: BoxDecoration(color: _currentPage == index ? cDark : cDark.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
          )),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, Color color, IconData icon, {VoidCallback? onTap}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 6),
              Text(value, style: GoogleFonts.kanit(fontSize: 20, fontWeight: FontWeight.bold, color: cDark)),
              Text(label, style: GoogleFonts.kanit(fontSize: 10, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuTileCompact({required IconData icon, required String title, required Color iconColor, required Future<void> Function() onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: onTap,
      child: Container(
        height: 70, padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 3))]),
        child: Row(
          children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: cCream, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: iconColor, size: 20)),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: GoogleFonts.kanit(fontWeight: FontWeight.w500, fontSize: 13, color: cDark))),
            Icon(Icons.chevron_right_rounded, color: cDark.withOpacity(0.2), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _row2(Widget a, Widget b) => Row(children: [Expanded(child: a), const SizedBox(width: 8), Expanded(child: b)]);
}