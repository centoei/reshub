import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import '../config.dart';

class PlatformUserListPage extends StatefulWidget {
  const PlatformUserListPage({super.key});

  @override
  State<PlatformUserListPage> createState() => _PlatformUserListPageState();
}

class _PlatformUserListPageState extends State<PlatformUserListPage> with SingleTickerProviderStateMixin {
  // ⚙️ แผงควบคุมหน้าจอ
  bool _loading = true;
  bool _isAdding = false; 
  List<dynamic> _allUsers = []; 
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = ""; 

  // 📝 Controllers สำหรับหน้าเพิ่มข้อมูล
  final _formKey = GlobalKey<FormState>();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final userCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final confirmPassCtrl = TextEditingController();
  bool saving = false;
  bool obscure = true;

  // 🎨 Palette ใหม่: สดใสและคมชัด (Deep Coffee & Cream)
  static const Color cBg = Color(0xFFF4EFE6);       // ครีมสว่าง
  static const Color cAccent = Color(0xFFDCD2C1);   // ครีมเข้ม
  static const Color cTextMain = Color(0xFF2A1F17); // น้ำตาลเข้มจัด (คมชัด)
  static const Color cDark = Color(0xFF523D2D);     // น้ำตาลไอคอน
  static const Color cIconBlue = Color(0xFF1565C0); // สีน้ำเงินสำหรับปุ่มเพิ่ม

