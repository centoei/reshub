<?php
header("Content-Type: application/json; charset=utf-8");
ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

/* ✅ กันชน: ถ้ามี jexit อยู่แล้ว (จากไฟล์อื่น) จะไม่ประกาศซ้ำ */
if (!function_exists("jexit")) {
  function jexit($arr, $code = 200) {
    http_response_code($code);
    echo json_encode($arr, JSON_UNESCAPED_UNICODE);
    exit;
  }
}

require_once "db.php";
mysqli_set_charset($conn, "utf8mb4");

/* ✅ include notifications เป็น library ได้เลย (ไม่ชน jexit แล้ว) */
require_once "notifications.php";

$method = $_SERVER["REQUEST_METHOD"] ?? "UNKNOWN";
$data = ($method === "POST") ? $_POST : $_GET;

$admin_user_id = (int)($data["admin_user_id"] ?? 0);
$user_dorm_id  = (int)($data["user_dorm_id"] ?? 0);
$room_id       = (int)($data["room_id"] ?? 0);
$move_in_date  = trim((string)($data["move_in_date"] ?? ""));

if ($admin_user_id <= 0 || $user_dorm_id <= 0 || $room_id <= 0) {
  jexit([
    "success" => false,
    "message" => "ส่ง admin_user_id / user_dorm_id / room_id ไม่ครบ",
    "method"  => $method
  ], 400);
}

if ($move_in_date === "") {
  jexit(["success" => false, "message" => "กรุณาส่ง move_in_date (YYYY-MM-DD)"], 400);
}

$dt = DateTime::createFromFormat("Y-m-d", $move_in_date);
if (!$dt || $dt->format("Y-m-d") !== $move_in_date) {
  jexit(["success" => false, "message" => "รูปแบบ move_in_date ไม่ถูกต้อง ต้องเป็น YYYY-MM-DD"], 400);
}

