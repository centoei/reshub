import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config.dart';
import 'repair_model.dart';

class RepairDetailPage extends StatefulWidget {
  final RepairModel repair;
  final bool canEdit;

  const RepairDetailPage({
    super.key,
    required this.repair,
    this.canEdit = false,
  });

  @override
  State<RepairDetailPage> createState() => _RepairDetailPageState();
}

class _RepairDetailPageState extends State<RepairDetailPage> {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cTextMain = Color(0xFF2A1F17);
  static const Color cDark = Color(0xFF523D2D);

  // 📏 มาตราส่วน Font ตามที่กำหนด
  static const double fHeader = 18.0; // หัวข้อใหญ่
  static const double fTitle = 15.0;  // หัวข้อย่อย
  static const double fBody = 13.0;   // เนื้อหา
  static const double fCaption = 11.0;

  late String _selectedStatusTh;
  bool _saving = false;
  late String _imageUrl;
  int _dormId = 0;

  String _platformRole = 'user';
  String _roleInDorm = 'tenant';

  String _tenantName = '';
  late String _roomText;
  late String _phoneText;
  late String _detailText;
  late String _typeText;

  bool get _isAdminByRole {
    final p = _platformRole.toLowerCase().trim();
    final r = _roleInDorm.toLowerCase().trim();
    return p == 'platform_admin' ||
        p == 'admin' ||
        r == 'admin' ||
        r == 'owner' ||
        r == 'o' ||
        r == 'a';
  }

  bool get _canManage => widget.canEdit || _isAdminByRole;

  @override
  void initState() {
    super.initState();
    _selectedStatusTh = _normalizeToThai(widget.repair.status);
    _imageUrl = _toImageUrl(widget.repair.image);
    _roomText = widget.repair.room;
    _phoneText = widget.repair.phone;
    _detailText = widget.repair.detail;
    _typeText = widget.repair.type.isEmpty ? 'อื่น ๆ' : widget.repair.type;
    _loadIds();
  }

