<?php
header("Content-Type: application/json; charset=utf-8");
ini_set('display_errors', '0');
ini_set('html_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

register_shutdown_function(function () {
    $e = error_get_last();
    if ($e && in_array($e['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR])) {
        http_response_code(500);
        echo json_encode([
            "success" => false,
            "message" => "Fatal Error: " . $e["message"]
        ], JSON_UNESCAPED_UNICODE);
    }
});

function jexit($arr, $code = 200) {
    http_response_code($code);
    echo json_encode($arr, JSON_UNESCAPED_UNICODE);
    exit;
}

require_once __DIR__ . "/db.php";
if (!$conn) jexit(["success" => false, "message" => "Database connection failed"], 500);

mysqli_set_charset($conn, "utf8mb4");
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

$raw = file_get_contents("php://input");
$inputJson = json_decode($raw, true) ?: [];

function param($k, $default = null) {
    global $inputJson;
    if (isset($_POST[$k])) return $_POST[$k];
    if (isset($_GET[$k])) return $_GET[$k];
    if (isset($inputJson[$k])) return $inputJson[$k];
    return $default;
}

$T_USERS = "rh_users";
$T_MEM   = "rh_dorm_memberships";
$T_ROOMS = "rh_rooms";
$T_NOTI  = "rh_notifications";

$action = trim((string)param("action", "list"));
$dorm_id = (int)param("dorm_id", 0);
$admin_user_id = (int)param("admin_user_id", 0);

if ($dorm_id <= 0 || $admin_user_id <= 0) {
    jexit(["success" => false, "message" => "ข้อมูล dorm_id หรือ admin_user_id ไม่ครบ"], 400);
}

$chk = $conn->prepare("
    SELECT role_code, approve_status
    FROM $T_MEM
    WHERE user_id = ? AND dorm_id = ?
    LIMIT 1
");
$chk->bind_param("ii", $admin_user_id, $dorm_id);
$chk->execute();
$me = $chk->get_result()->fetch_assoc();
$chk->close();

if (
    !$me ||
    ($me["approve_status"] ?? "") !== "approved" ||
    !in_array(($me["role_code"] ?? ""), ["o", "a"], true)
) {
    jexit(["success" => false, "message" => "ไม่มีสิทธิ์เข้าถึงส่วนนี้"], 403);
}

if ($action === "list") {
    try {
        $pending = [];
        $stmt = $conn->prepare("
            SELECT
                m.membership_id AS user_dorm_id,
                m.user_id,
                u.username,
                u.full_name,
                u.phone,
                m.created_at
            FROM $T_MEM m
            JOIN $T_USERS u ON u.user_id = m.user_id
            WHERE m.dorm_id = ?
              AND m.approve_status = 'pending'
            ORDER BY m.created_at ASC, m.membership_id ASC
        ");
        $stmt->bind_param("i", $dorm_id);
        $stmt->execute();
        $rs = $stmt->get_result();
        while ($row = $rs->fetch_assoc()) {
            $pending[] = $row;
        }
        $stmt->close();

        $rooms = [];
        $stmt2 = $conn->prepare("
            SELECT
                r.room_id,
                r.room_number,
                COALESCE(b.building_name, '') AS building,
                r.floor
            FROM $T_ROOMS r
            LEFT JOIN rh_buildings b ON b.building_id = r.building_id
            WHERE r.dorm_id = ?
              AND r.tenant_id IS NULL
              AND (r.status = 'vacant' OR r.status IS NULL OR r.status = '')
            ORDER BY COALESCE(b.building_name, '') ASC, r.floor ASC, r.room_number ASC
        ");
        $stmt2->bind_param("i", $dorm_id);
        $stmt2->execute();
        $rs2 = $stmt2->get_result();
        while ($row = $rs2->fetch_assoc()) {
            $rooms[] = $row;
        }
        $stmt2->close();

        jexit([
            "success" => true,
            "pending" => $pending,
            "rooms" => $rooms
        ]);
    } catch (Throwable $e) {
        jexit(["success" => false, "message" => $e->getMessage()], 500);
    }
}

if ($action === "approve") {
    $user_dorm_id = (int)param("user_dorm_id", 0);
    $user_id = (int)param("user_id", 0);
    $room_id_raw = param("room_id", "");
    $role_selected = trim((string)param("role", "tenant"));

    if ($user_dorm_id <= 0 || $user_id <= 0) {
        jexit(["success" => false, "message" => "ข้อมูลผู้ใช้ไม่ถูกต้อง"], 400);
    }

    $role_code = $role_selected === "admin" ? "a" : "t";

    $room_id = null;
    if ($role_code === "t") {
        $tmpRoomId = (int)$room_id_raw;
        if ($tmpRoomId <= 0) {
            jexit(["success" => false, "message" => "กรุณาเลือกห้องพัก"], 400);
        }
        $room_id = $tmpRoomId;
    }

    $conn->begin_transaction();
    try {
        $stMem = $conn->prepare("
            SELECT membership_id, user_id, dorm_id
            FROM $T_MEM
            WHERE membership_id = ? AND user_id = ? AND dorm_id = ?
            LIMIT 1
        ");
        $stMem->bind_param("iii", $user_dorm_id, $user_id, $dorm_id);
        $stMem->execute();
        $memRow = $stMem->get_result()->fetch_assoc();
        $stMem->close();

        if (!$memRow) {
            throw new Exception("ไม่พบคำขอที่ต้องการอนุมัติ");
        }

        if ($role_code === "t") {
            $stRoom = $conn->prepare("
                SELECT room_id, tenant_id, status
                FROM $T_ROOMS
                WHERE room_id = ? AND dorm_id = ?
                LIMIT 1
            ");
            $stRoom->bind_param("ii", $room_id, $dorm_id);
            $stRoom->execute();
            $roomRow = $stRoom->get_result()->fetch_assoc();
            $stRoom->close();

            if (!$roomRow) {
                throw new Exception("ไม่พบห้องพักที่เลือก");
            }

            if (!empty($roomRow["tenant_id"])) {
                throw new Exception("ห้องนี้มีผู้เช่าแล้ว");
            }

            if (($roomRow["status"] ?? "") === "maintenance") {
                throw new Exception("ห้องนี้อยู่ระหว่างซ่อมบำรุง");
            }

            $stRoomUpd = $conn->prepare("
                UPDATE $T_ROOMS
                SET tenant_id = ?, status = 'occupied'
                WHERE room_id = ? AND dorm_id = ?
            ");
            $stRoomUpd->bind_param("iii", $user_id, $room_id, $dorm_id);
            $stRoomUpd->execute();
            $stRoomUpd->close();
        }

        $st1 = $conn->prepare("
            UPDATE $T_MEM
            SET approve_status = 'approved',
                role_code = ?
            WHERE membership_id = ? AND dorm_id = ?
        ");
        $st1->bind_param("sii", $role_code, $user_dorm_id, $dorm_id);
        $st1->execute();
        $st1->close();

        $message = $role_code === "a"
            ? "คำขอเข้าร่วมหอพักของคุณได้รับการอนุมัติเป็นผู้ดูแลแล้ว"
            : "คำขอเข้าพักของคุณได้รับการอนุมัติแล้ว ห้อง " . $room_id;

        $stN = $conn->prepare("
            INSERT INTO $T_NOTI (user_id, dorm_id, type_id, message, is_read)
            VALUES (?, ?, 1, ?, 0)
        ");
        $stN->bind_param("iis", $user_id, $dorm_id, $message);
        $stN->execute();
        $stN->close();

        $conn->commit();
        jexit(["success" => true, "message" => "อนุมัติเรียบร้อยแล้ว"]);
    } catch (Throwable $e) {
        $conn->rollback();
        jexit(["success" => false, "message" => $e->getMessage()], 500);
    }
}

if ($action === "reject") {
    $user_dorm_id = (int)param("user_dorm_id", 0);
    if ($user_dorm_id <= 0) {
        jexit(["success" => false, "message" => "ID ไม่ถูกต้อง"], 400);
    }

    try {
        $stGet = $conn->prepare("
            SELECT membership_id, user_id
            FROM $T_MEM
            WHERE membership_id = ? AND dorm_id = ?
            LIMIT 1
        ");
        $stGet->bind_param("ii", $user_dorm_id, $dorm_id);
        $stGet->execute();
        $m = $stGet->get_result()->fetch_assoc();
        $stGet->close();

        if (!$m) {
            jexit(["success" => false, "message" => "ไม่พบรายการ"], 404);
        }

        $st = $conn->prepare("
            UPDATE $T_MEM
            SET approve_status = 'rejected'
            WHERE membership_id = ? AND dorm_id = ?
        ");
        $st->bind_param("ii", $user_dorm_id, $dorm_id);
        $ok = $st->execute();
        $st->close();

        if (!$ok) {
            jexit(["success" => false, "message" => "ไม่สามารถบันทึกได้"], 500);
        }

        $msg = "คำขอเข้าร่วมหอพักของคุณถูกปฏิเสธ";
        $stN = $conn->prepare("
            INSERT INTO $T_NOTI (user_id, dorm_id, type_id, message, is_read)
            VALUES (?, ?, 1, ?, 0)
        ");
        $stN->bind_param("iis", $m["user_id"], $dorm_id, $msg);
        $stN->execute();
        $stN->close();

        jexit(["success" => true, "message" => "ปฏิเสธการสมัครเรียบร้อย"]);
    } catch (Throwable $e) {
        jexit(["success" => false, "message" => $e->getMessage()], 500);
    }
}

jexit(["success" => false, "message" => "ไม่พบ Action ที่ต้องการ"], 400);
