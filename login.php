<?php
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");
header("Content-Type: application/json; charset=utf-8");

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') { exit; }

require_once "db.php"; 
mysqli_set_charset($conn, "utf8mb4");

function j($arr, $code = 200){
  http_response_code($code);
  echo json_encode($arr, JSON_UNESCAPED_UNICODE);
  exit;
}

try {
  $data = ($_SERVER["REQUEST_METHOD"] === "POST") ? $_POST : $_GET;
  $username = trim((string)($data["username"] ?? ""));
  $password = (string)($data["password"] ?? "");

  if ($username === "" || $password === "") {
    j(["success" => false, "message" => "กรอกข้อมูลไม่ครบ"], 400);
  }

  // ✅ ดึง user_id, username, password, full_name, user_level จาก rh_users
  $stmt = $conn->prepare("SELECT user_id, username, password, full_name, user_level FROM rh_users WHERE username=? LIMIT 1");
  $stmt->bind_param("s", $username);
  $stmt->execute();
  $user = $stmt->get_result()->fetch_assoc();
  $stmt->close();

  // ตรวจสอบความถูกต้องของรหัสผ่าน
  if (!$user || !password_verify($password, (string)$user["password"])) {
    j(["success" => false, "message" => "ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง"], 401);
  }

  $user_id = (int)$user["user_id"];
  $user_level = $user["user_level"]; // 'a'=Admin ระบบ, 'o'=เจ้าของหอ, 't'=ผู้เช่า

  // 1. กรณี Platform Admin (ผู้ดูแลระบบใหญ่)
  if ($user_level === 'a') {
    j([
      "success" => true,
      "user" => [
        "user_id" => $user_id,
        "username" => $user["username"],
        "full_name" => $user["full_name"], // ✅ ส่งชื่อจริง
        "platform_role" => "platform_admin",
        "approve_status" => "approved",
        "role_in_dorm" => "admin"
      ]
    ]);
  }

  // 2. กรณีผู้ใช้งานทั่วไป (เจ้าของหอ หรือ ผู้เช่า)
  // ดึงข้อมูลหอพักที่ผูกไว้ (rh_dorm_memberships JOIN rh_dorms)
  $q = $conn->prepare("
    SELECT m.dorm_id, m.role_code, m.approve_status, d.dorm_name 
    FROM rh_dorm_memberships m
    JOIN rh_dorms d ON d.dorm_id = m.dorm_id
    WHERE m.user_id = ?
    ORDER BY CASE m.role_code WHEN 'o' THEN 1 ELSE 2 END, m.membership_id DESC LIMIT 1
  ");
  $q->bind_param("i", $user_id);
  $q->execute();
  $ud = $q->get_result()->fetch_assoc();
  $q->close();
  
  if (!$ud) {
    j(["success" => false, "message" => "บัญชีนี้ยังไม่ได้ผูกกับหอพัก"], 403);
  }

  // ส่งข้อมูลกลับไปยัง Flutter
  j([
    "success" => true,
    "user" => [
      "user_id" => $user_id,
      "username" => $user["username"],
      "full_name" => $user["full_name"], // ✅ ส่งชื่อจริง (ไม่ใช่ username)
      "platform_role" => "user",
      "dorm_id" => (int)$ud["dorm_id"],
      "dorm_name" => $ud["dorm_name"],
      "role_in_dorm" => ($ud["role_code"] === 'o' ? "owner" : "tenant"),
      "approve_status" => $ud["approve_status"]
    ]
  ]);

} catch (Throwable $e) {
  j(["success" => false, "message" => "Server error: " . $e->getMessage()], 500);
}