  Future<void> _loadIds() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _dormId =
          prefs.getInt('dorm_id') ??
          int.tryParse(prefs.getString('dorm_id') ?? '0') ??
          0;
      _platformRole = (prefs.getString('platform_role') ??
              prefs.getString('user_role') ??
              'user')
          .toLowerCase();
      _roleInDorm = (prefs.getString('role_in_dorm') ??
              prefs.getString('dorm_role') ??
              prefs.getString('member_role') ??
              'tenant')
          .toLowerCase();
    });
    await _loadRepairDetail();
  }

  Future<void> _loadRepairDetail() async {
    if (widget.repair.repairId <= 0 || _dormId <= 0) return;
    try {
      final res = await http
          .post(
            Uri.parse(AppConfig.url('repairs_api.php')),
            body: {
              'action': 'getRepairById',
              'repair_id': widget.repair.repairId.toString(),
              'dorm_id': _dormId.toString(),
            },
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (!mounted) return;

      if (data is Map && (data['success'] == true || data['ok'] == true)) {
        final m = Map<String, dynamic>.from(data['data'] ?? {});
        setState(() {
          _tenantName = (m['full_name'] ?? '').toString().trim();
          _roomText = "${m['building_name'] ?? ''} ${m['room_number'] ?? ''}"
              .trim();
          if (_roomText.isEmpty) _roomText = (m['room_number'] ?? '-').toString();

          _phoneText = (m['phone'] ?? '').toString().trim();
          _detailText = (m['detail'] ?? '').toString().trim();

          _typeText = (m['repair_type'] ?? '').toString().trim();
          if (_typeText.isEmpty) _typeText = 'อื่น ๆ';

          final img = (m['image_path'] ?? '').toString().trim();
          if (img.isNotEmpty) _imageUrl = _toImageUrl(img);

          final statusRaw = (m['status_th'] ?? m['status'] ?? '').toString();
          _selectedStatusTh = _normalizeToThai(statusRaw);
        });
      }
    } catch (_) {}
  }

  String _normalizeToThai(String s) {
    final t = s.trim().toLowerCase();
    if (t.contains('pending') || t == 'รอดำเนินการ') return 'รอดำเนินการ';
    if (t.contains('working') || t == 'กำลังดำเนินการ') {
      return 'กำลังดำเนินการ';
    }
    if (t.contains('done') || t == 'เสร็จสิ้น') return 'เสร็จสิ้น';
    return 'รอดำเนินการ';
  }

  String _thaiToDbKey(String th) {
    switch (th) {
      case 'กำลังดำเนินการ':
        return 'working';
      case 'เสร็จสิ้น':
        return 'done';
      default:
        return 'pending';
    }
  }

  Color _getTypeColor(String type) {
    if (type.contains('ไฟฟ้า')) return const Color(0xFFFBC02D);
    if (type.contains('น้ำ') || type.contains('ประปา')) {
      return const Color(0xFF0288D1);
    }
    if (type.contains('แอร์')) return const Color(0xFF009688);
    if (type.contains('เฟอร์นิเจอร์')) return const Color(0xFF795548);
    return const Color(0xFF455A64);
  }

  IconData _typeIcon(String type) {
    if (type.contains('ไฟฟ้า')) return Icons.bolt_rounded;
    if (type.contains('น้ำ') || type.contains('ประปา')) {
      return Icons.water_drop_rounded;
    }
    if (type.contains('แอร์')) return Icons.ac_unit_rounded;
    if (type.contains('เฟอร์นิเจอร์')) return Icons.chair_rounded;
    return Icons.construction_rounded;
  }

  String _toImageUrl(String raw) {
    if (raw.isEmpty) return '';
    return raw.startsWith('http') ? raw : AppConfig.url(raw);
  }

  Future<void> _saveStatusToDb() async {
    if (_saving || !_canManage) return;
    setState(() => _saving = true);
    try {
      final key = _thaiToDbKey(_selectedStatusTh);
      final res = await http
          .post(
            Uri.parse(AppConfig.url('repairs_api.php')),
            body: {
              'action': 'update_status',
              'repair_id': widget.repair.repairId.toString(),
              'status': key,
              'dorm_id': _dormId.toString(),
            },
          )
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if ((data['success'] == true || data['ok'] == true) && mounted) {
        Navigator.pop(context, _selectedStatusTh);
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 55,
        title: Text(
          'รายละเอียดงานซ่อม',
          style: GoogleFonts.kanit(
            fontWeight: FontWeight.w600,
            fontSize: fHeader,
          ),
        ),
        centerTitle: true,
        elevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: cTextMain,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _buildStatusTimeline(_selectedStatusTh),
            ),
            _buildImageHeader(_typeText),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildContactAndLocationCard(),
                  const SizedBox(height: 16),
                  _buildIssueCard(),
                  const SizedBox(height: 24),
                  if (_canManage) _buildAdminControl(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTimeline(String statusTh) {
    final currentStep = (statusTh == 'รอดำเนินการ')
        ? 0
        : (statusTh == 'กำลังดำเนินการ')
            ? 1
            : 2;
    const labels = ['รอดำเนินการ', 'กำลังซ่อม', 'เสร็จสิ้น'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'สถานะปัจจุบัน',
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w600,
              color: cTextMain,
              fontSize: fTitle,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(3, (i) {
              final isDone = i <= currentStep;
              final color = isDone
                  ? (currentStep == 2
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFEF6C00))
                  : Colors.grey.shade300;
              return Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 3,
                            color: i == 0
                                ? Colors.transparent
                                : (i <= currentStep
                                    ? color
                                    : Colors.grey.shade300),
                          ),
                        ),
                        Icon(
                          isDone
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked,
                          color: color,
                          size: 24,
                        ),
                        Expanded(
                          child: Container(
                            height: 3,
                            color: i == 2
                                ? Colors.transparent
                                : (i < currentStep
                                    ? color
                                    : Colors.grey.shade300),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      labels[i],
                      style: GoogleFonts.kanit(
                        fontSize: fCaption,
                        fontWeight:
                            isDone ? FontWeight.w600 : FontWeight.normal,
                        color: isDone ? cTextMain : Colors.grey,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildImageHeader(String type) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _imageUrl.isNotEmpty
                    ? Image.network(
                        _imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (c, e, s) => Center(
                          child: Icon(
                            _typeIcon(type),
                            size: 50,
                            color: cAccent,
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          size: 50,
                          color: cAccent,
                        ),
                      ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: _buildTypePill(type, _getTypeColor(type)),
          ),
        ],
      ),
    );
  }

  Widget _buildTypePill(String text, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_typeIcon(text), color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.kanit(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: fCaption,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactAndLocationCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cAccent.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        children: [
          if (_tenantName.isNotEmpty) ...[
            Row(
              children: [
                const Icon(
                  Icons.person_pin_rounded,
                  color: Color(0xFFD84315),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ชื่อผู้เช่า',
                        style: GoogleFonts.kanit(
                          fontSize: fCaption,
                          color: Colors.black54,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      Text(
                        _tenantName,
                        style: GoogleFonts.kanit(
                          fontSize: fTitle,
                          fontWeight: FontWeight.w600,
                          color: cTextMain,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: cBg, thickness: 1.5),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.door_sliding_rounded,
                      color: Color(0xFF1565C0),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'เลขห้อง',
                          style: GoogleFonts.kanit(
                            fontSize: fCaption,
                            color: Colors.black54,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        Text(
                          _roomText.isEmpty ? '-' : _roomText,
                          style: GoogleFonts.kanit(
                            fontSize: fTitle,
                            fontWeight: FontWeight.w600,
                            color: cTextMain,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 35, color: cAccent.withOpacity(0.5)),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.phone_in_talk_rounded,
                      color: Color(0xFF2E7D32),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ติดต่อ',
                          style: GoogleFonts.kanit(
                            fontSize: fCaption,
                            color: Colors.black54,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        Text(
                          _phoneText.isEmpty ? '-' : _phoneText,
                          style: GoogleFonts.kanit(
                            fontSize: fTitle,
                            fontWeight: FontWeight.w600,
                            color: cTextMain,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIssueCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'รายละเอียดปัญหา',
            style: GoogleFonts.kanit(
              fontSize: fCaption,
              color: Colors.black54,
              fontWeight: FontWeight.normal,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _detailText.isEmpty ? 'ไม่มีรายละเอียดเพิ่มเติม' : _detailText,
            style: GoogleFonts.kanit(
              fontSize: fBody,
              color: cTextMain,
              fontWeight: FontWeight.normal,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminControl() {
    final statusList = ['รอดำเนินการ', 'กำลังดำเนินการ', 'เสร็จสิ้น'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cAccent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'จัดการสถานะงานซ่อม',
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w600,
              fontSize: fTitle,
              color: cTextMain,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedStatusTh,
            selectedItemBuilder: (BuildContext context) {
              return statusList.map<Widget>((String item) {
                return Text(
                  item,
                  style: GoogleFonts.kanit(
                    color: cTextMain,
                    fontWeight: FontWeight.normal,
                    fontSize: fBody,
                  ),
                  overflow: TextOverflow.ellipsis,
                );
              }).toList();
            },
            items: statusList
                .map(
                  (s) => DropdownMenuItem<String>(
                    value: s,
                    child: Text(
                      s,
                      style: GoogleFonts.kanit(
                        fontWeight: FontWeight.normal,
                        color: cTextMain,
                        fontSize: fBody,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => _selectedStatusTh = v);
              }
            },
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: cBg.withOpacity(0.4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            style: GoogleFonts.kanit(
              color: cTextMain,
              fontWeight: FontWeight.normal,
              fontSize: fBody,
            ),
            dropdownColor: Colors.white,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: cTextMain,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveStatusToDb,
              style: ElevatedButton.styleFrom(
                backgroundColor: cDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : Text(
                      'บันทึกการเปลี่ยนแปลง',
                      style: GoogleFonts.kanit(
                        fontWeight: FontWeight.w600,
                        fontSize: fHeader,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}