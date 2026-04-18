// import 'package:flutter/material.dart';

// class DormitoryFormPage extends StatefulWidget {
//   @override
//   _DormitoryFormPageState createState() => _DormitoryFormPageState();
// }

// class _DormitoryFormPageState extends State<DormitoryFormPage> {
//   final _formKey = GlobalKey<FormState>();
  
//   // Controller สำหรับรับค่าจากช่องกรอก
//   final TextEditingController _nameController = TextEditingController();
//   final TextEditingController _addressController = TextEditingController();
//   final TextEditingController _phoneController = TextEditingController();
//   final TextEditingController _roomCountController = TextEditingController();
//   final TextEditingController _priceController = TextEditingController();

//   void _submitData() {
//     if (_formKey.currentState!.validate()) {
//       // ตรงนี้คือจุดที่นำข้อมูลไปต่อยอดส่งเข้า PHP API
//       print("ชื่อหอพัก: ${_nameController.text}");
//       print("ที่อยู่: ${_addressController.text}");
      
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('บันทึกข้อมูลเรียบร้อยแล้ว')),
//       );
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('ลงทะเบียนหอพัก'),
//         backgroundColor: Colors.blueAccent,
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Form(
//           key: _formKey,
//           child: ListView(
//             children: [
//               _buildTextField(
//                 controller: _nameController,
//                 label: 'ชื่อหอพัก',
//                 icon: Icons.apartment,
//                 validator: (value) => value!.isEmpty ? 'กรุณากรอกชื่อหอพัก' : null,
//               ),
//               SizedBox(height: 15),
//               _buildTextField(
//                 controller: _addressController,
//                 label: 'ที่อยู่',
//                 icon: Icons.location_on,
//                 maxLines: 3,
//                 validator: (value) => value!.isEmpty ? 'กรุณากรอกที่อยู่' : null,
//               ),
//               SizedBox(height: 15),
//               _buildTextField(
//                 controller: _phoneController,
//                 label: 'เบอร์โทรศัพท์ติดต่อ',
//                 icon: Icons.phone,
//                 keyboardType: TextInputType.phone,
//                 validator: (value) => value!.length < 9 ? 'กรุณากรอกเบอร์โทรให้ถูกต้อง' : null,
//               ),
//               SizedBox(height: 15),
//               Row(
//                 children: [
//                   Expanded(
//                     child: _buildTextField(
//                       controller: _roomCountController,
//                       label: 'จำนวนห้องทั้งหมด',
//                       icon: Icons.meeting_room,
//                       keyboardType: TextInputType.number,
//                     ),
//                   ),
//                   SizedBox(width: 10),
//                   Expanded(
//                     child: _buildTextField(
//                       controller: _priceController,
//                       label: 'ราคาเริ่มต้น (บาท)',
//                       icon: Icons.payments,
//                       keyboardType: TextInputType.number,
//                     ),
//                   ),
//                 ],
//               ),
//               SizedBox(height: 30),
//               ElevatedButton(
//                 onPressed: _submitData,
//                 style: ElevatedButton.styleFrom(
//                   padding: EdgeInsets.symmetric(vertical: 15),
//                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//                   backgroundColor: Colors.blueAccent,
//                 ),
//                 child: Text('บันทึกข้อมูล', style: TextStyle(fontSize: 18, color: Colors.white)),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   // Widget ตัวช่วยสร้างช่องกรอกข้อมูล (เพื่อความสะอาดของโค้ด)
//   Widget _buildTextField({
//     required TextEditingController controller,
//     required String label,
//     required IconData icon,
//     TextInputType keyboardType = TextInputType.text,
//     int maxLines = 1,
//     String? Function(String?)? validator,
//   }) {
//     return TextFormField(
//       controller: controller,
//       keyboardType: keyboardType,
//       maxLines: maxLines,
//       decoration: InputDecoration(
//         labelText: label,
//         prefixIcon: Icon(icon),
//         border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
//         filled: true,
//         fillColor: Colors.grey[100],
//       ),
//       validator: validator,
//     );
//   }
// }