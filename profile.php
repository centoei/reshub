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

function jprofile(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
    exit;
}

$data = $_POST + $_GET;
$raw = file_get_contents('php://input');
if ($raw) {
    $decoded = json_decode($raw, true);
    if (is_array($decoded)) {
        $data = array_merge($data, $decoded);
    }
}

$action = $data['action'] ?? 'get';
$userId = (int)($data['user_id'] ?? $data['userId'] ?? 0);

if ($userId <= 0) {
    jprofile(['success' => false, 'message' => 'user_id ไม่ถูกต้อง'], 400);
}

if ($action === 'change_password') {
    $old = trim($data['old_password'] ?? '');
    $new = trim($data['new_password'] ?? '');

    if ($old === '' || $new === '') {
        jprofile(['success' => false, 'message' => 'กรอกข้อมูลไม่ครบ'], 400);
    }

    $stmt = $conn->prepare('SELECT password FROM rh_users WHERE user_id=? LIMIT 1');
    $stmt->bind_param('i', $userId);
    $stmt->execute();
    $u = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$u || !password_verify($old, $u['password'])) {
        jprofile(['success' => false, 'message' => 'รหัสผ่านเดิมไม่ถูกต้อง'], 401);
    }

    $hash = password_hash($new, PASSWORD_DEFAULT);
    $stmt = $conn->prepare('UPDATE rh_users SET password=? WHERE user_id=?');
    $stmt->bind_param('si', $hash, $userId);
    $stmt->execute();
    $stmt->close();

    jprofile(['success' => true, 'message' => 'เปลี่ยนรหัสผ่านสำเร็จ']);
}

if ($action === 'update') {
    $username = trim($data['username'] ?? '');
    $fullName = trim($data['full_name'] ?? '');
    $phone = trim($data['phone'] ?? '');

    if ($username === '' || $fullName === '' || $phone === '') {
        jprofile(['success' => false, 'message' => 'กรอกข้อมูลไม่ครบ'], 400);
    }

    $stmt = $conn->prepare('SELECT user_id FROM rh_users WHERE username=? AND user_id<>? LIMIT 1');
    $stmt->bind_param('si', $username, $userId);
    $stmt->execute();
    $dup = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if ($dup) {
        jprofile(['success' => false, 'message' => 'username ถูกใช้แล้ว'], 409);
    }

    $stmt = $conn->prepare('UPDATE rh_users SET username=?, full_name=?, phone=? WHERE user_id=?');
    $stmt->bind_param('sssi', $username, $fullName, $phone, $userId);
    $stmt->execute();
    $stmt->close();
}

$stmt = $conn->prepare('SELECT user_id, username, full_name, phone, user_level FROM rh_users WHERE user_id=? LIMIT 1');
$stmt->bind_param('i', $userId);
$stmt->execute();
$user = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$user) {
    jprofile(['success' => false, 'message' => 'ไม่พบผู้ใช้'], 404);
}

$stmt = $conn->prepare(
    "SELECT m.membership_id, m.dorm_id, m.role_code, m.approve_status, d.dorm_name
     FROM rh_dorm_memberships m
     LEFT JOIN rh_dorms d ON d.dorm_id = m.dorm_id
     WHERE m.user_id=?
     ORDER BY
        CASE m.approve_status WHEN 'approved' THEN 1 WHEN 'pending' THEN 2 ELSE 3 END,
        CASE m.role_code WHEN 'o' THEN 1 WHEN 'a' THEN 2 WHEN 't' THEN 3 ELSE 4 END,
        m.membership_id ASC
     LIMIT 1"
);
$stmt->bind_param('i', $userId);
$stmt->execute();
$membership = $stmt->get_result()->fetch_assoc();
$stmt->close();

$room = null;
if ($membership) {
    $dormId = (int)$membership['dorm_id'];

    $stmt = $conn->prepare(
        "SELECT r.room_id, r.room_number, r.floor, r.base_rent, r.status,
                b.building_id, b.building_name,
                rt.type_id, rt.type_name
         FROM rh_rooms r
         LEFT JOIN rh_buildings b ON b.building_id = r.building_id
         LEFT JOIN rh_room_types rt ON rt.type_id = r.type_id
         WHERE r.tenant_id=? AND r.dorm_id=?
         ORDER BY r.room_id ASC
         LIMIT 1"
    );
    $stmt->bind_param('ii', $userId, $dormId);
    $stmt->execute();
    $room = $stmt->get_result()->fetch_assoc();
    $stmt->close();
}

$roleInDorm = null;
if ($membership) {
    if ($membership['role_code'] === 'o') {
        $roleInDorm = 'owner';
    } elseif ($membership['role_code'] === 'a') {
        $roleInDorm = 'admin';
    } else {
        $roleInDorm = 'tenant';
    }
}

$responseData = [
    'user_id' => (int)$user['user_id'],
    'username' => $user['username'],
    'full_name' => $user['full_name'],
    'phone' => $user['phone'],
    'user_level' => $user['user_level'],
    'platform_role' => $user['user_level'] === 'a' ? 'platform_admin' : 'user',
    'role_in_dorm' => $roleInDorm,
    'approve_status' => $membership['approve_status'] ?? null,
    'dorm_id' => isset($membership['dorm_id']) ? (int)$membership['dorm_id'] : null,
    'dorm_name' => $membership['dorm_name'] ?? null,
    'room_id' => $room ? (int)$room['room_id'] : null,
    'room_number' => $room['room_number'] ?? null,
    'floor' => $room ? (int)$room['floor'] : null,
    'room_status' => $room['status'] ?? null,
    'base_rent' => $room ? (float)$room['base_rent'] : null,
    'building_id' => ($room && $room['building_id'] !== null) ? (int)$room['building_id'] : null,
    'building_name' => $room['building_name'] ?? null,
    'building' => $room['building_name'] ?? null,
    'room_type_id' => ($room && $room['type_id'] !== null) ? (int)$room['type_id'] : null,
    'room_type_name' => $room['type_name'] ?? null,
];

jprofile([
    'success' => true,
    'ok' => true,
    'message' => 'โหลดข้อมูลสำเร็จ',
    'data' => $responseData,

    // เผื่อหน้าเก่าอ่านค่าจาก top-level
    'user_id' => $responseData['user_id'],
    'username' => $responseData['username'],
    'full_name' => $responseData['full_name'],
    'phone' => $responseData['phone'],
    'user_level' => $responseData['user_level'],
    'platform_role' => $responseData['platform_role'],
    'role_in_dorm' => $responseData['role_in_dorm'],
    'approve_status' => $responseData['approve_status'],
    'dorm_id' => $responseData['dorm_id'],
    'dorm_name' => $responseData['dorm_name'],
    'room_id' => $responseData['room_id'],
    'room_number' => $responseData['room_number'],
    'floor' => $responseData['floor'],
    'room_status' => $responseData['room_status'],
    'base_rent' => $responseData['base_rent'],
    'building_id' => $responseData['building_id'],
    'building_name' => $responseData['building_name'],
    'building' => $responseData['building'],
    'room_type_id' => $responseData['room_type_id'],
    'room_type_name' => $responseData['room_type_name'],
]);