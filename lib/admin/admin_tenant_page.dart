import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

class TenantRow {
  final int tenantId;
  final int roomId;
  final String roomNumber;
  final int userId;
  final String fullName;

  TenantRow({
    required this.tenantId,
    required this.roomId,
    required this.roomNumber,
    required this.userId,
    required this.fullName,
  });

  factory TenantRow.fromJson(Map<String, dynamic> json) {
    return TenantRow(
      tenantId: int.tryParse(json["tenant_id"].toString()) ?? 0,
      roomId: int.tryParse(json["room_id"].toString()) ?? 0,
      roomNumber: (json["room_number"] ?? "").toString(),
      userId: int.tryParse(json["user_id"].toString()) ?? 0,
      fullName: (json["full_name"] ?? "").toString(),
    );
  }
}

class AdminTenantPage extends StatefulWidget {
  const AdminTenantPage({super.key});

  @override
  State<AdminTenantPage> createState() => _AdminTenantPageState();
}

class _AdminTenantPageState extends State<AdminTenantPage> {
  bool loading = true;
  List<TenantRow> tenants = [];

  @override
  void initState() {
    super.initState();
    fetchTenants();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Map<String, dynamic> _mustJson(http.Response res) {
    if (res.statusCode != 200) {
      throw Exception("HTTP ${res.statusCode}\n${res.body}");
    }

    final ct = (res.headers['content-type'] ?? '').toLowerCase();
    final body = res.body.trim();

    if (!ct.contains('application/json') &&
        !(body.startsWith('{') || body.startsWith('['))) {
      throw Exception("API ไม่ได้ส่ง JSON กลับมา\ncontent-type: $ct\n${res.body}");
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception("JSON shape ไม่ถูกต้อง");
    }
    return decoded;
  }

  Future<void> fetchTenants() async {
    if (!mounted) return;
    setState(() => loading = true);

    try {
      final url = Uri.parse(AppConfig.url("tenants_api.php"));

      final res = await http
          .post(url, body: {"action": "list"})
          .timeout(const Duration(seconds: 12));

      final data = _mustJson(res);

      if (!mounted) return;

      if (data["success"] == true || data["ok"] == true) {
        final List list = (data["data"] as List?) ?? [];
        final fetched = list
            .map((e) => TenantRow.fromJson(Map<String, dynamic>.from(e)))
            .toList();

        setState(() => tenants = fetched);
      } else {
        _snack(data["message"]?.toString() ?? "โหลดผู้เช่าไม่สำเร็จ");
      }
    } catch (e) {
      if (!mounted) return;
      _snack("เชื่อมต่อไม่ได้: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE6),
      appBar: AppBar(
        title: const Text(
          "จัดการผู้เช่า",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(onPressed: fetchTenants, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : tenants.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline,
                          size: 72, color: Colors.grey[300]),
                      const SizedBox(height: 12),
                      const Text("ยังไม่มีข้อมูลผู้เช่า",
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: fetchTenants,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: tenants.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _tenantCard(tenants[i]),
                  ),
                ),
    );
  }

  Widget _tenantCard(TenantRow t) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        _snack("ห้อง ${t.roomNumber} • ${t.fullName}");
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFDCD2C1).withOpacity(0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.door_front_door_rounded,
                  color: Color(0xFF523D2D)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "ห้อง ${t.roomNumber}",
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.fullName.isEmpty ? "ไม่มีชื่อผู้เช่า" : t.fullName,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}