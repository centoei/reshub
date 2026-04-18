<?php
header("Content-Type: application/json; charset=utf-8");
require_once "db.php";

function j($arr) { echo json_encode($arr, JSON_UNESCAPED_UNICODE); exit; }

$full_name = trim($_POST["full_name"] ?? "");
$phone     = trim($_POST["phone"] ?? "");
$username  = trim($_POST["username"] ?? "");
$password  = trim($_POST["password"] ?? "");
$dormCode  = trim($_POST["dorm_code"] ?? "");

try {
    $conn->begin_transaction();

    // 1. ตรวจสอบหอพัก
    $qDorm = $conn->prepare("SELECT dorm_id FROM rh_dorms WHERE dorm_code=? LIMIT 1");
    $qDorm->bind_param("s", $dormCode);
    $qDorm->execute();
    $dorm = $qDorm->get_result()->fetch_assoc();
    if (!$dorm) throw new Exception("ไม่พบโค้ดหอพักนี้");
    $dorm_id = (int)$dorm["dorm_id"];

    // 2. เพิ่ม User (t = Tenant)
    $hash = password_hash($password, PASSWORD_DEFAULT);
    $stmt = $conn->prepare("INSERT INTO rh_users (username, password, full_name, phone, user_level) VALUES (?, ?, ?, ?, 't')");
    $stmt->bind_param("ssss", $username, $hash, $full_name, $phone);
    $stmt->execute();
    $user_id = $conn->insert_id;

    // 3. ผูกหอพัก (t = Tenant)
    $stmt2 = $conn->prepare("INSERT INTO rh_dorm_memberships (user_id, dorm_id, role_code, approve_status) VALUES (?, ?, 't', 'pending')");
    $stmt2->bind_param("ii", $user_id, $dorm_id);
    $stmt2->execute();

    // 4. บันทึกแจ้งเตือน (สมมติ type_id 1 = สมัครสมาชิกใหม่)
    $stmtNoti = $conn->prepare("INSERT INTO rh_notifications (user_id, dorm_id, type_id, message) VALUES (?, ?, 1, ?)");
    $msg = "มีผู้ขอเข้าร่วมหอพัก: $full_name";
    $stmtNoti->bind_param("iis", $user_id, $dorm_id, $msg);
    $stmtNoti->execute();

    $conn->commit();
    j(["success"=>true, "user_id"=>$user_id]);

} catch (Exception $e) {
    if($conn) $conn->rollback();
    j(["success"=>false, "message"=>$e->getMessage()]);
}