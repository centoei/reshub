enum RoomStatus { available, occupied, maintenance }

enum RoomType { air, fan }

extension RoomTypeX on RoomType {
  String get dbValue => this == RoomType.air ? "air" : "fan";
  String get label => this == RoomType.air ? "แอร์" : "พัดลม";
}

extension RoomStatusX on RoomStatus {
  String get dbValue {
    switch (this) {
      case RoomStatus.available:
        return "vacant";
      case RoomStatus.occupied:
        return "occupied";
      case RoomStatus.maintenance:
        return "maintenance";
    }
  }

  String get label {
    switch (this) {
      case RoomStatus.available:
        return "ว่าง";
      case RoomStatus.occupied:
        return "ไม่ว่าง";
      case RoomStatus.maintenance:
        return "ซ่อมแซม";
    }
  }
}

class Room {
  final int roomId;
  final int dormId;
  final String roomNo;
  final String building;
  final int floor;
  final RoomType type;
  final RoomStatus status;
  final int rent;
  final TenantInfo? tenant;

  Room({
    required this.roomId,
    required this.dormId,
    required this.roomNo,
    required this.building,
    required this.floor,
    required this.type,
    required this.status,
    required this.rent,
    this.tenant,
  });

  static int _toInt(dynamic v, {int def = 0}) {
    if (v == null) return def;
    if (v is int) return v;
    if (v is double) return v.round();
    final s = v.toString().trim();
    if (s.isEmpty) return def;
    final d = double.tryParse(s);
    return d != null ? d.round() : def;
  }

  static RoomType _toType(dynamic v) {
    final s = (v ?? "").toString().trim().toLowerCase();
    if (s.contains("air") || s.contains("ac") || s.contains("แอร์")) {
      return RoomType.air;
    }
    return RoomType.fan;
  }

  static RoomStatus _toStatus(dynamic v) {
    final s = (v ?? "").toString().trim().toLowerCase();
    if (s == "vacant" || s == "available" || s == "ว่าง") {
      return RoomStatus.available;
    }
    if (s == "maintenance" || s == "repair" || s == "ซ่อมแซม") {
      return RoomStatus.maintenance;
    }
    return RoomStatus.occupied;
  }

  factory Room.fromJson(Map<String, dynamic> j) {
    final roomId = _toInt(j["room_id"] ?? j["id"]);
    final dormId = _toInt(j["dorm_id"]);
    final roomNo = (j["room_number"] ?? j["room_no"] ?? j["room"] ?? "").toString();
    final building = (j["building"] ?? j["building_name"] ?? "-").toString();
    final floor = _toInt(j["floor"]);
    final type = _toType(j["room_type"] ?? j["type"] ?? j["type_name"]);
    final status = _toStatus(j["status"] ?? j["room_status"]);
    final rent = _toInt(j["rent_price"] ?? j["base_rent"] ?? j["rent"] ?? j["price"]);

    final tenantId = _toInt(j["tenant_id"]);
    TenantInfo? tenant;
    if (tenantId > 0) {
      tenant = TenantInfo(
        tenantId: tenantId,
        name: (j["full_name"] ?? "").toString().trim().isEmpty ? null : j["full_name"].toString(),
        phone: (j["phone"] ?? "").toString().trim().isEmpty ? null : j["phone"].toString(),
        tenantStatus: (j["tenant_status"] ?? "active").toString(),
        startDate: (j["start_date"] ?? "").toString().trim().isEmpty ? null : j["start_date"].toString(),
      );
    }

    return Room(
      roomId: roomId,
      dormId: dormId,
      roomNo: roomNo,
      building: building,
      floor: floor,
      type: type,
      status: status,
      rent: rent,
      tenant: tenant,
    );
  }

  String get typeLabel => type.label;
  String get statusLabel => status.label;
}

class TenantInfo {
  final int tenantId;
  final String? name;
  final String? phone;
  final String tenantStatus;
  final String? startDate;

  TenantInfo({
    required this.tenantId,
    required this.name,
    required this.phone,
    required this.tenantStatus,
    required this.startDate,
  });

  String get statusLabel => tenantStatus == "active" ? "กำลังเช่า" : tenantStatus;
}
