<?php
header('Content-Type: application/json; charset=utf-8');
error_reporting(0);
require_once __DIR__ . '/db.php';
$conn->set_charset('utf8mb4');

function jexit($arr, $code = 200) {
    http_response_code($code);
    echo json_encode($arr, JSON_UNESCAPED_UNICODE);
    exit;
}

function hasColumn(mysqli $conn, string $table, string $column): bool {
    static $cache = [];
    $key = $table . '.' . $column;
    if (array_key_exists($key, $cache)) return $cache[$key];

    $table = $conn->real_escape_string($table);
    $column = $conn->real_escape_string($column);
    $res = $conn->query("SHOW COLUMNS FROM `$table` LIKE '$column'");
    $cache[$key] = $res && $res->num_rows > 0;
    return $cache[$key];
}

function getBaseUrl(): string {
    if (!empty($_ENV['APP_BASE_URL'])) return rtrim($_ENV['APP_BASE_URL'], '/') . '/';
    if (!empty($_SERVER['APP_BASE_URL'])) return rtrim($_SERVER['APP_BASE_URL'], '/') . '/';

    $https = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off');
    $scheme = $https ? 'https' : 'http';
    $host = $_SERVER['HTTP_HOST'] ?? 'localhost';
    $scriptDir = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/');
    if ($scriptDir === '' || $scriptDir === '.') $scriptDir = '';
    return $scheme . '://' . $host . $scriptDir . '/';
}

function absoluteImageUrl(string $baseUrl, string $path): string {
    $path = trim($path);
    if ($path === '' || $path === 'DEL') return '';
    if (preg_match('~^https?://~i', $path)) return $path;
    return $baseUrl . ltrim($path, '/');
}

$dorm_id = isset($_POST['dorm_id']) ? (int)$_POST['dorm_id'] : (int)($_GET['dorm_id'] ?? 0);
$user_id = isset($_POST['user_id']) ? (int)$_POST['user_id'] : (int)($_GET['user_id'] ?? 0);
$action = $_POST['action'] ?? $_GET['action'] ?? '';

if ($action !== 'get_all_stats') {
    jexit(['success' => false, 'message' => 'Invalid action'], 400);
}

if ($dorm_id <= 0 || $user_id <= 0) {
    jexit(['success' => false, 'message' => 'dorm_id หรือ user_id ไม่ถูกต้อง'], 400);
}

$hasImageColumn = hasColumn($conn, 'rh_announcements', 'image');
$selectImage = $hasImageColumn ? ', COALESCE(image, "") AS image' : ', "" AS image';
$baseUrl = getBaseUrl();

$stmt = $conn->prepare("SELECT COUNT(*) AS total FROM rh_dorm_memberships WHERE dorm_id = ? AND approve_status = 'pending'");
$stmt->bind_param('i', $dorm_id);
$stmt->execute();
$r_pending = $stmt->get_result()->fetch_assoc();
$stmt->close();

$stmt = $conn->prepare("SELECT COUNT(*) AS total FROM rh_repairs WHERE dorm_id = ? AND status <> 'done'");
$stmt->bind_param('i', $dorm_id);
$stmt->execute();
$r_repair = $stmt->get_result()->fetch_assoc();
$stmt->close();

$stmt = $conn->prepare("SELECT COUNT(*) AS total FROM rh_notifications WHERE user_id = ? AND is_read = 0");
$stmt->bind_param('i', $user_id);
$stmt->execute();
$r_noti = $stmt->get_result()->fetch_assoc();
$stmt->close();

$sqlAnn = "SELECT announce_id, title, detail, is_pinned, created_at $selectImage
           FROM rh_announcements
           WHERE dorm_id = ? AND status = 'active'
           ORDER BY is_pinned DESC, created_at DESC, announce_id DESC
           LIMIT 5";
$stmt = $conn->prepare($sqlAnn);
$stmt->bind_param('i', $dorm_id);
$stmt->execute();
$resAnn = $stmt->get_result();

$announcements = [];
while ($row = $resAnn->fetch_assoc()) {
    $announcements[] = [
        'announce_id' => (int)$row['announce_id'],
        'title' => $row['title'] ?? '',
        'detail' => $row['detail'] ?? '',
        'image' => absoluteImageUrl($baseUrl, $row['image'] ?? ''),
        'is_pinned' => (int)($row['is_pinned'] ?? 0),
        'created_at' => $row['created_at'] ?? null,
    ];
}
$stmt->close();

jexit([
    'success' => true,
    'pending_approve' => (int)($r_pending['total'] ?? 0),
    'pending_repair' => (int)($r_repair['total'] ?? 0),
    'unread_count' => (int)($r_noti['total'] ?? 0),
    'total_announcements' => count($announcements),
    'announcements_list' => $announcements,
]);
