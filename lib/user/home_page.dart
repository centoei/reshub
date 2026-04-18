import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reshub/user/repair_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bill_page.dart';
import 'home_main_page.dart';
import '../profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cNavBg = Color(0xFFFFFFFF);
  static const Color cAccent = Color(0xFFD7CCC8);
  static const Color cTextMain = Color(0xFF523D2D);
  static const Color cIconUnselected = Color(0xFF7D6552);

  // 📏 Typography System
  static const double fHeader = 18.0; 
  static const double fTitle = 15.0;  
  static const double fBody = 13.0;   

  int _currentIndex = 0;
  bool _checking = true;

  late final List<Widget> _pages = [
    const HomeMainPage(),
    const BillPage(),
    const RepairPage(),
    const ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _loadAndGuard();
  }

  Future<void> _loadAndGuard() async {
    final prefs = await SharedPreferences.getInstance();
    final isLogin = prefs.getBool("isLogin") ?? false;
    if (!mounted) return;

    if (!isLogin) {
      Navigator.pushNamedAndRemoveUntil(context, "/", (_) => false);
      return;
    }
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: cBg,
        body: Center(child: CircularProgressIndicator(color: cTextMain)),
      );
    }

    return Scaffold(
      extendBody: true, 
      backgroundColor: cBg,
      body: Stack(
        children: [
          /// 1. ส่วนแสดงเนื้อหา
          IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),

          /// 2. แถบเมนูแบบลอย (Floating Navigation Bar) พร้อมชื่อ
          Positioned(
            left: 20,
            right: 20,
            bottom: 25, 
            child: SafeArea(
              top: false,
              child: Container(
                height: 75, 
                decoration: BoxDecoration(
                  color: cNavBg,
                  borderRadius: BorderRadius.circular(35),
                  boxShadow: [
                    BoxShadow(
                      color: cTextMain.withOpacity(0.12),
                      blurRadius: 25,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _navItem(Icons.home_rounded, "หน้าแรก", 0),
                    _navItem(Icons.receipt_long_rounded, "บิลค่าเช่า", 1),
                    _navItem(Icons.build_rounded, "แจ้งซ่อม", 2),
                    _navItem(Icons.person_rounded, "โปรไฟล์", 3),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final bool isSelected = _currentIndex == index;

    return GestureDetector(
      onTap: () {
        if (_currentIndex == index) return;
        setState(() => _currentIndex = index);
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 65, 
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? cAccent.withOpacity(0.7) : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 24, 
                color: isSelected ? cTextMain : cIconUnselected.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.kanit(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? cTextMain : cIconUnselected.withOpacity(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}