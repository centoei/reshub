class RepairModel {
  final int repairId;
  final String type;      // ชื่อประเภทภาษาไทย (เช่น ไฟฟ้า, ประปา)
  final String room;      // ชื่อตึก - เลขห้อง
  final String status;    // pending, working, done
  final String statusTh;  // รอดำเนินการ, กำลังดำเนินการ, เสร็จสิ้น
  final String detail;
  final String image;
  final String createdAt;
  final String fullName;  // ชื่อผู้แจ้ง (สำหรับ Admin)
  final String phone;     // เบอร์โทร (สำหรับ Admin)

  RepairModel({
    required this.repairId,
    required this.type,
    required this.room,
    required this.status,
    required this.statusTh,
    required this.detail,
    required this.image,
    required this.createdAt,
    this.fullName = '',
    this.phone = '',
  });

  factory RepairModel.fromJson(Map<String, dynamic> json) {
    return RepairModel(
      repairId: int.tryParse(json['repair_id']?.toString() ?? '0') ?? 0,
      type: json['repair_type']?.toString() ?? 'ทั่วไป',
      room: "${json['building_name'] ?? ''} ${json['room_number'] ?? ''}".trim(),
      status: json['status']?.toString() ?? 'pending',
      statusTh: json['status_th']?.toString() ?? 'รอดำเนินการ',
      detail: json['detail']?.toString() ?? '',
      image: json['image_path']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
    );
  }
}