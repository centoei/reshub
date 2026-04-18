<?php
header("Content-Type: application/json; charset=utf-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit;
}

require_once "db.php";
mysqli_set_charset($conn, "utf8mb4");

function jexit($arr, $code = 200) {
    http_response_code($code);
    echo json_encode($arr, JSON_UNESCAPED_UNICODE);
    exit;
}

function param($key, $default = "") {
    if (isset($_POST[$key])) return $_POST[$key];
    if (isset($_GET[$key])) return $_GET[$key];
    static $json = null;
    if ($json === null) {
        $raw = file_get_contents("php://input");
        $json = json_decode($raw, true);
        if (!is_array($json)) $json = [];
    }
    return $json[$key] ?? $default;
}

function columnExists(mysqli $conn, string $table, string $column): bool {
    $table = $conn->real_escape_string($table);
    $column = $conn->real_escape_string($column);
    $res = $conn->query("SHOW COLUMNS FROM `$table` LIKE '$column'");
    return $res && $res->num_rows > 0;
}

function dbToThaiStatus(string $status): string {
    $s = strtolower(trim($status));
    if ($s === 'working') return 'กำลังดำเนินการ';
    if ($s === 'done') return 'เสร็จสิ้น';
    return 'รอดำเนินการ';
}

function thaiToDbStatus(string $status): string {
    $s = strtolower(trim($status));
    if ($s === 'working' || str_contains($status, 'กำลัง')) return 'working';
    if ($s === 'done' || str_contains($status, 'เสร็จ')) return 'done';
    return 'pending';
}

function insertNotification(mysqli $conn, int $dormId, int $userId, string $message, int $typeId = 3, int $refId = 0): void {
    $hasCreatedAt = columnExists($conn, 'rh_notifications', 'created_at');
    $hasRefId = columnExists($conn, 'rh_notifications', 'ref_id');

    if ($hasCreatedAt && $hasRefId) {
        $st = $conn->prepare("INSERT INTO rh_notifications (user_id, dorm_id, type_id, ref_id, message, is_read, created_at) VALUES (?, ?, ?, ?, ?, 0, NOW())");
        $st->bind_param("iiiis", $userId, $dormId, $typeId, $refId, $message);
    } elseif ($hasRefId) {
        $st = $conn->prepare("INSERT INTO rh_notifications (user_id, dorm_id, type_id, ref_id, message, is_read) VALUES (?, ?, ?, ?, ?, 0)");
        $st->bind_param("iiiis", $userId, $dormId, $typeId, $refId, $message);
    } else {
        $st = $conn->prepare("INSERT INTO rh_notifications (user_id, dorm_id, type_id, message, is_read) VALUES (?, ?, ?, ?, 0)");
        $st->bind_param("iiis", $userId, $dormId, $typeId, $message);
    }
    $st->execute();
    $st->close();
}

/**
 * ปรับปรุงให้ดึงชื่อประเภทจากชื่อที่ Join มา
 */
function normalizeRepairRow(array $row): array {
    // ใช้ชื่อจาก rh_repair_types (type_name) ถ้าไม่มีให้ใช้ 'อื่น ๆ'
    $finalRepairType = trim((string)($row['type_name'] ?? ''));
    if ($finalRepairType === '') {
        $finalRepairType = 'อื่น ๆ';
    }

    $row['title'] = 'แจ้งซ่อม' . $finalRepairType;
    $row['repair_type'] = $finalRepairType;
    $row['status_th'] = dbToThaiStatus((string)($row['status'] ?? 'pending'));

    $img = trim((string)($row['image_path'] ?? ''));
    $row['image_first'] = $img;
    $row['images'] = $img !== '' ? json_encode([$img], JSON_UNESCAPED_UNICODE) : '[]';

    return $row;
}

$action = (string)param('action', '');
if ($action === '') jexit(['success' => false, 'message' => 'Missing action'], 400);

// --- ดึงรายการของผู้ใช้คนนั้นๆ ---
if ($action === 'listMyRepairs') {
    $userId = (int)param('user_id', 0);
    $dormId = (int)param('dorm_id', 0);

    $sql = "SELECT r.*, rt.type_name, rm.room_number, b.building_name, u.full_name, u.phone
            FROM rh_repairs r
            LEFT JOIN rh_repair_types rt ON rt.type_id = r.type_id
            LEFT JOIN rh_rooms rm ON rm.room_id = r.room_id
            LEFT JOIN rh_buildings b ON b.building_id = rm.building_id
            LEFT JOIN rh_users u ON u.user_id = r.user_id
            WHERE r.user_id = ? AND r.dorm_id = ?
            ORDER BY r.repair_id DESC";

    $st = $conn->prepare($sql);
    $st->bind_param("ii", $userId, $dormId);
    $st->execute();
    $res = $st->get_result();
    $items = [];
    while ($row = $res->fetch_assoc()) {
        $items[] = normalizeRepairRow($row);
    }
    $st->close();
    jexit(['success' => true, 'ok' => true, 'data' => $items]);
}

