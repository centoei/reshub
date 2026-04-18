<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db.php';
mysqli_set_charset($conn, 'utf8mb4');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

/**
 * ส่งคำตอบกลับเป็น JSON และหยุดการทำงาน
 */
function jrepair(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

/**
 * ดึงค่าจาก POST/GET หรือค่าเริ่มต้น
 */
function req(string $key, $default = null) {
    return $_POST[$key] ?? $_GET[$key] ?? $default;
}

/**
 * แปลงสถานะภาษาอังกฤษเป็นภาษาไทย
 */
function statusThai(string $status): string {
    switch ($status) {
        case 'pending': return 'รอดำเนินการ';
        case 'working': return 'กำลังดำเนินการ';
        case 'done':    return 'เสร็จสิ้น';
        default:        return '-';
    }
}

/**
 * จัดการอัปโหลดรูปภาพ
 */
function uploadRepairImage(string $fieldName = 'image'): string {
    if (!isset($_FILES[$fieldName])) return '';
    $file = $_FILES[$fieldName];
    if (($file['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_NO_FILE) return '';
    if ($file['error'] !== UPLOAD_ERR_OK) throw new Exception('อัปโหลดรูปไม่สำเร็จ');

    $tmpPath = $file['tmp_name'];
    if (!is_uploaded_file($tmpPath)) throw new Exception('ไฟล์รูปไม่ถูกต้อง');

    $ext = strtolower(pathinfo($file['name'], PATHINFO_EXTENSION));
    if (!in_array($ext, ['jpg', 'jpeg', 'png', 'webp'])) throw new Exception('รองรับเฉพาะ jpg, jpeg, png, webp');

    $uploadDir = __DIR__ . '/uploads/repairs/';
    if (!is_dir($uploadDir)) mkdir($uploadDir, 0777, true);

    $newName = 'repair_' . date('Ymd_His') . '_' . bin2hex(random_bytes(5)) . '.' . $ext;
    if (!move_uploaded_file($tmpPath, $uploadDir . $newName)) throw new Exception('บันทึกไฟล์รูปไม่สำเร็จ');

    return 'uploads/repairs/' . $newName;
}

/**
 * ลบไฟล์รูปภาพ
 */
function deleteImageFile(?string $relativePath): void {
    if (!$relativePath) return;
    $fullPath = __DIR__ . '/' . ltrim($relativePath, '/');
    if (is_file($fullPath)) @unlink($fullPath);
}

// รองรับข้อมูลแบบ JSON Raw Body
$raw = file_get_contents('php://input');
if ($raw) {
    $json = json_decode($raw, true);
    if (is_array($json)) {
        foreach ($json as $k => $v) {
            if (!isset($_POST[$k])) $_POST[$k] = $v;
        }
    }
}

$action = trim((string)req('action', ''));
if ($action === '') jrepair(['success' => false, 'message' => 'ไม่พบ action'], 400);

// --- ACTION: CREATE (ส่งรายการแจ้งซ่อมใหม่) ---
if ($action === 'create') {
    try {
        $userId = (int)req('user_id', req('userId', 0));
        $dormId = (int)req('dorm_id', req('dormId', 0));
        $typeId = (int)req('type_id', req('typeId', 0)); // เปลี่ยนจาก repair_type เป็น type_id
        $detail = trim((string)req('detail', ''));

        if ($userId <= 0 || $dormId <= 0 || $typeId <= 0 || $detail === '') {
            jrepair(['success' => false, 'message' => 'ข้อมูลไม่ครบถ้วน'], 400);
        }

        // ตรวจสอบว่าผู้ใช้มีห้องพักในหอนี้จริงหรือไม่
        $stmt = $conn->prepare("SELECT room_id, room_number FROM rh_rooms WHERE tenant_id = ? AND dorm_id = ? LIMIT 1");
        $stmt->bind_param('ii', $userId, $dormId);
        $stmt->execute();
        $room = $stmt->get_result()->fetch_assoc();
        $stmt->close();

        if (!$room) jrepair(['success' => false, 'message' => 'ยังไม่พบห้องพักของคุณในหอนี้'], 404);

        $roomId = (int)$room['room_id'];
        $imagePath = uploadRepairImage('image');

        // บันทึกรายการแจ้งซ่อม
        $stmt = $conn->prepare("INSERT INTO rh_repairs (dorm_id, room_id, user_id, type_id, detail, image_path, status, created_at) VALUES (?, ?, ?, ?, ?, ?, 'pending', NOW())");
        $stmt->bind_param('iiiiss', $dormId, $roomId, $userId, $typeId, $detail, $imagePath);
        $stmt->execute();
        $repairId = $stmt->insert_id;
        $stmt->close();

        // ดึงชื่อประเภทมาเพื่อส่ง Notification
        $stmt = $conn->prepare("SELECT type_name FROM rh_repair_types WHERE type_id = ?");
        $stmt->bind_param('i', $typeId);
        $stmt->execute();
        $tRow = $stmt->get_result()->fetch_assoc();
        $stmt->close();
        $typeName = $tRow['type_name'] ?? 'ทั่วไป';

        // แจ้งเตือนแอดมิน
        $message = "มีรายการแจ้งซ่อมใหม่ ห้อง " . ($room['room_number'] ?? '-') . " ประเภท: " . $typeName;
        $stmt = $conn->prepare("SELECT user_id FROM rh_dorm_memberships WHERE dorm_id = ? AND approve_status = 'approved' AND role_code IN ('a', 'o')");
        $stmt->bind_param('i', $dormId);
        $stmt->execute();
        $admins = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
        $stmt->close();

        if (!empty($admins)) {
            $stmt = $conn->prepare("INSERT INTO rh_notifications (user_id, dorm_id, type_id, ref_id, message, is_read) VALUES (?, ?, 3, ?, ?, 0)");
            foreach ($admins as $a) {
                $adminId = (int)$a['user_id'];
                $stmt->bind_param('iiis', $adminId, $dormId, $repairId, $message);
                $stmt->execute();
            }
            $stmt->close();
        }

        jrepair(['success' => true, 'ok' => true, 'message' => 'บันทึกการแจ้งซ่อมสำเร็จ', 'repair_id' => $repairId, 'image_path' => $imagePath]);
    } catch (Throwable $e) {
        jrepair(['success' => false, 'message' => $e->getMessage()], 500);
    }
}

// --- ACTION: LIST (รายการแจ้งซ่อมของฉัน) ---
if ($action === 'listMyRepairs') {
    $userId = (int)req('user_id', req('userId', 0));
    $dormId = (int)req('dorm_id', req('dormId', 0));

    if ($userId <= 0) jrepair(['success' => false, 'message' => 'user_id ไม่ถูกต้อง'], 400);

    $sql = "SELECT rp.*, rt.type_name as repair_type, r.room_number, b.building_name 
            FROM rh_repairs rp
            LEFT JOIN rh_repair_types rt ON rp.type_id = rt.type_id
            LEFT JOIN rh_rooms r ON r.room_id = rp.room_id
            LEFT JOIN rh_buildings b ON b.building_id = r.building_id
            WHERE rp.user_id = ? " . ($dormId > 0 ? "AND rp.dorm_id = ? " : "") . "
            ORDER BY rp.repair_id DESC";
    
    $stmt = $conn->prepare($sql);
    if ($dormId > 0) $stmt->bind_param('ii', $userId, $dormId);
    else $stmt->bind_param('i', $userId);
    
    $stmt->execute();
    $rows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    $items = [];
    foreach ($rows as $row) {
        $items[] = [
            'repair_id'     => (int)$row['repair_id'],
            'type_id'       => (int)$row['type_id'],
            'repair_type'   => $row['repair_type'] ?? 'อื่น ๆ',
            'detail'        => $row['detail'] ?? '',
            'image_path'    => $row['image_path'] ?? '',
            'status'        => $row['status'] ?? 'pending',
            'status_th'     => statusThai($row['status'] ?? ''),
            'created_at'    => $row['created_at'] ?? '',
            'room_number'   => $row['room_number'] ?? '',
            'building_name' => $row['building_name'] ?? ''
        ];
    }
    jrepair(['success' => true, 'data' => $items]);
}

// --- ACTION: GET BY ID (ดูรายละเอียดรายชุด) ---
if ($action === 'getRepairById') {
    $repairId = (int)req('repair_id', req('id', 0));
    if ($repairId <= 0) jrepair(['success' => false, 'message' => 'repair_id ไม่ถูกต้อง'], 400);

    $stmt = $conn->prepare("SELECT rp.*, rt.type_name as repair_type, r.room_number, b.building_name, u.full_name, u.phone
                            FROM rh_repairs rp
                            LEFT JOIN rh_repair_types rt ON rt.type_id = rp.type_id
                            LEFT JOIN rh_rooms r ON r.room_id = rp.room_id
                            LEFT JOIN rh_buildings b ON b.building_id = r.building_id
                            LEFT JOIN rh_users u ON u.user_id = rp.user_id
                            WHERE rp.repair_id = ? LIMIT 1");
    $stmt->bind_param('i', $repairId);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$row) jrepair(['success' => false, 'message' => 'ไม่พบรายการ'], 404);

    $row['repair_id'] = (int)$row['repair_id'];
    $row['status_th'] = statusThai($row['status']);
    jrepair(['success' => true, 'data' => $row]);
}

// --- ACTION: UPDATE (แก้ไขรายการ) ---
if ($action === 'update') {
    try {
        $repairId = (int)req('repair_id', req('id', 0));
        $userId = (int)req('user_id', req('userId', 0));
        $typeId = (int)req('type_id', req('typeId', 0));
        $detail = trim((string)req('detail', ''));
        $isImageDeleted = req('is_image_deleted', '0') === '1';

        $stmt = $conn->prepare("SELECT status, image_path FROM rh_repairs WHERE repair_id = ? AND user_id = ? LIMIT 1");
        $stmt->bind_param('ii', $repairId, $userId);
        $stmt->execute();
        $old = $stmt->get_result()->fetch_assoc();
        $stmt->close();

        if (!$old) jrepair(['success' => false, 'message' => 'ไม่พบรายการ'], 404);
        if ($old['status'] !== 'pending') jrepair(['success' => false, 'message' => 'แก้ไขได้เฉพาะรายการรอดำเนินการ'], 400);

        $finalImage = $old['image_path'];
        if ($isImageDeleted) {
            deleteImageFile($old['image_path']);
            $finalImage = '';
        }

        $newUploaded = uploadRepairImage('image');
        if ($newUploaded !== '') {
            if ($finalImage !== '') deleteImageFile($finalImage);
            $finalImage = $newUploaded;
        }

        $stmt = $conn->prepare("UPDATE rh_repairs SET type_id = ?, detail = ?, image_path = ? WHERE repair_id = ? AND user_id = ?");
        $stmt->bind_param('issii', $typeId, $detail, $finalImage, $repairId, $userId);
        $stmt->execute();
        $stmt->close();

        jrepair(['success' => true, 'message' => 'แก้ไขข้อมูลสำเร็จ', 'image_path' => $finalImage]);
    } catch (Throwable $e) {
        jrepair(['success' => false, 'message' => $e->getMessage()], 500);
    }
}

// --- ACTION: DELETE (ลบรายการ) ---
if ($action === 'deleteMyRepair') {
    $repairId = (int)req('repair_id', req('id', 0));
    $userId = (int)req('user_id', req('userId', 0));

    $stmt = $conn->prepare("SELECT image_path FROM rh_repairs WHERE repair_id = ? AND user_id = ? AND status = 'pending' LIMIT 1");
    $stmt->bind_param('ii', $repairId, $userId);
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    $stmt = $conn->prepare("DELETE FROM rh_repairs WHERE repair_id = ? AND user_id = ? AND status = 'pending'");
    $stmt->bind_param('ii', $repairId, $userId);
    $stmt->execute();
    $affected = $stmt->affected_rows;
    $stmt->close();

    if ($affected > 0) {
        if (!empty($row['image_path'])) deleteImageFile($row['image_path']);
        jrepair(['success' => true, 'message' => 'ลบรายการสำเร็จ']);
    }
    jrepair(['success' => false, 'message' => 'ลบไม่ได้ หรือไม่พบรายการ'], 400);
}

jrepair(['success' => false, 'message' => 'action ไม่ถูกต้อง'], 400);