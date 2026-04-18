// import 'dart:convert';
// import 'dart:io';

// import 'package:flutter/material.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:http/http.dart' as http;

// import '../config.dart';

// class RepairPage extends StatefulWidget {
//   const RepairPage({super.key});

//   @override
//   State<RepairPage> createState() => _RepairPageState();
// }

// class _RepairPageState extends State<RepairPage> {
//   // 🎨 Palette สีพรีเมียม
//   static const Color cBg = Color(0xFFFFEAC5);       // พื้นหลังครีมสว่าง
//   static const Color cCard = Color(0xFFFFFFFF);     // กล่องขาว
//   static const Color cAccent = Color(0xFFFFDBB5);   // พีชอ่อน
//   static const Color cTextMain = Color(0xFF603F26); // น้ำตาลเข้ม
//   static const Color cIcon = Color(0xFF6C4E31);     // น้ำตาลกลาง

//   Uri get _repairApi => Uri.parse(AppConfig.url("repair.php"));

//   final _formKey = GlobalKey<FormState>();
//   final ImagePicker _picker = ImagePicker();

//   final ScrollController _scrollCtrl = ScrollController();
//   int _formVersion = 0;

//   File? _image;
//   String? repairType;

//   final TextEditingController titleCtrl = TextEditingController();
//   final TextEditingController detailCtrl = TextEditingController();
//   final TextEditingController roomCtrl = TextEditingController();
//   final TextEditingController phoneCtrl = TextEditingController();

//   bool _loadingUser = true;
//   bool _submitting = false;

//   int _userId = 0;
//   int _tenantId = 0;
//   int _roomId = 0;
//   int _dormId = 0;

//   String _roomNumber = "";

//   final Map<String, IconData> categories = {
//     "ไฟฟ้า": Icons.bolt_rounded,
//     "ประปา": Icons.water_drop_rounded,
//     "เครื่องใช้": Icons.kitchen_rounded,
//     "อื่น ๆ": Icons.construction_rounded,
//   };

//   Map<String, IconData> dynamicCategories = {};

//   @override
//   void initState() {
//     super.initState();
//     _loadUserAndTenant();
//   }

//   @override
//   void dispose() {
//     _scrollCtrl.dispose();
//     titleCtrl.dispose();
//     detailCtrl.dispose();
//     roomCtrl.dispose();
//     phoneCtrl.dispose();
//     super.dispose();
//   }

//   bool _isSuccess(dynamic v) {
//     if (v == true) return true;
//     if (v is num) return v == 1;
//     final s = v.toString().trim().toLowerCase();
//     return s == "1" || s == "true" || s == "success";
//   }

//   void _resetForm() {
//     if (!mounted) return;
//     FocusScope.of(context).unfocus();
//     _formKey.currentState?.reset();
//     titleCtrl.value = TextEditingValue.empty;
//     detailCtrl.value = TextEditingValue.empty;
//     setState(() {
//       repairType = null;
//       _image = null;
//       _formVersion++;
//     });
//   }

//   void _toast(String msg) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(msg, style: const TextStyle(color: Color(0xFFFFEAC5))),
//         backgroundColor: cTextMain,
//         behavior: SnackBarBehavior.floating,
//       ),
//     );
//   }

//   Map<String, dynamic>? _tryDecodeJson(http.Response res) {
//     try {
//       final decoded = jsonDecode(res.body);
//       if (decoded is Map<String, dynamic>) return decoded;
//       if (decoded is Map) return Map<String, dynamic>.from(decoded);
//       return null;
//     } catch (_) { return null; }
//   }

//   String _shortBody(String s) {
//     final t = s.trim();
//     if (t.length <= 400) return t;
//     return "${t.substring(0, 400)} ...";
//   }

//   Future<void> _loadRepairTypes() async {
//     if (_dormId == 0) return;
//     try {
//       final res = await http.post(_repairApi, body: {
//         "action": "getRepairTypes",
//         "dorm_id": _dormId.toString(),
//       }).timeout(const Duration(seconds: 10));
//       final data = _tryDecodeJson(res);
//       if (data == null || !_isSuccess(data["success"])) return;
//       final List types = (data["data"] ?? []) as List;
//       final Map<String, IconData> m = {};
//       for (final t in types) {
//         final name = t.toString().trim();
//         if (name.isEmpty) continue;
//         if (!categories.containsKey(name)) m[name] = Icons.construction_rounded;
//       }
//       if (!mounted) return;
//       setState(() => dynamicCategories = m);
//     } catch (_) {}
//   }