// --- ดึงรายการทั้งหมด (สำหรับ Admin) ---
if ($action === 'list') {
    $dormId = (int)param('dorm_id', 0);
    if ($dormId <= 0) jexit(['success' => false, 'message' => 'missing dorm_id'], 400);

    $status = trim((string)param('status', ''));
    $whereStatus = '';
    $params = [$dormId];
    $types = 'i';

    if ($status !== '' && $status !== 'all' && $status !== 'ทั้งหมด') {
        $dbStatus = thaiToDbStatus($status);
        $whereStatus = ' AND r.status = ? ';
        $params[] = $dbStatus;
        $types .= 's';
    }

    $sql = "SELECT r.*, rt.type_name, rm.room_number, b.building_name, u.full_name, u.phone
            FROM rh_repairs r
            LEFT JOIN rh_repair_types rt ON rt.type_id = r.type_id
            LEFT JOIN rh_rooms rm ON rm.room_id = r.room_id
            LEFT JOIN rh_buildings b ON b.building_id = rm.building_id
            LEFT JOIN rh_users u ON u.user_id = r.user_id
            WHERE r.dorm_id = ? $whereStatus
            ORDER BY r.repair_id DESC";

    $st = $conn->prepare($sql);
    $st->bind_param($types, ...$params);
    $st->execute();
    $res = $st->get_result();
    $items = [];
    while ($row = $res->fetch_assoc()) {
        $items[] = normalizeRepairRow($row);
    }
    $st->close();
    jexit(['success' => true, 'ok' => true, 'data' => $items]);
}

// --- อัปเดตสถานะงานซ่อม ---
if ($action === 'update_status') {
    $repairId = (int)param('repair_id', 0);
    $statusDb = thaiToDbStatus((string)param('status', 'pending'));

    $st = $conn->prepare("UPDATE rh_repairs SET status=? WHERE repair_id=?");
    $st->bind_param("si", $statusDb, $repairId);
    $ok = $st->execute();
    $st->close();

    if ($ok) {
        // ส่ง Notification แจ้งผู้เช่า
        $infoSql = "SELECT r.dorm_id, r.user_id, rt.type_name, rm.room_number 
                    FROM rh_repairs r 
                    LEFT JOIN rh_repair_types rt ON rt.type_id = r.type_id
                    LEFT JOIN rh_rooms rm ON rm.room_id = r.room_id
                    WHERE r.repair_id = ? LIMIT 1";
        $infoSt = $conn->prepare($infoSql);
        $infoSt->bind_param("i", $repairId);
        $infoSt->execute();
        $info = $infoSt->get_result()->fetch_assoc();
        $infoSt->close();

        if ($info) {
            $typeName = $info['type_name'] ?? 'ทั่วไป';
            $msg = "อัปเดตงานซ่อมแจ้งซ่อม{$typeName} (ห้อง {$info['room_number']}) สถานะใหม่: " . dbToThaiStatus($statusDb);
            insertNotification($conn, (int)$info['dorm_id'], (int)$info['user_id'], $msg, 3, $repairId);
        }
        jexit(['success' => true, 'ok' => true, 'status_th' => dbToThaiStatus($statusDb)]);
    }
    jexit(['success' => false, 'message' => 'Update failed'], 500);
}

// --- ดึงข้อมูลรายชุด ---
if ($action === 'getRepairById') {
    $repairId = (int)param('repair_id', 0);
    $dormId = (int)param('dorm_id', 0);
    
    $sql = "SELECT r.*, rt.type_name, rm.room_number, b.building_name, u.full_name, u.phone
            FROM rh_repairs r
            LEFT JOIN rh_repair_types rt ON rt.type_id = r.type_id
            LEFT JOIN rh_rooms rm ON rm.room_id = r.room_id
            LEFT JOIN rh_buildings b ON b.building_id = rm.building_id
            LEFT JOIN rh_users u ON u.user_id = r.user_id
            WHERE r.repair_id = ? AND r.dorm_id = ? LIMIT 1";
            
    $st = $conn->prepare($sql);
    $st->bind_param("ii", $repairId, $dormId);
    $st->execute();
    $row = $st->get_result()->fetch_assoc();
    $st->close();

    if ($row) {
        jexit(['success' => true, 'ok' => true, 'data' => normalizeRepairRow($row)]);
    }
    jexit(['success' => false, 'message' => 'ไม่พบข้อมูล'], 404);
}

jexit(['success' => false, 'message' => 'Unknown action'], 400);