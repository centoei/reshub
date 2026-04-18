<?php
header("Content-Type: application/json; charset=utf-8");
require_once "db.php"; // ใช้ไฟล์ db.php ที่แก้ชื่อ base แล้ว

function j($arr) {
  echo json_encode($arr, JSON_UNESCAPED_UNICODE);
  exit;
}

$username     = trim($_POST["username"] ?? "");
$dormCode     = trim($_POST["dorm_code"] ?? "");
$phone        = trim($_POST["phone"] ?? "");
$new_password = trim($_POST["new_password"] ?? "");

if ($username === "" || $dormCode === "" || $phone === "" || $new_password === "") {
  j(["success"=>false, "message"=>"กรุณากรอกข้อมูลให้ครบ"]);
}

try {
  $conn->begin_transaction();

  // ตรวจสอบ Username + Phone (rh_users) และ Dorm Code (rh_dorms)
  $stmt = $conn->prepare("
    SELECT u.user_id
    FROM rh_users u
    JOIN rh_dorm_memberships m ON m.user_id = u.user_id
    JOIN rh_dorms d ON d.dorm_id = m.dorm_id
    WHERE u.username = ?
      AND u.phone = ?
      AND d.dorm_code = ?
    LIMIT 1
  ");
  
  $stmt->bind_param("sss", $username, $phone, $dormCode);
  $stmt->execute();
  $res = $stmt->get_result();
  $row = $res->fetch_assoc();
  $stmt->close();

  if (!$row) {
    throw new Exception("ข้อมูลไม่ถูกต้อง ไม่สามารถเปลี่ยนรหัสผ่านได้");
  }

  $user_id = (int)$row["user_id"];
  $hash = password_hash($new_password, PASSWORD_DEFAULT);

  // อัปเดตรหัสผ่านใหม่ลง rh_users
  $upd = $conn->prepare("UPDATE rh_users SET password = ? WHERE user_id = ?");
  $upd->bind_param("si", $hash, $user_id);
  $upd->execute();
  $upd->close();

  $conn->commit();
  j(["success"=>true, "message"=>"เปลี่ยนรหัสผ่านเรียบร้อย"]);

} catch (Exception $e) {
  if($conn) $conn->rollback();
  j(["success"=>false, "message"=>$e->getMessage()]);
}