<?php
/**
 * notifications.php
 * ปรับให้รองรับฐานข้อมูล reshub ใหม่ แต่คงรูปแบบ JSON เดิมที่หน้า Flutter ใช้อยู่
 */

header('Content-Type: application/json; charset=utf-8');
ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

if (!function_exists('jexit')) {
    function jexit($arr, $code = 200) {
        http_response_code($code);
        echo json_encode($arr, JSON_UNESCAPED_UNICODE);
        exit;
    }
}
if (!function_exists('ok')) {
    function ok($extra = []) { jexit(array_merge(['ok' => true, 'success' => true], $extra), 200); }
}
if (!function_exists('fail')) {
    function fail($msg, $code = 400, $extra = []) { jexit(array_merge(['ok' => false, 'success' => false, 'message' => $msg], $extra), $code); }
}

require_once 'db.php';
mysqli_set_charset($conn, 'utf8mb4');

$raw = file_get_contents('php://input');
$inputJson = json_decode($raw, true);
function param($k, $default = null) {
    global $inputJson;
    if (isset($_POST[$k])) return $_POST[$k];
    if (isset($_GET[$k])) return $_GET[$k];
    return (is_array($inputJson) && array_key_exists($k, $inputJson)) ? $inputJson[$k] : $default;
}
function tableExists($conn, $table) {
    $t = $conn->real_escape_string($table);
    $rs = $conn->query("SHOW TABLES LIKE '$t'");
    return ($rs && $rs->num_rows > 0);
}
function columnExists($conn, $table, $column) {
    $t = $conn->real_escape_string($table);
    $c = $conn->real_escape_string($column);
    $rs = $conn->query("SHOW COLUMNS FROM `$t` LIKE '$c'");
    return ($rs && $rs->num_rows > 0);
}

$table = tableExists($conn, 'rh_notifications') ? 'rh_notifications' : 'notifications';
$hasCreatedAt = columnExists($conn, $table, 'created_at');
$hasRefId = columnExists($conn, $table, 'ref_id');
$hasTypeText = columnExists($conn, $table, 'type');

$action = trim((string)param('action', 'listNotifications'));
$aliasMap = [
    'unread_count' => 'unreadCount',
    'mark_read'    => 'markRead',
    'delete'       => 'deleteSingle',
];
if (isset($aliasMap[$action])) $action = $aliasMap[$action];

$user_id = (int)param('user_id', 0);
$dorm_id = (int)param('dorm_id', 0);
$limit   = max(1, (int)param('limit', 50));

// ประเภทจาก schema ใหม่: 1 สมัครสมาชิก, 2 ค่าเช่า, 3 แจ้งซ่อม
$adminTypeIDs = '1,2,3';

function buildAudienceWhere($isForCount = false) {
    return "(n.user_id = ? OR ( ? > 0 AND n.dorm_id = ? AND n.type_id IN (1,2,3) AND (n.user_id = 0 OR n.user_id IS NULL)))";
}

function mapTypeFromRow($row) {
    $typeId = (int)($row['type_id'] ?? 0);
    $typeText = strtolower(trim((string)($row['type_raw'] ?? '')));
    $message = strtolower(trim((string)($row['message'] ?? '')));
    $typeName = trim((string)($row['type_name'] ?? ''));

    if ($typeText !== '') {
        return $typeText;
    }
    if ($typeId === 1) return 'new_registration';
    if ($typeId === 2) return 'bill';
    if ($typeId === 3) return 'repair';
    if (strpos($message, 'ซ่อม') !== false) return 'repair';
    if (strpos($message, 'บิล') !== false || strpos($message, 'ค่าเช่า') !== false || strpos($message, 'ชำระ') !== false) return 'bill';
    if (strpos($message, 'สมัคร') !== false || strpos($message, 'อนุมัติ') !== false) return 'new_registration';
    if ($typeName !== '') return strtolower($typeName);
    return 'general';
}

function mapTitleFromRow($row, $type) {
    $typeName = trim((string)($row['type_name'] ?? ''));
    if ($typeName !== '') return $typeName;
    switch ($type) {
        case 'new_registration': return 'สมัครสมาชิก';
        case 'bill': return 'ค่าเช่า';
        case 'repair': return 'แจ้งซ่อม';
        default: return 'แจ้งเตือน';
    }
}