//   Future<void> _loadUserAndTenant() async {
//     if (!mounted) return;
//     setState(() => _loadingUser = true);
//     final prefs = await SharedPreferences.getInstance();
//     _userId = prefs.getInt("user_id") ?? 0;
//     _dormId = prefs.getInt("dorm_id") ?? prefs.getInt("selected_dorm_id") ?? 0;
//     final phonePref = (prefs.getString("phone") ?? "").trim();
//     phoneCtrl.text = phonePref.isEmpty ? "ไม่มีข้อมูล" : phonePref;

//     if (_userId == 0) {
//       setState(() => _loadingUser = false);
//       _toast("ไม่พบ user_id กรุณาเข้าสู่ระบบใหม่");
//       return;
//     }
//     if (_dormId == 0) {
//       setState(() => _loadingUser = false);
//       _toast("ไม่พบ dorm_id");
//       roomCtrl.text = "ยังไม่ได้ผูกห้อง";
//       return;
//     }
//     try {
//       final res = await http.post(_repairApi, body: {
//         "action": "getTenant", "user_id": _userId.toString(), "dorm_id": _dormId.toString(),
//       }).timeout(const Duration(seconds: 10));
//       final data = _tryDecodeJson(res);
//       if (data != null && res.statusCode == 200 && _isSuccess(data["success"])) {
//         final m = Map<String, dynamic>.from(data["data"] ?? {});
//         _tenantId = int.tryParse("${m["tenant_id"]}") ?? 0;
//         _roomId = int.tryParse("${m["room_id"]}") ?? 0;
//         _roomNumber = (m["room_number"] ?? "").toString().trim();
//         roomCtrl.text = _roomNumber.isEmpty ? "ยังไม่ได้ผูกห้อง" : _roomNumber;
//         await _loadRepairTypes();
//       }
//     } finally { if (mounted) setState(() => _loadingUser = false); }
//   }

//   Future<void> _pickImage(ImageSource source) async {
//     final XFile? picked = await _picker.pickImage(source: source, imageQuality: 70);
//     if (picked != null) setState(() => _image = File(picked.path));
//   }

//   void _showImageSourceSheet() {
//     showModalBottomSheet(
//       context: context, backgroundColor: cBg,
//       shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
//       builder: (_) => SafeArea(
//         child: Wrap(
//           children: [
//             ListTile(leading: const Icon(Icons.camera_alt, color: cTextMain), title: const Text("ถ่ายรูป"), onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); }),
//             ListTile(leading: const Icon(Icons.photo_library, color: cTextMain), title: const Text("เลือกจากแกลเลอรี"), onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); }),
//           ],
//         ),
//       ),
//     );
//   }

