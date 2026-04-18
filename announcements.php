<?php
ob_start();
header("Content-Type: application/json; charset=utf-8");
error_reporting(E_ALL);
ini_set('display_errors', 0);

require_once __DIR__ . "/db.php";
$conn->set_charset("utf8mb4");

// กำหนด Base URL (แนะนำให้ใช้ path สัมพัทธ์ หรือ config ที่ถูกต้อง)
define('BASE_URL', 'https://yourdomain.com/reshub/'); 

function jexit($arr, $code = 200) {
    http_response_code($code);
    ob_clean();
    echo json_encode($arr, JSON_UNESCAPED_UNICODE);
    exit;
}

function hasColumn($conn, $table, $column) {
    static $cache = [];
    $key = $table . '.' . $column;
    if (array_key_exists($key, $cache)) return $cache[$key];
    $res = $conn->query("SHOW COLUMNS FROM `$table` LIKE '$column'");
    $cache[$key] = $res && $res->num_rows > 0;
    return $cache[$key];
}

function normalizeImageUrl($imagePath) {
    if (empty($imagePath)) return '';
    if (preg_match('~^https?://~i', $imagePath)) return $imagePath;
    // ตรวจสอบว่าไฟล์มีอยู่จริงใน server หรือไม่
    $localPath = __DIR__ . "/" . ltrim($imagePath, '/');
    if (!file_exists($localPath)) return ''; 
    return BASE_URL . ltrim($imagePath, '/');
}

$hasImageColumn = hasColumn($conn, 'rh_announcements', 'image');
$action = $_REQUEST['action'] ?? '';

// --- 1. แสดงรายการประกาศ ---
if ($action === 'list') {
    $dormId = (int)($_GET['dorm_id'] ?? 0);
    if ($dormId <= 0) jexit(["ok" => false, "message" => "dorm_id ไม่ถูกต้อง"], 400);

    $selectImage = $hasImageColumn ? ", image" : ", '' AS image";
    $sql = "SELECT announce_id, dorm_id, title, detail, is_pinned, status, created_at $selectImage
            FROM rh_announcements
            WHERE dorm_id=?
            ORDER BY is_pinned DESC, announce_id DESC"; // เรียงตาม ID ล่าสุดด้วย

    $stmt = $conn->prepare($sql);
    $stmt->bind_param("i", $dormId);
    $stmt->execute();
    $rows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    $stmt->close();

    foreach ($rows as &$row) {
        $row['image'] = normalizeImageUrl($row['image'] ?? '');
        $row['is_pinned'] = (int)$row['is_pinned'];
        // คืนค่า status ตามจริง (active/hidden)
        $row['status'] = (strtolower($row['status']) === 'hidden') ? 'hidden' : 'active';
    }
    jexit(["ok" => true, "data" => $rows ?: []]);
}

// --- 2. อัปเดตสถานะการมองเห็น (แก้ไขจุดนี้เพื่อให้ซ่อนได้) ---
if ($action === 'update_visibility') {
    $id = (int)($_POST['announce_id'] ?? 0);
    $status = $_POST['status']; // รับค่าตรงๆ จาก Flutter (active หรือ hidden)
    
    // ตรวจสอบค่าสถานะป้องกันค่าแปลกปลอม
    if($status !== 'active' && $status !== 'hidden'){
        $status = 'active'; 
    }
    
    $stmt = $conn->prepare("UPDATE rh_announcements SET status=? WHERE announce_id=?");
    $stmt->bind_param("si", $status, $id);
    $ok = $stmt->execute();
    
    jexit([
        "ok" => $ok,
        "new_status" => $status,
        "message" => $ok ? "อัปเดตสถานะสำเร็จ" : "ไม่สามารถอัปเดตได้"
    ]);
}

