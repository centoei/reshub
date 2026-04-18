import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config.dart';
import '../profile_page.dart';

class TenantListAdminPage extends StatefulWidget {
  const TenantListAdminPage({super.key});

  @override
  State<TenantListAdminPage> createState() => _TenantListAdminPageState();
}

class _TenantListAdminPageState extends State<TenantListAdminPage> with SingleTickerProviderStateMixin {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cIcon = Color(0xFF523D2D);
  static const Color cTextMain = Color(0xFF603F26);
  
  static const Color cPrimaryBright = Color(0xFF007BFF); 
  static const Color cAdminBright = Color(0xFFFF9800);   

  // 📏 Typography มาตราส่วนใหม่
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle = 15.0;  // หัวข้อย่อย
  static const double fBody = 13.0;   // เนื้อหา
  static const double fCaption = 11.0;

  bool loading = true;
  int dormId = 0;
  late TabController _tabController; 

  List<Map<String, dynamic>> allUsers = []; 
  String keyword = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); 
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt("dorm_id") ?? 0;
    if (!mounted) return;
    setState(() => dormId = id);
    await _fetchTenants();
  }

  Future<void> _fetchTenants() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      final uri = Uri.parse(AppConfig.url("tenants_api.php")).replace(
        queryParameters: {"action": "list", "dorm_id": dormId.toString()},
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      if (data is Map && (data["ok"] == true || data["success"] == true)) {
        final list = (data["data"] as List?) ?? [];
        if (!mounted) return;
        setState(() {
          allUsers = list.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _roomLabel(Map<String, dynamic> t) {
    if ((t["role"] ?? "").toString().toLowerCase() == "admin") return "ผู้ดูแลหอพัก";
    final b = (t["building"] ?? "").toString().trim();
    final r = (t["room_number"] ?? "").toString().trim();
    if (b.isEmpty && r.isEmpty) return "รอการจัดห้อง";
    return b.isEmpty ? r : (r.isEmpty ? b : "$b-$r");
  }

  List<Map<String, dynamic>> _filteredList(String role) {
    final k = keyword.trim().toLowerCase();
    Iterable<Map<String, dynamic>> list = allUsers.where((u) {
      final userRole = (u["role"] ?? "tenant").toString().toLowerCase();
      return role == "admin" ? userRole == "admin" : userRole == "tenant";
    });
    if (k.isEmpty) return list.toList();
    return list.where((u) {
      final name = (u["full_name"] ?? "").toString().toLowerCase();
      final room = _roomLabel(u).toLowerCase();
      return name.contains(k) || room.contains(k);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 50,
        title: Text("รายชื่อผู้เช่าหอพัก", style: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: fHeader, color: cTextMain)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: cTextMain, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: cTextMain,
          unselectedLabelColor: Colors.grey,
          indicatorColor: cTextMain,
          labelStyle: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: fTitle),
          tabs: const [ Tab(text: "ผู้เช่า"), Tab(text: "ผู้ดูแล") ],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: cTextMain))
          : Column(
              children: [
                _buildSearchField(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [ _buildListView("tenant"), _buildListView("admin") ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SizedBox(
        height: 40,
        child: TextField(
          onChanged: (v) => setState(() => keyword = v),
          style: GoogleFonts.kanit(fontSize: fBody),
          decoration: InputDecoration(
            hintText: "ค้นหาชื่อ หรือ เลขห้องพัก",
            hintStyle: GoogleFonts.kanit(fontSize: fBody, color: Colors.grey),
            prefixIcon: const Icon(Icons.search, size: 20, color: cIcon),
            filled: true,
            fillColor: cBg.withOpacity(0.3),
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ),
    );
  }

Widget _buildListView(String role) {
    final filtered = _filteredList(role);
    final bool isAdminPage = role == "admin";

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search_rounded, size: 60, color: cAccent),
            const SizedBox(height: 16),
            Text(
              "ไม่พบข้อมูลรายชื่อ",
              style: GoogleFonts.kanit(
                color: cTextMain, 
                fontWeight: FontWeight.normal, 
                fontSize: fTitle,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final u = filtered[index];
        final name = (u["full_name"] ?? "-").toString();
        final label = _roomLabel(u);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ProfilePage(tenantData: u)),
              ).then((value) => _fetchTenants());
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: cAccent.withOpacity(0.4),
                    child: Icon(
                      isAdminPage ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                      color: cIcon,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name, 
                          style: GoogleFonts.kanit(
                            fontWeight: FontWeight.w600, 
                            fontSize: fTitle, 
                            color: cTextMain
                          )
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              isAdminPage ? label : (label == "รอการจัดห้อง" ? label : "ห้อง $label"),
                              style: GoogleFonts.kanit(
                                color: Colors.grey.shade600, 
                                fontSize: fBody,
                                fontWeight: FontWeight.normal
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFD7CCC8)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}