//   Future<void> _handleSubmit() async {
//     if (_submitting) return;
//     if (!_formKey.currentState!.validate() || repairType == null) {
//       if (repairType == null) _toast("กรุณาเลือกประเภทงานซ่อม");
//       return;
//     }
//     setState(() => _submitting = true);
//     try {
//       final req = http.MultipartRequest("POST", _repairApi);
//       req.fields.addAll({"action": "create", "user_id": _userId.toString(), "dorm_id": _dormId.toString(), "type": repairType!, "title": titleCtrl.text.trim(), "detail": detailCtrl.text.trim()});
//       if (_image != null) req.files.add(await http.MultipartFile.fromPath("image", _image!.path));
//       final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 20)));
//       final data = _tryDecodeJson(res);
//       if (data != null && _isSuccess(data["success"])) {
//         _resetForm();
//         _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
//         _toast("ส่งแจ้งซ่อมเรียบร้อย ✅");
//       }
//     } finally { if (mounted) setState(() => _submitting = false); }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final allCategories = {...categories, ...dynamicCategories};
//     return Scaffold(
//       backgroundColor: cBg,
//       appBar: AppBar(
//         title: const Text("แจ้งซ่อม", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFEAC5))),
//         centerTitle: true, backgroundColor: cTextMain, elevation: 0, iconTheme: const IconThemeData(color: Color(0xFFFFEAC5)),
//         actions: [IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RepairHistoryPage())), icon: const Icon(Icons.history_rounded))],
//       ),
//       body: _loadingUser ? const Center(child: CircularProgressIndicator(color: cTextMain)) : SingleChildScrollView(
//         controller: _scrollCtrl, padding: const EdgeInsets.fromLTRB(16, 20, 16, 30),
//         child: KeyedSubtree(
//           key: ValueKey(_formVersion),
//           child: Form(
//             key: _formKey,
//             child: Container( // ✅ เพิ่มกรอบพื้นหลัง (Background Card)
//               padding: const EdgeInsets.all(20),
//               decoration: BoxDecoration(color: cCard, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))]),
//               child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//                 Container(
//                   padding: const EdgeInsets.all(20),
//                   decoration: BoxDecoration(gradient: const LinearGradient(colors: [cTextMain, cIcon]), borderRadius: BorderRadius.circular(24)),
//                   child: Row(children: [
//                     const CircleAvatar(backgroundColor: Colors.white24, radius: 25, child: Icon(Icons.apartment_rounded, color: Colors.white, size: 30)),
//                     const SizedBox(width: 15),
//                     Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//                       const Text("หมายเลขห้อง", style: TextStyle(color: Colors.white70, fontSize: 14)),
//                       Text(roomCtrl.text, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
//                     ]),
//                   ]),
//                 ),
//                 const SizedBox(height: 32),
//                 const Text("ประเภทงานซ่อม", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cTextMain)),
//                 const SizedBox(height: 12),
//                 SizedBox(
//                   height: 95,
//                   child: ListView(scrollDirection: Axis.horizontal, children: allCategories.entries.map((entry) {
//                     final isSelected = repairType == entry.key;
//                     return GestureDetector(
//                       onTap: () => setState(() => repairType = entry.key),
//                       child: AnimatedContainer(
//                         duration: const Duration(milliseconds: 200), width: 85, margin: const EdgeInsets.only(right: 12),
//                         decoration: BoxDecoration(color: isSelected ? cTextMain : Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(20), border: Border.all(color: isSelected ? cTextMain : cAccent, width: 2)),
//                         child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
//                           Icon(entry.value, color: isSelected ? Colors.white : cIcon),
//                           const SizedBox(height: 8),
//                           Text(entry.key, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : cIcon)),
//                         ]),
//                       ),
//                     );
//                   }).toList()),
//                 ),
//                 const SizedBox(height: 32),
//                 const Text("ข้อมูลการแจ้งซ่อม", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cTextMain)),
//                 const SizedBox(height: 16),
//                 _buildField(titleCtrl, "หัวข้อ", Icons.title_rounded),
//                 const SizedBox(height: 16),
//                 _buildField(detailCtrl, "รายละเอียดเพิ่มเติม", Icons.description_rounded, maxLines: 3),
//                 const SizedBox(height: 32),
//                 const Text("รูปภาพประกอบ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cTextMain)),
//                 const SizedBox(height: 12),
//                 _buildImageSection(),
//                 const SizedBox(height: 40),
//                 SizedBox(width: double.infinity, height: 56, child: ElevatedButton(onPressed: _submitting ? null : _handleSubmit, style: ElevatedButton.styleFrom(backgroundColor: cTextMain, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 5), child: _submitting ? const CircularProgressIndicator(color: Colors.white) : const Text("ยืนยันส่งข้อมูล", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)))),
//               ]),
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildField(TextEditingController c, String l, IconData i, {int maxLines = 1}) {
//     return TextFormField(
//       controller: c, maxLines: maxLines, validator: (v) => (v == null || v.isEmpty) ? "กรุณากรอก$l" : null,
//       decoration: InputDecoration(
//         labelText: l, prefixIcon: Icon(i, color: cIcon), filled: true, fillColor: Color(0xFFF8F9FA),
//         enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: cAccent)),
//         focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: cTextMain, width: 2)),
//       ),
//     );
//   }

//   Widget _buildImageSection() {
//     return GestureDetector(
//       onTap: _showImageSourceSheet,
//       child: Container(
//         height: 150, width: double.infinity,
//         decoration: BoxDecoration(color: Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(20), border: Border.all(color: cAccent, width: 2)),
//         child: _image == null ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.add_a_photo_rounded, size: 40, color: cAccent), const Text("แตะเพื่อเพิ่มรูปภาพ", style: TextStyle(color: cIcon))]) : ClipRRect(borderRadius: BorderRadius.circular(18), child: Stack(fit: StackFit.expand, children: [Image.file(_image!, fit: BoxFit.cover), Positioned(top: 10, right: 10, child: GestureDetector(onTap: () => setState(() => _image = null), child: const CircleAvatar(backgroundColor: Colors.red, radius: 14, child: Icon(Icons.close, color: Colors.white, size: 18))))])),
//       ),
//     );
//   }
// }

// class RepairHistoryPage extends StatefulWidget {
//   const RepairHistoryPage({super.key});
//   @override
//   State<RepairHistoryPage> createState() => _RepairHistoryPageState();
// }

// class _RepairHistoryPageState extends State<RepairHistoryPage> {
//   static const Color cBg = Color(0xFFFFEAC5), cCard = Color(0xFFFFFFFF), cTextMain = Color(0xFF603F26), cIcon = Color(0xFF6C4E31);
//   Uri get _repairApi => Uri.parse(AppConfig.url("repair.php"));
//   bool loading = true;
//   List<Map<String, dynamic>> items = [];

//   @override
//   void initState() { super.initState(); _load(); }

//   Future<void> _load() async {
//     final prefs = await SharedPreferences.getInstance();
//     try {
//       final res = await http.post(_repairApi, body: {"action": "listMyRepairs", "user_id": prefs.getInt("user_id").toString(), "dorm_id": prefs.getInt("dorm_id").toString()});
//       final data = jsonDecode(res.body);
//       if (data["success"] == true) setState(() => items = List<Map<String, dynamic>>.from(data["data"]));
//     } finally { if (mounted) setState(() => loading = false); }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: cBg,
//       appBar: AppBar(backgroundColor: cTextMain, centerTitle: true, title: const Text("ประวัติการแจ้งซ่อม", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFEAC5)))),
//       body: loading ? const Center(child: CircularProgressIndicator(color: cTextMain)) : ListView.separated(
//         padding: const EdgeInsets.all(16), itemCount: items.length,
//         separatorBuilder: (_, __) => const SizedBox(height: 12),
//         itemBuilder: (context, i) => _buildRepairCard(items[i], i),
//       ),
//     );
//   }

//   Widget _buildRepairCard(Map<String, dynamic> item, int index) {
//     final status = item["status"]?.toString() ?? "pending";
//     String? img; try { img = jsonDecode(item["images"].toString()).first; } catch (_) {}
//     return Container(
//       decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
//       child: Row(children: [
//         // ✅ แถบสีข้างหนา 8px
//         Container(width: 8, height: 110, decoration: BoxDecoration(color: status == "done" ? Colors.green : status == "working" ? Colors.blue : Colors.orange, borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)))),
//         const SizedBox(width: 12),
//         // ✅ รูปภาพ thumbnail
//         ClipRRect(borderRadius: BorderRadius.circular(12), child: Container(width: 70, height: 70, color: cBg, child: img != null ? Image.network(AppConfig.url(img), fit: BoxFit.cover) : const Icon(Icons.image))),
//         const SizedBox(width: 12),
//         Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//           Text(item["title"] ?? "-", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: cTextMain)),
//           Text(item["repair_type"] ?? "-", style: const TextStyle(color: cIcon, fontSize: 13, fontWeight: FontWeight.bold)),
//           Text(item["created_at"] ?? "-", style: const TextStyle(color: Colors.grey, fontSize: 11)),
//         ])),
//         IconButton(onPressed: () async {
//           final res = await http.post(_repairApi, body: {"action": "deleteMyRepair", "repair_id": (item["repair_id"] ?? item["id"]).toString()});
//           if (jsonDecode(res.body)["success"] == true) setState(() => items.removeAt(index));
//         }, icon: const Icon(Icons.delete_outline, color: Colors.redAccent))
//       ]),
//     );
//   }
// }