// --- 3. ลบประกาศ ---
if ($action === 'delete') {
    $id = (int)($_POST['announce_id'] ?? 0);
    
    // ลบไฟล์ภาพก่อนลบ Row
    $stmtImg = $conn->prepare("SELECT image FROM rh_announcements WHERE announce_id=?");
    $stmtImg->bind_param("i", $id);
    $stmtImg->execute();
    $res = $stmtImg->get_result()->fetch_assoc();
    if ($res && !empty($res['image'])) {
        $path = __DIR__ . "/" . ltrim($res['image'], '/');
        if (file_exists($path)) @unlink($path);
    }
    
    $stmt = $conn->prepare("DELETE FROM rh_announcements WHERE announce_id=?");
    $stmt->bind_param("i", $id);
    $ok = $stmt->execute();
    jexit(["ok" => $ok]);
}

// --- 4. เพิ่มหรือแก้ไขประกาศ ---
if ($action === 'add' || $action === 'update') {
    $id = (int)($_POST['announce_id'] ?? 0);
    $dormId = (int)($_POST['dorm_id'] ?? 0);
    $title = trim($_POST['title'] ?? '');
    $detail = trim($_POST['detail'] ?? '');
    $pinned = (int)($_POST['is_pinned'] ?? 0);
    $status = ($_POST['status'] === 'hidden') ? 'hidden' : 'active';
    $delImg = (int)($_POST['delete_image'] ?? 0);

    $imagePath = null;
    // จัดการอัปโหลดรูปภาพ
    if (isset($_FILES['image']) && $_FILES['image']['error'] === 0) {
        $dir = "uploads/announcements/";
        if (!is_dir(__DIR__ . "/" . $dir)) @mkdir(__DIR__ . "/" . $dir, 0777, true);
        
        $ext = strtolower(pathinfo($_FILES['image']['name'], PATHINFO_EXTENSION));
        $imagePath = $dir . "ann_" . uniqid() . "." . $ext;
        move_uploaded_file($_FILES['image']['tmp_name'], __DIR__ . "/" . $imagePath);
        
        // ถ้าเป็นการแก้ไข ให้ลบรูปเก่าทิ้ง
        if ($action === 'update') {
            $stmtOld = $conn->prepare("SELECT image FROM rh_announcements WHERE announce_id=?");
            $stmtOld->bind_param("i", $id);
            $stmtOld->execute();
            $old = $stmtOld->get_result()->fetch_assoc();
            if ($old && !empty($old['image'])) {
                @unlink(__DIR__ . "/" . ltrim($old['image'], '/'));
            }
        }
    }

    if ($action === 'add') {
        $sql = "INSERT INTO rh_announcements (dorm_id, title, detail, image, is_pinned, status) VALUES (?,?,?,?,?,?)";
        $stmt = $conn->prepare($sql);
        $stmt->bind_param("isssis", $dormId, $title, $detail, $imagePath, $pinned, $status);
    } else {
        // กรณี Update
        if ($imagePath !== null) {
            // อัปเดตรูปใหม่
            $sql = "UPDATE rh_announcements SET title=?, detail=?, is_pinned=?, status=?, image=? WHERE announce_id=?";
            $stmt = $conn->prepare($sql);
            $stmt->bind_param("ssissi", $title, $detail, $pinned, $status, $imagePath, $id);
        } elseif ($delImg == 1) {
            // สั่งลบรูปเดิม (เปลี่ยนเป็นค่าว่าง)
            $sql = "UPDATE rh_announcements SET title=?, detail=?, is_pinned=?, status=?, image='' WHERE announce_id=?";
            $stmt = $conn->prepare($sql);
            $stmt->bind_param("ssisi", $title, $detail, $pinned, $status, $id);
        } else {
            // ไม่อัปเดตรูปภาพ
            $sql = "UPDATE rh_announcements SET title=?, detail=?, is_pinned=?, status=? WHERE announce_id=?";
            $stmt = $conn->prepare($sql);
            $stmt->bind_param("ssisi", $title, $detail, $pinned, $status, $id);
        }
    }
    
    $ok = $stmt->execute();
    jexit(["ok" => $ok]);
}

jexit(["ok" => false, "message" => "Invalid action"], 400);