import 'package:flutter/material.dart';
import '../profile_page.dart';
import 'admin_home_page.dart';
import 'bill/bill_admin_page.dart';
import 'room/admin_room_page.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int _currentIndex = 0;

  static const Color cCream = Color(0xFFF4EFE6);
  static const Color cDark = Color(0xFF523D2D);

  @override
  Widget build(BuildContext context) {
    final double bottomSafe = MediaQuery.of(context).padding.bottom;
    final double navBottom = bottomSafe > 0 ? bottomSafe + 10 : 16;

    return PopScope(
      canPop: false,
      child: Scaffold(
        extendBody: true,
        backgroundColor: cCream,
        body: Stack(
          children: [
            IndexedStack(
              index: _currentIndex,
              children: const [
                AdminHomePage(),
                AdminRoomPage(),
                BillAdminPage(),
                ProfilePage(),
              ],
            ),

            Positioned(
              left: 16,
              right: 16,
              bottom: navBottom,
              child: Container(
                height: 72,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(36),
                  boxShadow: [
                    BoxShadow(
                      color: cDark.withOpacity(0.10),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(child: _navItem(Icons.home_rounded, "หน้าแรก", 0)),
                    Expanded(child: _navItem(Icons.meeting_room_rounded, "ห้องพัก", 1)),
                    Expanded(child: _navItem(Icons.receipt_long_rounded, "บิลค่าเช่า", 2)),
                    Expanded(child: _navItem(Icons.person_rounded, "โปรไฟล์", 3)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final bool isSelected = _currentIndex == index;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _currentIndex = index),
      child: SizedBox(
        height: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? cCream.withOpacity(0.75) : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 23,
                color: isSelected ? cDark : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                color: isSelected ? cDark : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}