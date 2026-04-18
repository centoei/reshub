<?php
header("Content-Type: application/json; charset=utf-8");
ini_set('display_errors', '0');  // กัน HTML error ปน JSON
ini_set('log_errors', '1');
error_reporting(E_ALL);

/* ✅ ดัก fatal error ให้ยังตอบเป็น JSON */
register_shutdown_function(function () {
  $e = error_get_last();
  if ($e && in_array($e['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR])) {
    http_response_code(500);
    echo json_encode([
      "success" => false,
      "message" => "Fatal: ".$e["message"]." @".$e["file"].":".$e["line"]
    ], JSON_UNESCAPED_UNICODE);
  }
});

function jexit($arr, $code = 200) {
  http_response_code($code);
  echo json_encode($arr, JSON_UNESCAPED_UNICODE);
  exit;
}

/* ========= รองรับ JSON body + form POST ========= */
$raw = file_get_contents("php://input");
$ct  = strtolower($_SERVER["CONTENT_TYPE"] ?? "");
$inputJson = null;
if (!empty($raw) && strpos($ct, "application/json") !== false) {
  $inputJson = json_decode($raw, true);
}

$user_id = 0;
if (isset($_POST["user_id"])) $user_id = (int)$_POST["user_id"];
else if (is_array($inputJson) && isset($inputJson["user_id"])) $user_id = (int)$inputJson["user_id"];

if ($user_id <= 0) {
  jexit(["success"=>false, "message"=>"missing user_id"], 400);
}

// ✅ เรียกใช้ db.php ที่เชื่อมต่อฐานข้อมูล reshub
require_once __DIR__ . "/db.php"; 
mysqli_set_charset($conn, "utf8mb4");

try {
  /* ==================================================
     ✅ SQL ใหม่: ปรับชื่อ Column ให้ตรงกับ reshub
     - user_level ('a', 'o', 't')
     - role_code ('o', 't')
  ================================================== */
  $sql = "
    SELECT
      u.user_id, 
      u.username, 
      u.full_name, 
      u.phone, 
      u.user_level,
      m.role_code, 
      m.approve_status, 
      m.dorm_id,
      d.dorm_name
    FROM rh_users u
    LEFT JOIN rh_dorm_memberships m ON m.user_id = u.user_id
    LEFT JOIN rh_dorms d ON d.dorm_id = m.dorm_id
    WHERE u.user_id = ?
    ORDER BY m.membership_id DESC
    LIMIT 1
  ";

  $stmt = $conn->prepare($sql);
  if (!$stmt) jexit(["success"=>false, "message"=>"prepare fail: ".$conn->error], 500);

  $stmt->bind_param("i", $user_id);
  $stmt->execute();
  $rs = $stmt->get_result();
  $row = $rs->fetch_assoc();

  if (!$row) {
    jexit(["success"=>false, "message"=>"ไม่พบผู้ใช้"], 404);
  }

  /* ==================================================
     ✅ Mapping ข้อมูลกลับเป็น Format ที่ Flutter เข้าใจ
     เพื่อให้โค้ดฝั่งแอปไม่ต้องแก้ตัวแปรตาม
  ================================================== */
  $resUser = [
    "user_id"        => (int)$row["user_id"],
    "username"       => $row["username"],
    "full_name"      => $row["full_name"],
    "phone"          => $row["phone"],
    
    // แปลง user_level 'a' -> platform_admin
    "platform_role"  => ($row["user_level"] === 'a' ? "platform_admin" : "user"),
    
    // แปลง role_code 'o' -> owner, 't' -> tenant
    "role_in_dorm"   => ($row["role_code"] === 'o' ? "owner" : "tenant"),
    
    "approve_status" => $row["approve_status"] ?? "pending",
    "dorm_id"        => (int)($row["dorm_id"] ?? 0),
    "dorm_name"      => $row["dorm_name"] ?? null,
    
    // ใน Schema ใหม่ rh_dorm_memberships ไม่มี room_id โดยตรง 
    // จึงส่งค่าพื้นฐานเป็น null/0 ไปก่อนเพื่อไม่ให้แอปค้าง
    "room_id"        => 0 
  ];

  jexit([
    "success" => true,
    "user" => $resUser
  ]);

} catch (Throwable $e) {
  jexit(["success"=>false, "message"=>"server error: ".$e->getMessage()], 500);
}