import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_page.dart';
import 'forgot_password_page.dart';
import 'pending_page.dart';
import 'register_page.dart';
import 'user/home_page.dart';
import 'admin/admin_page.dart';
import 'owner/platform_home_page.dart';

void main() => runApp(const MyAuthApp());

class MyAuthApp extends StatelessWidget {
  const MyAuthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ResHub',
      theme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.kanitTextTheme(),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashPage(),
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/forgot-password': (context) => const ForgotPasswordPage(),
        '/home': (context) => const HomePage(),
        '/admin': (context) => const AdminPage(),
        '/pending': (context) => const PendingPage(),
        '/platform': (context) => const PlatformHomePage(),
      },
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _goNext();
  }

  Future<void> _goNext() async {
    await Future.delayed(const Duration(seconds: 2));
    final prefs = await SharedPreferences.getInstance();

    final bool isLogin = prefs.getBool('isLogin') ?? false;
    final String platformRole = prefs.getString('platform_role') ?? 'user';
    final String roleInDorm = prefs.getString('role_in_dorm') ?? 'tenant';
    final String approveStatus = prefs.getString('approve_status') ?? 'pending';

    if (!mounted) return;

    if (!isLogin) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }

    // เช็คสถานะการอนุมัติ
    if (approveStatus != 'approved' && platformRole != 'platform_admin') {
      Navigator.pushReplacementNamed(context, '/pending');
      return;
    }

    // แยกหน้าตาม Role (เจ้าของหอ / ผู้เช่า / แอดมินระบบ)
    if (platformRole == 'platform_admin') {
      Navigator.pushReplacementNamed(context, '/platform');
    } else if (roleInDorm == 'owner' || roleInDorm == 'admin') {
      Navigator.pushReplacementNamed(context, '/admin');
    } else {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.apartment, size: 110, color: Color(0xFF603F26)),
            const SizedBox(height: 14),
            Text('ResHub', style: GoogleFonts.kanit(fontSize: 22, fontWeight: FontWeight.w700, color: const Color(0xFF603F26))),
            const SizedBox(height: 10),
            const CircularProgressIndicator(color: Color(0xFF6C4E31)),
          ],
        ),
      ),
    );
  }
}