try {
  $conn->begin_transaction();

  // 1) user_dorms pending
  $q = $conn->prepare("
    SELECT user_dorm_id, user_id, dorm_id, role_in_dorm, approve_status, room_id
    FROM user_dorms
    WHERE user_dorm_id=? LIMIT 1
  ");
  $q->bind_param("i", $user_dorm_id);
  $q->execute();
  $ud = $q->get_result()->fetch_assoc();
  $q->close();

  if (!$ud) {
    $conn->rollback();
    jexit(["success"=>false,"message"=>"ไม่พบรายการ user_dorm_id นี้"], 400);
  }

  $tenant_user_id = (int)$ud["user_id"];
  $dorm_id        = (int)$ud["dorm_id"];

  if (($ud["role_in_dorm"] ?? "") !== "tenant") {
    $conn->rollback();
    jexit(["success"=>false,"message"=>"รายการนี้ไม่ใช่ tenant"], 400);
  }
  if (($ud["approve_status"] ?? "") !== "pending") {
    $conn->rollback();
    jexit(["success"=>false,"message"=>"รายการนี้ไม่อยู่สถานะ pending"], 400);
  }

  // 2) check admin permission
  $chk = $conn->prepare("
    SELECT role_in_dorm, approve_status
    FROM user_dorms
    WHERE user_id=? AND dorm_id=? LIMIT 1
  ");
  $chk->bind_param("ii", $admin_user_id, $dorm_id);
  $chk->execute();
  $me = $chk->get_result()->fetch_assoc();
  $chk->close();

  if (
    !$me ||
    ($me["approve_status"] ?? "") !== "approved" ||
    !in_array(($me["role_in_dorm"] ?? ""), ["owner","admin"])
  ) {
    $conn->rollback();
    jexit(["success"=>false,"message"=>"ไม่มีสิทธิ์อนุมัติ (ต้องเป็น owner/admin และ approved)"], 403);
  }

  // 3) check room vacant + same dorm
  $rq = $conn->prepare("
    SELECT room_id, dorm_id, status, room_number
    FROM rooms
    WHERE dorm_id=? AND room_id=? LIMIT 1
  ");
  $rq->bind_param("ii", $dorm_id, $room_id);
  $rq->execute();
  $room = $rq->get_result()->fetch_assoc();
  $rq->close();

  if (!$room) { $conn->rollback(); jexit(["success"=>false,"message"=>"ไม่พบห้องนี้ในหอนี้"], 400); }
  if (($room["status"] ?? "") !== "vacant") { $conn->rollback(); jexit(["success"=>false,"message"=>"ห้องนี้ไม่ว่างแล้ว"], 400); }

  // 4) approve user_dorms
  $up = $conn->prepare("
    UPDATE user_dorms
    SET approve_status='approved', room_id=?
    WHERE user_dorm_id=? AND dorm_id=? AND approve_status='pending'
  ");
  $up->bind_param("iii", $room_id, $user_dorm_id, $dorm_id);
  $up->execute();
  if ($up->affected_rows <= 0) {
    $up->close();
    $conn->rollback();
    jexit(["success"=>false,"message"=>"อนุมัติไม่สำเร็จ (สถานะอาจเปลี่ยนไปแล้ว)"], 409);
  }
  $up->close();

  // 5) room -> occupied
  $up2 = $conn->prepare("
    UPDATE rooms
    SET status='occupied'
    WHERE dorm_id=? AND room_id=? AND status='vacant'
  ");
  $up2->bind_param("ii", $dorm_id, $room_id);
  $up2->execute();
  if ($up2->affected_rows <= 0) {
    $up2->close();
    $conn->rollback();
    jexit(["success"=>false,"message"=>"อัปเดตห้องไม่สำเร็จ (ห้องอาจไม่ว่างแล้ว)"], 409);
  }
  $up2->close();

  // 6) tenants upsert
  $checkT = $conn->prepare("
    SELECT tenant_id
    FROM tenants
    WHERE dorm_id=? AND user_id=?
    ORDER BY tenant_id DESC
    LIMIT 1
  ");
  $checkT->bind_param("ii", $dorm_id, $tenant_user_id);
  $checkT->execute();
  $ex = $checkT->get_result()->fetch_assoc();
  $checkT->close();

  $tenant_id = 0;
  $createdTenant = false;
  $tenant_status = "active";

  if ($ex) {
    $tenant_id = (int)$ex["tenant_id"];
    $upT = $conn->prepare("
      UPDATE tenants
      SET room_id=?, move_in_date=?, start_date=?, tenant_status=?
      WHERE tenant_id=? AND dorm_id=? AND user_id=?
    ");
    $upT->bind_param("isssiii", $room_id, $move_in_date, $move_in_date, $tenant_status, $tenant_id, $dorm_id, $tenant_user_id);
    $upT->execute();
    $upT->close();
  } else {
    $insT = $conn->prepare("
      INSERT INTO tenants (dorm_id, user_id, room_id, move_in_date, start_date, tenant_status)
      VALUES (?, ?, ?, ?, ?, ?)
    ");
    $insT->bind_param("iiisss", $dorm_id, $tenant_user_id, $room_id, $move_in_date, $move_in_date, $tenant_status);
    $insT->execute();
    if ($insT->affected_rows <= 0) {
      $insT->close();
      $conn->rollback();
      jexit(["success"=>false,"message"=>"เพิ่ม tenants ไม่สำเร็จ: ".$conn->error], 500);
    }
    $tenant_id = (int)$conn->insert_id;
    $createdTenant = true;
    $insT->close();
  }

  // 7) notifications -> tenant (ใช้ library)
  $room_number = (string)($room["room_number"] ?? "");
  $titleN = "อนุมัติการเข้าพักแล้ว ✅";
  $msgN = "คุณได้รับการอนุมัติแล้ว"
        . ($room_number !== "" ? " ห้อง $room_number" : "")
        . "\nวันเข้าอยู่: $move_in_date";

  $sent = 0;
  if (function_exists("noti_push_to_user")) {
    $sent = noti_push_to_user($conn, $dorm_id, $tenant_user_id, $titleN, $msgN, "approve", $tenant_id) ? 1 : 0;
  }

  $conn->commit();

  jexit([
    "success" => true,
    "message" => "อนุมัติผู้เช่าเรียบร้อย ✅ (ตั้งวันเข้าอยู่แล้ว)",
    "dorm_id" => $dorm_id,
    "user_dorm_id" => $user_dorm_id,
    "room_id" => $room_id,
    "tenant_id" => $tenant_id,
    "tenant_created" => $createdTenant,
    "move_in_date" => $move_in_date,
    "noti_sent" => $sent
  ]);

} catch (Throwable $e) {
  $conn->rollback();
  jexit(["success"=>false,"message"=>"เกิดข้อผิดพลาด: ".$e->getMessage()], 500);
}
