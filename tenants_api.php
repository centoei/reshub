<?php
header('Content-Type: application/json; charset=utf-8');

$host = 'localhost';
$user = 'root';
$pass = '';
$db   = 'reshub';

$conn = new mysqli($host, $user, $pass, $db);
if ($conn->connect_error) {
    http_response_code(500);
    echo json_encode([
        'ok' => false,
        'message' => 'DB connect fail: ' . $conn->connect_error,
    ], JSON_UNESCAPED_UNICODE);
    exit;
}
$conn->set_charset('utf8mb4');

$raw = file_get_contents('php://input');
$ct  = strtolower($_SERVER['CONTENT_TYPE'] ?? '');
$inputJson = null;
if (!empty($raw) && strpos($ct, 'application/json') !== false) {
    $tmp = json_decode($raw, true);
    if (is_array($tmp)) {
        $inputJson = $tmp;
    }
}

function req_val($key, $default = null) {
    global $inputJson;
    return $_GET[$key]
        ?? $_POST[$key]
        ?? ($_SERVER['HTTP_' . strtoupper(str_replace('-', '_', $key))] ?? null)
        ?? (is_array($inputJson) ? ($inputJson[$key] ?? null) : null)
        ?? $default;
}

$action   = req_val('action', 'list');
$dorm_id  = intval(req_val('dorm_id', 0));
$user_id  = intval(req_val('user_id', 0));

function json_out($arr, $code = 200) {
    http_response_code($code);
    echo json_encode($arr, JSON_UNESCAPED_UNICODE);
    exit;
}

if ($action === 'list') {
    $where = "WHERE m.approve_status = 'approved'";
    $types = '';
    $params = [];

    if ($dorm_id > 0) {
        $where .= " AND m.dorm_id = ?";
        $types .= 'i';
        $params[] = $dorm_id;
    }

    $sql = "
        SELECT
            m.membership_id,
            m.membership_id AS tenant_id,
            m.user_id,
            m.dorm_id,
            m.role_code,
            m.approve_status,
            u.username,
            u.full_name,
            u.phone,
            u.user_level,
            r.room_id,
            r.room_number,
            r.floor,
            b.building_name AS building,
            b.building_name,
            d.dorm_name,
            CASE
                WHEN m.role_code IN ('a','o') OR u.user_level IN ('a','o') THEN 'admin'
                ELSE 'tenant'
            END AS role,
            CASE
                WHEN m.role_code = 'o' OR u.user_level = 'o' THEN 'owner'
                WHEN m.role_code = 'a' OR u.user_level = 'a' THEN 'admin'
                ELSE 'tenant'
            END AS role_in_dorm,
            CASE
                WHEN r.room_id IS NOT NULL THEN 'active'
                ELSE 'waiting'
            END AS tenant_status,
            NULL AS move_in_date
        FROM rh_dorm_memberships m
        INNER JOIN rh_users u
            ON u.user_id = m.user_id
        INNER JOIN rh_dorms d
            ON d.dorm_id = m.dorm_id
        LEFT JOIN rh_rooms r
            ON r.tenant_id = m.user_id
           AND r.dorm_id = m.dorm_id
        LEFT JOIN rh_buildings b
            ON b.building_id = r.building_id
        $where
        ORDER BY
            CASE
                WHEN (m.role_code IN ('a','o') OR u.user_level IN ('a','o')) THEN 0
                ELSE 1
            END,
            COALESCE(b.building_name, ''),
            COALESCE(r.floor, 0),
            COALESCE(r.room_number, ''),
            COALESCE(u.full_name, u.username, '')
    ";

    $st = $conn->prepare($sql);
    if (!$st) {
        json_out(['ok' => false, 'message' => 'prepare failed: ' . $conn->error], 500);
    }

    if (!empty($params)) {
        $st->bind_param($types, ...$params);
    }
    $st->execute();
    $res = $st->get_result();

    $rows = [];
    while ($row = $res->fetch_assoc()) {
        $row['membership_id'] = isset($row['membership_id']) ? intval($row['membership_id']) : null;
        $row['tenant_id']     = isset($row['tenant_id']) ? intval($row['tenant_id']) : null;
        $row['user_id']       = isset($row['user_id']) ? intval($row['user_id']) : null;
        $row['dorm_id']       = isset($row['dorm_id']) ? intval($row['dorm_id']) : null;
        $row['room_id']       = isset($row['room_id']) && $row['room_id'] !== null ? intval($row['room_id']) : 0;
        $row['floor']         = isset($row['floor']) && $row['floor'] !== null ? intval($row['floor']) : null;
        $rows[] = $row;
    }

    json_out([
        'ok' => true,
        'success' => true,
        'dorm_id' => $dorm_id,
        'count' => count($rows),
        'data' => $rows,
    ]);
}