try {
    if ($action === 'unreadCount') {
        $sql = "SELECT COUNT(*) AS c
                FROM `$table` n
                WHERE n.is_read = 0
                  AND " . buildAudienceWhere(true);
        $st = $conn->prepare($sql);
        $st->bind_param('iii', $user_id, $dorm_id, $dorm_id);
        $st->execute();
        $row = $st->get_result()->fetch_assoc();
        $st->close();
        ok(['count' => (int)($row['c'] ?? 0)]);
    }

    if ($action === 'listNotifications') {
        $createdExpr = $hasCreatedAt ? 'n.created_at' : 'NOW()';
        $refExpr = $hasRefId ? 'n.ref_id' : '0';
        $typeExpr = $hasTypeText ? 'n.type' : "''";

        $sql = "SELECT
                    n.notification_id,
                    n.dorm_id,
                    n.user_id,
                    n.type_id,
                    n.message,
                    n.is_read,
                    $createdExpr AS created_at,
                    $refExpr AS ref_id,
                    $typeExpr AS type_raw,
                    t.type_name
                FROM `$table` n
                LEFT JOIN rh_notification_types t ON n.type_id = t.type_id
                WHERE " . buildAudienceWhere() . "
                ORDER BY " . ($hasCreatedAt ? 'n.created_at DESC, ' : '') . "n.notification_id DESC
                LIMIT ?";

        $st = $conn->prepare($sql);
        $st->bind_param('iiii', $user_id, $dorm_id, $dorm_id, $limit);
        $st->execute();
        $res = $st->get_result();
        $rows = [];
        while ($row = $res->fetch_assoc()) {
            $type = mapTypeFromRow($row);
            $rows[] = [
                'notification_id' => (int)($row['notification_id'] ?? 0),
                'dorm_id' => (int)($row['dorm_id'] ?? 0),
                'user_id' => (int)($row['user_id'] ?? 0),
                'title' => mapTitleFromRow($row, $type),
                'message' => (string)($row['message'] ?? ''),
                'type' => $type,
                'type_name' => (string)($row['type_name'] ?? ''),
                'ref_id' => (int)($row['ref_id'] ?? 0),
                'is_read' => (int)($row['is_read'] ?? 0),
                'created_at' => (string)($row['created_at'] ?? ''),
            ];
        }
        $st->close();
        ok(['data' => $rows]);
    }

    if ($action === 'markRead') {
        $nid = (int)param('notification_id', 0);
        if ($nid <= 0) fail('notification_id is required');
        $sql = "UPDATE `$table` n
                SET n.is_read = 1
                WHERE n.notification_id = ?
                  AND " . buildAudienceWhere();
        $st = $conn->prepare($sql);
        $st->bind_param('iiii', $nid, $user_id, $dorm_id, $dorm_id);
        $st->execute();
        $updated = $st->affected_rows;
        $st->close();
        ok(['updated' => $updated]);
    }

    if ($action === 'markAllRead') {
        $sql = "UPDATE `$table` n
                SET n.is_read = 1
                WHERE n.is_read = 0
                  AND " . buildAudienceWhere();
        $st = $conn->prepare($sql);
        $st->bind_param('iii', $user_id, $dorm_id, $dorm_id);
        $st->execute();
        $updated = $st->affected_rows;
        $st->close();
        ok(['updated' => $updated]);
    }

    if ($action === 'deleteSingle') {
        $nid = (int)param('notification_id', 0);
        if ($nid <= 0) fail('notification_id is required');
        $sql = "DELETE n FROM `$table` n
                WHERE n.notification_id = ?
                  AND " . buildAudienceWhere();
        $st = $conn->prepare($sql);
        $st->bind_param('iiii', $nid, $user_id, $dorm_id, $dorm_id);
        $st->execute();
        $deleted = $st->affected_rows;
        $st->close();
        ok(['deleted' => $deleted]);
    }

    if ($action === 'deleteAll') {
        $sql = "DELETE n FROM `$table` n
                WHERE " . buildAudienceWhere();
        $st = $conn->prepare($sql);
        $st->bind_param('iii', $user_id, $dorm_id, $dorm_id);
        $st->execute();
        $deleted = $st->affected_rows;
        $st->close();
        ok(['deleted' => $deleted]);
    }

    fail('Unknown action: ' . $action);
} catch (Throwable $e) {
    jexit(['success' => false, 'message' => 'SERVER_ERROR', 'error' => $e->getMessage()], 500);
}
