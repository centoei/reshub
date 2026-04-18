<?php
header("Content-Type: application/json; charset=utf-8");
ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

register_shutdown_function(function () {
    $e = error_get_last();
    if ($e && in_array($e['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR])) {
        http_response_code(500);
        echo json_encode([
            "ok" => false,
            "message" => "Fatal Error: {$e['message']}"
        ], JSON_UNESCAPED_UNICODE);
    }
});

function ok($extra = []) {
    echo json_encode(array_merge(["ok" => true], $extra), JSON_UNESCAPED_UNICODE);
    exit;
}

function fail($msg, $code = 400) {
    http_response_code($code);
    echo json_encode(["ok" => false, "message" => $msg], JSON_UNESCAPED_UNICODE);
    exit;
}

require_once "db.php";
mysqli_set_charset($conn, "utf8mb4");
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

$raw = file_get_contents("php://input");
$inputJson = json_decode($raw, true) ?: [];

function param($k, $default = "") {
    global $inputJson;
    if (isset($_GET[$k])) return $_GET[$k];
    if (isset($_POST[$k])) return $_POST[$k];
    if (isset($inputJson[$k])) return $inputJson[$k];
    return $default;
}

$action  = (string)param("action", "get");
$dorm_id = (int)param("dorm_id", 0);
$month   = (int)param("month", date("n"));
$year    = (int)param("year", date("Y"));

if ($dorm_id <= 0) fail("ไม่พบ dorm_id");
if ($month < 1 || $month > 12) fail("เดือนไม่ถูกต้อง");
if ($year < 2000 || $year > 2100) fail("ปีไม่ถูกต้อง");

$prevMonth = $month - 1;
$prevYear  = $year;
if ($prevMonth <= 0) {
    $prevMonth = 12;
    $prevYear = $year - 1;
}

if ($action === "get") {
    try {
        $stS = $conn->prepare("
            SELECT water_rate, electric_rate
            FROM rh_dorm_settings
            WHERE dorm_id = ?
            LIMIT 1
        ");
        $stS->bind_param("i", $dorm_id);
        $stS->execute();
        $setRow = $stS->get_result()->fetch_assoc() ?: ["water_rate" => 0, "electric_rate" => 0];
        $stS->close();

        $sql = "
            SELECT
                r.room_id,
                r.room_number,
                COALESCE(b.building_name, '') AS building,
                COALESCE(pm.water_new, 0) AS prev_w,
                COALESCE(pm.elec_new, 0) AS prev_e,
                COALESCE(cm.water_new, 0) AS cur_w,
                COALESCE(cm.elec_new, 0) AS cur_e
            FROM rh_rooms r
            LEFT JOIN rh_buildings b
                ON b.building_id = r.building_id
            LEFT JOIN rh_meter pm
                ON pm.dorm_id = r.dorm_id
               AND pm.room_id = r.room_id
               AND pm.month = ?
               AND pm.year = ?
            LEFT JOIN rh_meter cm
                ON cm.dorm_id = r.dorm_id
               AND cm.room_id = r.room_id
               AND cm.month = ?
               AND cm.year = ?
            WHERE r.dorm_id = ?
            ORDER BY
                COALESCE(b.building_name, '') ASC,
                r.floor ASC,
                r.room_number ASC
        ";

        $st = $conn->prepare($sql);
        $st->bind_param("iiiii", $prevMonth, $prevYear, $month, $year, $dorm_id);
        $st->execute();
        $rs = $st->get_result();

        $rooms = [];
        while ($row = $rs->fetch_assoc()) {
            $rooms[] = [
                "room_id" => (int)$row["room_id"],
                "room_number" => (string)$row["room_number"],
                "building" => (string)$row["building"],
                "prev_water_meter" => (int)$row["prev_w"],
                "prev_electric_meter" => (int)$row["prev_e"],
                "current_water_meter" => (int)$row["cur_w"],
                "current_electric_meter" => (int)$row["cur_e"],
            ];
        }
        $st->close();

        ok([
            "rooms" => $rooms,
            "water_rate" => (float)$setRow["water_rate"],
            "electric_rate" => (float)$setRow["electric_rate"]
        ]);
    } catch (Throwable $e) {
        fail($e->getMessage(), 500);
    }
}

if ($action === "save") {
    $items = param("items");
    if (!is_array($items) || empty($items)) fail("รายการข้อมูลไม่ถูกต้อง");

    try {
        $conn->begin_transaction();
        $savedCount = 0;

        $stPrev = $conn->prepare("
            SELECT water_new, elec_new
            FROM rh_meter
            WHERE dorm_id = ? AND room_id = ? AND month = ? AND year = ?
            LIMIT 1
        ");

        $stCur = $conn->prepare("
            SELECT reading_id, water_new, elec_new
            FROM rh_meter
            WHERE dorm_id = ? AND room_id = ? AND month = ? AND year = ?
            LIMIT 1
        ");

        $stRoom = $conn->prepare("
            SELECT room_id
            FROM rh_rooms
            WHERE room_id = ? AND dorm_id = ?
            LIMIT 1
        ");

        $stUpd = $conn->prepare("
            UPDATE rh_meter
            SET water_old = ?, water_new = ?, elec_old = ?, elec_new = ?
            WHERE reading_id = ?
        ");

        $stIns = $conn->prepare("
            INSERT INTO rh_meter
            (dorm_id, room_id, month, year, water_old, water_new, elec_old, elec_new)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ");

        foreach ($items as $it) {
            $room_id = isset($it['room_id']) ? (int)$it['room_id'] : 0;
            if ($room_id <= 0) continue;

            $stRoom->bind_param("ii", $room_id, $dorm_id);
            $stRoom->execute();
            if (!$stRoom->get_result()->fetch_assoc()) {
                continue;
            }

            $stPrev->bind_param("iiii", $dorm_id, $room_id, $prevMonth, $prevYear);
            $stPrev->execute();
            $prevRow = $stPrev->get_result()->fetch_assoc();
            $prevW = $prevRow ? (int)$prevRow['water_new'] : 0;
            $prevE = $prevRow ? (int)$prevRow['elec_new'] : 0;

            $stCur->bind_param("iiii", $dorm_id, $room_id, $month, $year);
            $stCur->execute();
            $curRow = $stCur->get_result()->fetch_assoc();

            $newW = array_key_exists('water_meter', $it)
                ? (int)$it['water_meter']
                : ($curRow ? (int)$curRow['water_new'] : $prevW);

            $newE = array_key_exists('electric_meter', $it)
                ? (int)$it['electric_meter']
                : ($curRow ? (int)$curRow['elec_new'] : $prevE);

            if ($newW < $prevW) fail("เลขน้ำห้อง {$room_id} ต่ำกว่าเดือนก่อน");
            if ($newE < $prevE) fail("เลขไฟห้อง {$room_id} ต่ำกว่าเดือนก่อน");

            if ($curRow) {
                $reading_id = (int)$curRow['reading_id'];
                $stUpd->bind_param("iiiii", $prevW, $newW, $prevE, $newE, $reading_id);
                if ($stUpd->execute()) $savedCount++;
            } else {
                $stIns->bind_param("iiiiiiii", $dorm_id, $room_id, $month, $year, $prevW, $newW, $prevE, $newE);
                if ($stIns->execute()) $savedCount++;
            }
        }

        $stPrev->close();
        $stCur->close();
        $stRoom->close();
        $stUpd->close();
        $stIns->close();

        $conn->commit();
        ok(["saved" => $savedCount]);
    } catch (Throwable $e) {
        $conn->rollback();
        fail($e->getMessage(), 500);
    }
}

fail("Unknown action");