if ($action === 'get') {
    if ($user_id <= 0) {
        json_out(['ok' => false, 'success' => false, 'message' => 'missing user_id'], 400);
    }

    $whereDorm = '';
    $types = 'i';
    $params = [$user_id];

    if ($dorm_id > 0) {
        $whereDorm = " AND m.dorm_id = ? ";
        $types .= 'i';
        $params[] = $dorm_id;
    }

    $sql = "
        SELECT
            u.user_id,
            u.username,
            u.full_name,
            u.phone,
            u.user_level,
            m.dorm_id,
            d.dorm_name,
            m.role_code,
            CASE
                WHEN m.role_code = 'o' OR u.user_level = 'o' THEN 'owner'
                WHEN m.role_code = 'a' OR u.user_level = 'a' THEN 'admin'
                ELSE 'tenant'
            END AS role_in_dorm,
            b.building_name AS building,
            r.room_id,
            r.room_number,
            NULL AS move_in_date
        FROM rh_users u
        LEFT JOIN rh_dorm_memberships m
            ON m.user_id = u.user_id
           AND m.approve_status = 'approved'
        LEFT JOIN rh_dorms d
            ON d.dorm_id = m.dorm_id
        LEFT JOIN rh_rooms r
            ON r.tenant_id = u.user_id
           AND r.dorm_id = m.dorm_id
        LEFT JOIN rh_buildings b
            ON b.building_id = r.building_id
        WHERE u.user_id = ?
        $whereDorm
        ORDER BY
            CASE WHEN m.dorm_id IS NULL THEN 1 ELSE 0 END,
            m.membership_id DESC
        LIMIT 1
    ";

    $st = $conn->prepare($sql);
    if (!$st) {
        json_out(['ok' => false, 'message' => 'prepare failed: ' . $conn->error], 500);
    }
    $st->bind_param($types, ...$params);
    $st->execute();
    $res = $st->get_result();
    $row = $res->fetch_assoc();

    if (!$row) {
        json_out(['ok' => false, 'success' => false, 'message' => 'ไม่พบข้อมูลผู้ใช้'], 404);
    }

    $row['user_id'] = intval($row['user_id']);
    $row['dorm_id'] = isset($row['dorm_id']) ? intval($row['dorm_id']) : 0;
    $row['room_id'] = isset($row['room_id']) && $row['room_id'] !== null ? intval($row['room_id']) : 0;

    json_out([
        'ok' => true,
        'success' => true,
        'data' => $row,
    ]);
}

if ($action === 'remove') {
    $target_user_id = intval(req_val('user_id', 0));
    if ($target_user_id <= 0) {
        json_out(['ok' => false, 'message' => 'missing user_id'], 400);
    }
    if ($dorm_id <= 0) {
        json_out(['ok' => false, 'message' => 'missing dorm_id'], 400);
    }

    $conn->begin_transaction();
    try {
        $findRoom = $conn->prepare("SELECT room_id FROM rh_rooms WHERE dorm_id = ? AND tenant_id = ? LIMIT 1");
        if (!$findRoom) {
            throw new Exception('prepare findRoom failed: ' . $conn->error);
        }
        $findRoom->bind_param('ii', $dorm_id, $target_user_id);
        $findRoom->execute();
        $roomRes = $findRoom->get_result();
        $room = $roomRes->fetch_assoc();

        if ($room && !empty($room['room_id'])) {
            $room_id = intval($room['room_id']);
            $updRoom = $conn->prepare("UPDATE rh_rooms SET tenant_id = NULL, status = 'vacant' WHERE room_id = ? AND dorm_id = ?");
            if (!$updRoom) {
                throw new Exception('prepare updRoom failed: ' . $conn->error);
            }
            $updRoom->bind_param('ii', $room_id, $dorm_id);
            $updRoom->execute();
        }

        $delMember = $conn->prepare("DELETE FROM rh_dorm_memberships WHERE user_id = ? AND dorm_id = ?");
        if (!$delMember) {
            throw new Exception('prepare delMember failed: ' . $conn->error);
        }
        $delMember->bind_param('ii', $target_user_id, $dorm_id);
        $delMember->execute();

        $conn->commit();
        json_out([
            'ok' => true,
            'success' => true,
            'message' => 'ลบชื่อออกจากหอพักเรียบร้อยแล้ว',
        ]);
    } catch (Throwable $e) {
        $conn->rollback();
        json_out([
            'ok' => false,
            'message' => 'Error: ' . $e->getMessage(),
        ], 500);
    }
}

json_out(['ok' => false, 'message' => 'Unknown action'], 400);
?>