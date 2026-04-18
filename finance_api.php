<?php
ob_start();
header("Content-Type: application/json; charset=utf-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') { exit; }

ini_set('display_errors', '0');
error_reporting(E_ALL);

const T_SETTINGS  = "rh_dorm_settings";
const T_MEMBERS   = "rh_dorm_memberships";
const T_METER     = "rh_meter";
const T_PAYMENTS  = "rh_payments";
const T_ROOMS     = "rh_rooms";
const T_BUILDINGS = "rh_buildings";

function ok($extra = []) {
    if (ob_get_length()) ob_clean();
    echo json_encode(array_merge(["ok"=>true, "success"=>true], $extra), JSON_UNESCAPED_UNICODE);
    exit;
}

function fail($msg, $code = 400) {
    http_response_code($code);
    if (ob_get_length()) ob_clean();
    echo json_encode(["ok"=>false, "success"=>false, "message"=>$msg], JSON_UNESCAPED_UNICODE);
    exit;
}

function hasTable($conn, $table) {
    $table = $conn->real_escape_string($table);
    $res = $conn->query("SHOW TABLES LIKE '$table'");
    return $res && $res->num_rows > 0;
}

function hasColumn($conn, $table, $column) {
    $table = $conn->real_escape_string($table);
    $column = $conn->real_escape_string($column);
    $res = $conn->query("SHOW COLUMNS FROM `$table` LIKE '$column'");
    return $res && $res->num_rows > 0;
}

function toSlipUrl($path) {
    if (!$path || $path === "null") return null;
    $scheme = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? "https" : "http";
    $host = $_SERVER['HTTP_HOST'] ?? "localhost";
    $dir = str_replace("\\", "/", dirname($_SERVER['SCRIPT_NAME']));
    return $scheme . "://" . $host . rtrim($dir, '/') . "/" . ltrim($path, '/');
}

function getDormRates($conn, $dorm_id) {
    $rates = ["water_rate" => 0.0, "electric_rate" => 0.0];
    $st = $conn->prepare("SELECT water_rate, electric_rate FROM " . T_SETTINGS . " WHERE dorm_id=? LIMIT 1");
    $st->bind_param("i", $dorm_id);
    $st->execute();
    $row = $st->get_result()->fetch_assoc();
    $st->close();

    if ($row) {
        $rates["water_rate"] = (float)($row["water_rate"] ?? 0);
        $rates["electric_rate"] = (float)($row["electric_rate"] ?? 0);
    }
    return $rates;
}

function getTenantContext($conn, $user_id) {
    $sql = "
        SELECT r.room_id, r.dorm_id
        FROM " . T_ROOMS . " r
        WHERE r.tenant_id = ?
        ORDER BY (r.status='occupied') DESC, r.room_id ASC
        LIMIT 1
    ";
    $st = $conn->prepare($sql);
    $st->bind_param("i", $user_id);
    $st->execute();
    $ctx = $st->get_result()->fetch_assoc();
    $st->close();

    if ($ctx) return $ctx;

    $sql = "
        SELECT m.dorm_id
        FROM " . T_MEMBERS . " m
        WHERE m.user_id=? AND m.approve_status='approved'
        ORDER BY m.membership_id ASC
        LIMIT 1
    ";
    $st = $conn->prepare($sql);
    $st->bind_param("i", $user_id);
    $st->execute();
    $m = $st->get_result()->fetch_assoc();
    $st->close();

    if (!$m) return null;

    $sql = "
        SELECT room_id, dorm_id
        FROM " . T_ROOMS . "
        WHERE dorm_id=? AND tenant_id=?
        ORDER BY room_id ASC
        LIMIT 1
    ";
    $st = $conn->prepare($sql);
    $st->bind_param("ii", $m['dorm_id'], $user_id);
    $st->execute();
    $ctx = $st->get_result()->fetch_assoc();
    $st->close();

    return $ctx ?: null;
}

function getRoomMeta($conn, $room_id) {
    $hasBuildingTable = hasTable($conn, T_BUILDINGS);
    $hasBuildingIdInRooms = hasColumn($conn, T_ROOMS, 'building_id');
    $hasRoomNumber = hasColumn($conn, T_ROOMS, 'room_number');

    $buildingExpr = "'' AS building";
    $joinBuilding = "";

    if ($hasBuildingTable && $hasBuildingIdInRooms) {
        $buildingNameCol = hasColumn($conn, T_BUILDINGS, 'building_name') ? 'b.building_name'
            : (hasColumn($conn, T_BUILDINGS, 'building_code') ? 'b.building_code'
            : (hasColumn($conn, T_BUILDINGS, 'name') ? 'b.name' : "''"));

        $joinBuilding = " LEFT JOIN " . T_BUILDINGS . " b ON b.building_id = r.building_id ";
        $buildingExpr = "COALESCE($buildingNameCol, '') AS building";
    }

    $roomNumberExpr = $hasRoomNumber ? "COALESCE(r.room_number, '') AS room_number" : "'' AS room_number";

    $sql = "
        SELECT
            COALESCE(r.base_rent, 0) AS base_rent,
            $roomNumberExpr,
            $buildingExpr
        FROM " . T_ROOMS . " r
        $joinBuilding
        WHERE r.room_id = ?
        LIMIT 1
    ";

    $st = $conn->prepare($sql);
    $st->bind_param("i", $room_id);
    $st->execute();
    $row = $st->get_result()->fetch_assoc();
    $st->close();

    return [
        "base_rent"   => (float)($row["base_rent"] ?? 0),
        "room_number" => (string)($row["room_number"] ?? ''),
        "building"    => (string)($row["building"] ?? ''),
    ];
}

function getTenantBillItems($conn, $room_id, $dorm_id, $year = 0, $month = 0) {
    $rates = getDormRates($conn, $dorm_id);
    $hasSlipImage = hasColumn($conn, T_PAYMENTS, 'slip_image');
    $hasPaymentDate = hasColumn($conn, T_PAYMENTS, 'payment_date');

    $roomMeta = getRoomMeta($conn, $room_id);
    $roomRent = (float)($roomMeta["base_rent"] ?? 0);
    $roomNumber = (string)($roomMeta["room_number"] ?? '');
    $building = (string)($roomMeta["building"] ?? '');

    $slipSelect = $hasSlipImage ? "p.slip_image," : "NULL AS slip_image,";
    $payDateSelect = $hasPaymentDate ? "p.payment_date," : "NULL AS payment_date,";

    $sql = "
        SELECT
            p.payment_id,
            p.total_amount,
            p.status,
            p.month,
            p.year,
            $slipSelect
            $payDateSelect
            m.water_old,
            m.water_new,
            m.elec_old,
            m.elec_new
        FROM " . T_PAYMENTS . " p
        LEFT JOIN " . T_METER . " m
            ON (m.room_id = p.room_id AND m.month = p.month AND m.year = p.year)
        WHERE p.room_id = ?
    ";

    $types = "i";
    $params = [$room_id];

    if ($year > 0) {
        $sql .= " AND p.year = ?";
        $types .= "i";
        $params[] = $year;
    }
    if ($month > 0) {
        $sql .= " AND p.month = ?";
        $types .= "i";
        $params[] = $month;
    }

    $sql .= " ORDER BY p.year DESC, p.month DESC, p.payment_id DESC";

    $st = $conn->prepare($sql);
    $st->bind_param($types, ...$params);
    $st->execute();
    $rs = $st->get_result();

    $items = [];
    while ($row = $rs->fetch_assoc()) {
        $waterOld = (float)($row['water_old'] ?? 0);
        $waterNew = (float)($row['water_new'] ?? 0);
        $elecOld = (float)($row['elec_old'] ?? 0);
        $elecNew = (float)($row['elec_new'] ?? 0);

        $wUnit = max(0, $waterNew - $waterOld);
        $eUnit = max(0, $elecNew - $elecOld);

        $waterCost = $wUnit * (float)$rates["water_rate"];
        $electricCost = $eUnit * (float)$rates["electric_rate"];

        $dbTotal = (float)($row["total_amount"] ?? 0);
        $calcTotal = $roomRent + $waterCost + $electricCost;
        $finalTotal = $dbTotal > 0 ? $dbTotal : $calcTotal;

        $items[] = [
            "payment_id"     => (int)$row["payment_id"],
            "bill_title"     => "บิลเดือน " . $row["month"] . "/" . $row["year"],
            "status"         => (string)($row["status"] ?? ''),
            "rent"           => $roomRent,
            "water"          => $waterCost,
            "electric"       => $electricCost,
            "water_unit"     => (int)$wUnit,
            "electric_unit"  => (int)$eUnit,
            "water_rate"     => (float)$rates["water_rate"],
            "electric_rate"  => (float)$rates["electric_rate"],
            "total"          => $finalTotal,
            "slip_url"       => toSlipUrl($row["slip_image"] ?? null),
            "pay_date"       => $row["payment_date"] ?? null,
            "month"          => (int)$row["month"],
            "year"           => (int)$row["year"],
            "bill_count"     => 1,
            "building"       => $building,
            "room_number"    => $roomNumber,
        ];
    }
    $st->close();

    return $items;
}

function getTenantYearSummary($conn, $room_id, $dorm_id, $target_year) {
    $rates = getDormRates($conn, $dorm_id);
    $roomMeta = getRoomMeta($conn, $room_id);
    $roomRent = (float)($roomMeta['base_rent'] ?? 0);

    $sql = "
        SELECT p.month, p.total_amount, p.status,
               m.water_old, m.water_new, m.elec_old, m.elec_new
        FROM " . T_PAYMENTS . " p
        LEFT JOIN " . T_METER . " m
            ON (m.room_id = p.room_id AND m.month = p.month AND m.year = p.year)
        WHERE p.room_id = ? AND p.year = ?
        ORDER BY p.month ASC
    ";
    $st = $conn->prepare($sql);
    $st->bind_param("ii", $room_id, $target_year);
    $st->execute();
    $rs = $st->get_result();

    $sumReceived = 0.0;
    $monthsMap = [];
    while ($r = $rs->fetch_assoc()) {
        $isPaid = in_array(strtolower((string)$r['status']), ['paid', 'verified'], true);
        $total = (float)($r['total_amount'] ?? 0);

        $wUnit = max(0, (float)($r['water_new'] ?? 0) - (float)($r['water_old'] ?? 0));
        $eUnit = max(0, (float)($r['elec_new'] ?? 0) - (float)($r['elec_old'] ?? 0));

        $waterCost = $wUnit * (float)$rates["water_rate"];
        $electricCost = $eUnit * (float)$rates["electric_rate"];
        $calcTotal = $roomRent + $waterCost + $electricCost;
        $finalTotal = $total > 0 ? $total : $calcTotal;

        if ($isPaid) {
            $sumReceived += $finalTotal;
        }

        $monthsMap[(int)$r['month']] = [
            "month" => (int)$r["month"],
            "received_income" => $isPaid ? $finalTotal : 0,
            "water" => $waterCost,
            "electric" => $electricCost,
            "bill_count" => 1,
        ];
    }
    $st->close();

    $months = [];
    for ($m = 1; $m <= 12; $m++) {
        $months[] = $monthsMap[$m] ?? [
            "month" => $m,
            "received_income" => 0,
            "water" => 0,
            "electric" => 0,
            "bill_count" => 0,
        ];
    }

    return [
        "received_income" => $sumReceived,
        "months" => $months
    ];
}

// --- ส่วนที่ฟอนต้องการ: แก้ไขให้ดึงแยกรายรับรายปี/เดือนแบบเห็นภาพน้ำไฟชัดเจน ---
function getOwnerDormSummary($conn, $dorm_id, $target_year, $target_month = 0) {
    $rates = getDormRates($conn, $dorm_id);
    
    // 1. เป้าหมายรายรับ (Expected) จากค่าเช่าฐานทุกห้องในหอ
    $stExp = $conn->prepare("SELECT SUM(base_rent) as expected FROM " . T_ROOMS . " WHERE dorm_id = ?");
    $stExp->bind_param("i", $dorm_id);
    $stExp->execute();
    $expectedBase = (float)($stExp->get_result()->fetch_assoc()['expected'] ?? 0);
    $stExp->close();

    $months = [];
    $yearlySums = ["total"=>0, "water"=>0, "electric"=>0, "rent"=>0];

    for ($m = 1; $m <= 12; $m++) {
        // ดึงยอดที่ Verified แล้ว พร้อมหน่วยน้ำไฟจาก Meter ของทุกห้องในหอนั้น
        $sqlM = "
            SELECT 
                SUM(p.total_amount) as total,
                SUM(m.water_new - m.water_old) as w_unit,
                SUM(m.elec_new - m.elec_old) as e_unit
            FROM " . T_PAYMENTS . " p
            LEFT JOIN " . T_METER . " m ON (m.room_id = p.room_id AND m.month = p.month AND m.year = p.year)
            WHERE p.dorm_id = ? AND p.year = ? AND p.month = ? AND p.status = 'verified'
        ";
        $stM = $conn->prepare($sqlM);
        $stM->bind_param("iii", $dorm_id, $target_year, $m);
        $stM->execute();
        $rowM = $stM->get_result()->fetch_assoc();
        
        $mTotal = (float)($rowM['total'] ?? 0);
        $mWater = max(0, (float)($rowM['w_unit'] ?? 0)) * (float)$rates['water_rate'];
        $mElectric = max(0, (float)($rowM['e_unit'] ?? 0)) * (float)$rates['electric_rate'];
        $mRentOnly = max(0, $mTotal - $mWater - $mElectric);

        $months[] = [
            "month" => $m,
            "received_income" => $mTotal,
            "water" => $mWater,
            "electric" => $mElectric,
            "rent" => $mRentOnly
        ];

        $yearlySums["total"] += $mTotal;
        $yearlySums["water"] += $mWater;
        $yearlySums["electric"] += $mElectric;
        $yearlySums["rent"] += $mRentOnly;
        $stM->close();
    }

    // กรณีเจ้าของเลือกเดือนในแอป
    if ($target_month > 0) {
        $curr = $months[$target_month - 1];
        return [
            "expected_income" => $expectedBase,
            "received_income" => $curr['received_income'],
            "months" => $months,
            "breakdown" => [
                "rent" => $curr['rent'],
                "water" => $curr['water'],
                "electric" => $curr['electric']
            ]
        ];
    }

    // กรณีดูภาพรวมทั้งปี
    return [
        "expected_income" => $expectedBase * 12,
        "received_income" => $yearlySums["total"],
        "months" => $months,
        "breakdown" => [
            "rent" => $yearlySums["rent"],
            "water" => $yearlySums["water"],
            "electric" => $yearlySums["electric"]
        ]
    ];
}

try {
    require_once "db.php";
    mysqli_set_charset($conn, "utf8mb4");

    $action = $_REQUEST["action"] ?? "";

    if ($action === "bill_list") {
        $user_id = intval($_REQUEST["user_id"] ?? 0);
        $year = intval($_REQUEST["year"] ?? 0);
        $month = intval($_REQUEST["month"] ?? 0);
        if ($user_id <= 0) fail("ไม่พบ user_id");
        $ctx = getTenantContext($conn, $user_id);
        if (!$ctx) fail("ไม่พบข้อมูลห้องพักของผู้ใช้");
        ok(["items" => getTenantBillItems($conn, (int)$ctx['room_id'], (int)$ctx['dorm_id'], $year, $month)]);
    }

    if ($action === "summary_income") {
        $dorm_id = intval($_REQUEST["dorm_id"] ?? 0);
        $user_id = intval($_REQUEST["user_id"] ?? 0);
        $target_year = intval($_REQUEST["year"] ?? date("Y"));
        $target_month = intval($_REQUEST["month"] ?? 0);

        // กรณีเจ้าของหอ (มี dorm_id)
        if ($dorm_id > 0) {
            ok(getOwnerDormSummary($conn, $dorm_id, $target_year, $target_month));
        } 
        // กรณีผู้เช่า (ไม่มี dorm_id แต่มี user_id)
        else if ($user_id > 0) {
            $ctx = getTenantContext($conn, $user_id);
            if (!$ctx) fail("ไม่พบข้อมูลห้องพักของผู้ใช้");
            ok(getTenantYearSummary($conn, (int)$ctx['room_id'], (int)$ctx['dorm_id'], $target_year));
        }
        fail("ข้อมูลไม่ครบ");
    }

    fail("ไม่พบ action ที่ร้องขอ", 404);

} catch (Throwable $e) {
    fail("Server error: " . $e->getMessage(), 500);
}