  // 📏 Typography System
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle  = 15.0; // หัวข้อย่อย
  static const double fBody   = 13.0; // เนื้อหา

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {}); 
    });
    fetchUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> fetchUsers() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final url = Uri.parse("${AppConfig.baseUrl}/platform_api.php");
      final res = await http.post(url, body: {"action": "listUsers"}).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data["success"] == true) {
          setState(() => _allUsers = data["data"] ?? []);
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveAdmin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final res = await http.post(Uri.parse("${AppConfig.baseUrl}/platform_api.php"), body: {
        "action": "addAdmin",
        "full_name": nameCtrl.text.trim(),
        "username": userCtrl.text.trim(),
        "password": passCtrl.text,
        "phone": phoneCtrl.text.trim(),
      });
      final data = jsonDecode(res.body);
      if (data["success"]) {
        setState(() => _isAdding = false);
        fetchUsers();
        _clearForm();
      }
    } catch (e) { debugPrint(e.toString()); }
    finally { if (mounted) setState(() => saving = false); }
  }

  void _clearForm() {
    nameCtrl.clear(); phoneCtrl.clear(); userCtrl.clear(); passCtrl.clear(); confirmPassCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isAdding) { setState(() => _isAdding = false); return false; }
        return true;
      },
      child: _isAdding ? _buildAddAdminPage() : _buildUserListPage(),
    );
  }

  // ---------------------------------------------------------
  // 🏢 1. หน้าแสดงรายชื่อ
  // ---------------------------------------------------------
  Widget _buildUserListPage() {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        toolbarHeight: 60,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: cTextMain),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("รายชื่อผู้ใช้งาน", style: GoogleFonts.kanit(fontWeight: FontWeight.w600, color: cTextMain, fontSize: fHeader)),
        centerTitle: true,
        actions: [
          if (_tabController.index == 1)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_rounded, color: cIconBlue, size: 28),
              onPressed: () => setState(() => _isAdding = true),
            ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: cTextMain,
          unselectedLabelColor: Colors.grey.shade500,
          labelStyle: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: fTitle),
          unselectedLabelStyle: GoogleFonts.kanit(fontWeight: FontWeight.w600, fontSize: fTitle),
          indicatorColor: cTextMain,
          indicatorWeight: 3,
          tabs: const [Tab(text: "ผู้ดูแลหอพัก"), Tab(text: "ผู้ดูแลระบบ")],
        ),
      ),
      body: Column(
        children: [
          _buildSearchBox(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: cDark))
                : TabBarView(
                    controller: _tabController,
                    children: [_buildUserList(false), _buildUserList(true)],
                  ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  // 📝 2. หน้ากรอกข้อมูล
  // ---------------------------------------------------------
  Widget _buildAddAdminPage() {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        leading: const SizedBox.shrink(), 
        title: Text(
          "เพิ่มผู้ดูแลระบบ", 
          style: GoogleFonts.kanit(fontWeight: FontWeight.w600, color: cTextMain, fontSize: fHeader)
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 26, color: cTextMain),
            onPressed: () => setState(() => _isAdding = false),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildSectionCard(
                title: "ข้อมูลผู้ดูแลระบบ",
                icon: Icons.admin_panel_settings_rounded,
                children: [
                  const SizedBox(height: 8),
                  TextFormField(controller: nameCtrl, style: GoogleFonts.kanit(fontSize: fBody), decoration: _dec("ชื่อ-นามสกุล", Icons.person_outline), validator: (v) => v!.isEmpty ? "กรุณากรอกชื่อ" : null),
                  const SizedBox(height: 16),
                  TextFormField(controller: phoneCtrl, keyboardType: TextInputType.phone, style: GoogleFonts.kanit(fontSize: fBody), decoration: _dec("เบอร์โทรศัพท์", Icons.phone_android_rounded), validator: (v) => v!.isEmpty ? "กรุณากรอกเบอร์" : null),
                  const SizedBox(height: 16),
                  TextFormField(controller: userCtrl, style: GoogleFonts.kanit(fontSize: fBody), decoration: _dec("Username", Icons.alternate_email_rounded), validator: (v) => v!.isEmpty ? "กรุณากรอก Username" : null),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passCtrl, 
                    obscureText: obscure, 
                    style: GoogleFonts.kanit(fontSize: fBody),
                    decoration: _dec("รหัสผ่าน", Icons.lock_outline_rounded, suffix: IconButton(
                      icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 20, color: cDark),
                      onPressed: () => setState(() => obscure = !obscure),
                    )), 
                    validator: (v) => v!.length < 4 ? "รหัสต้อง 4 ตัวขึ้นไป" : null
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: confirmPassCtrl, 
                    obscureText: obscure, 
                    style: GoogleFonts.kanit(fontSize: fBody),
                    decoration: _dec("ยืนยันรหัสผ่าน", Icons.lock_reset_rounded), 
                    validator: (v) => v != passCtrl.text ? "รหัสไม่ตรงกัน" : null
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cDark,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: saving ? null : _saveAdmin,
                  child: saving 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)) 
                    : Text("บันทึกข้อมูล", style: GoogleFonts.kanit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: fTitle)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: GoogleFonts.kanit(fontWeight: FontWeight.normal, color: cTextMain, fontSize: fBody),
        decoration: InputDecoration(
          hintText: "ค้นหาชื่อ หรือชื่อหอพัก...",
          hintStyle: GoogleFonts.kanit(fontSize: fBody, color: Colors.grey.shade400, fontWeight: FontWeight.normal),
          prefixIcon: const Icon(Icons.search_rounded, color: cTextMain),
          filled: true, fillColor: cBg.withOpacity(0.5),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildUserList(bool isSystemAdmin) {
    final list = _allUsers.where((u) {
      bool isMatchRole = isSystemAdmin 
          ? u['platform_role'] == 'platform_admin' 
          : (u['dorm_name'] != null && u['dorm_name'].toString().isNotEmpty);
      return isMatchRole && (u['full_name'] ?? "").toString().toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return RefreshIndicator(
      onRefresh: fetchUsers,
      color: cDark,
      child: list.isEmpty 
        ? Center(child: Text("ไม่พบข้อมูล", style: GoogleFonts.kanit(color: cDark, fontWeight: FontWeight.w600, fontSize: fBody)))
        : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: list.length,
            itemBuilder: (context, index) => _buildCard(list[index]),
          ),
    );
  }

  Widget _buildCard(Map u) {
    bool isAdminSystem = u['platform_role'] == 'platform_admin';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: isAdminSystem ? Colors.purple.withOpacity(0.1) : cAccent.withOpacity(0.4),
          child: Icon(
            isAdminSystem ? Icons.stars_rounded : Icons.admin_panel_settings_rounded,
            color: isAdminSystem ? Colors.purple : cDark,
            size: 30,
          ),
        ),
        title: Text(u['full_name'] ?? "-", style: GoogleFonts.kanit(fontWeight: FontWeight.w600, color: cTextMain, fontSize: fTitle)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text("หอพัก : ${u['dorm_name'] ?? 'ผู้ดูแลระบบ'}", style: GoogleFonts.kanit(color: Colors.grey.shade600, fontSize: fBody, fontWeight: FontWeight.normal)),
            const SizedBox(height: 2),
            Text("โทร : ${u['phone'] ?? '-'}", style: GoogleFonts.kanit(color: Colors.grey.shade500, fontSize: fBody, fontWeight: FontWeight.normal)),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: cDark.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: Text("แอดมิน", style: GoogleFonts.kanit(fontSize: 11, fontWeight: FontWeight.w600, color: cDark)),
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cAccent.withOpacity(0.6), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cDark, size: 22),
              const SizedBox(width: 10),
              Text(title, style: GoogleFonts.kanit(fontSize: fTitle, fontWeight: FontWeight.w600, color: cTextMain)),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(thickness: 1, height: 1),
          ),
          ...children,
        ],
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label, labelStyle: GoogleFonts.kanit(fontSize: fBody, color: Colors.grey.shade600, fontWeight: FontWeight.normal),
      prefixIcon: Icon(icon, color: cDark, size: 22),
      suffixIcon: suffix,
      filled: true, fillColor: cBg.withOpacity(0.3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: cAccent.withOpacity(0.5))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: cTextMain, width: 2)),
    );
  }
}