<?php
header("Content-Type: application/json; charset=utf-8");
require_once "db.php";

/* =========================
   helpers
========================= */
function jexit($arr, $code = 200) {
    if (ob_get_length()) ob_clean(); // ล้าง junk output
    http_response_code($code);
    echo json_encode($arr, JSON_UNESCAPED_UNICODE);
    exit;
}

function post($k, $d=""){ return $_POST[$k] ?? $d; }
function getq($k, $d=""){ return $_GET[$k] ?? $d; }

mysqli_set_charset($conn, "utf8mb4");

$action = trim((string)post("action", getq("action","")));

/* =========================
   tables
========================= */
const T_PAYMENTS  = "rh_payments";
const T_TENANTS   = "rh_tenants";
const T_UTILITIES = "rh_utilities";
const T_DORM      = "rh_dorm_settings";
const T_ROOMS     = "rh_rooms";

/* =========================================================
   ACTION: summary (สำหรับหน้าแรก และ กราฟรายปี)
   - ดึงยอดรวมรายเดือน
   - แยก Water / Electric สำหรับกราฟคู่
========================================================= */
if ($action === "summary") {

    $dorm_id = intval(post("dorm_id", getq("dorm_id", 0)));
    $year    = intval(post("year", getq("year", 0)));

    if ($dorm_id <= 0 || $year <= 0) {
        jexit(["success"=>false,"message"=>"missing params"], 400);
    }

    // SQL ดึงข้อมูลสรุปรายเดือนแบบละเอียด เพื่อวาดกราฟแยกน้ำ-ไฟ
    $sql = "
        SELECT 
            m.month,
            COALESCE(SUM(p.total_price), 0) AS total_received,
            COALESCE(SUM(uu.water_price), 0) AS water_total,
            COALESCE(SUM(uu.electric_price), 0) AS electric_total,
            COALESCE(SUM(uu.total_price), 0) AS utility_total
        FROM (
            SELECT 1 AS month UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 
            UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 
            UNION SELECT 9 UNION SELECT 10 UNION SELECT 11 UNION SELECT 12
        ) m
        LEFT JOIN ".T_PAYMENTS." p ON p.month = m.month AND p.year = ? AND p.dorm_id = ? AND p.status = 'verified'
        LEFT JOIN (
            SELECT 
                dorm_id, year, month,
                SUM(water_total) AS water_price,
                SUM(electric_total) AS electric_price,
                SUM(total) AS total_price
            FROM ".T_UTILITIES."
            WHERE dorm_id = ? AND year = ?
            GROUP BY month
        ) uu ON uu.month = m.month
        GROUP BY m.month
        ORDER BY m.month
    ";

    $st = $conn->prepare($sql);
    $st->bind_param("iiii", $year, $dorm_id, $dorm_id, $year);
    $st->execute();
    $res = $st->get_result();
    
    $out = [];
    $total_year = 0;

    while ($r = $res->fetch_assoc()) {
        $total_year += floatval($r["total_received"]);
        $out[] = [
            "month" => intval($r["month"]),
            "received_income" => floatval($r["total_received"]),
            "water_income" => floatval($r["water_total"]),
            "electric_income" => floatval($r["electric_total"]),
            "total" => floatval($r["total_received"]),
        ];
    }

    $st->close();
    jexit([
        "success" => true, 
        "year_total" => $total_year,
        "months" => $out
    ]);
}

/* =========================================================
   ACTION: detail (สำหรับสรุปรายเดือน และนับจำนวนห้อง)
========================================================= */
if ($action === "detail") {

    $dorm_id = intval(post("dorm_id", getq("dorm_id", 0)));
    $year    = intval(post("year", getq("year", 0)));
    $month   = intval(post("month", getq("month", 0)));

    if ($dorm_id <= 0 || $year <= 0 || $month < 1 || $month > 12) {
        jexit(["success"=>false,"message"=>"invalid params"], 400);
    }

    // 1. ดึงข้อมูลตัวเลขสรุปเงิน
    $sql_finance = "
        SELECT 
            COALESCE(SUM(CASE WHEN p.status = 'verified' THEN p.total_price ELSE 0 END), 0) as received,
            COALESCE(SUM(CASE WHEN p.status = 'pending' THEN p.total_price ELSE 0 END), 0) as pending,
            (SELECT COALESCE(SUM(r.rent_price), 0) FROM ".T_ROOMS." r WHERE r.dorm_id = ?) as total_expected
        FROM ".T_PAYMENTS." p
        WHERE p.dorm_id = ? AND p.year = ? AND p.month = ?
    ";
    
    $st_f = $conn->prepare($sql_finance);
    $st_f->bind_param("iiii", $dorm_id, $dorm_id, $year, $month);
    $st_f->execute();
    $finance = $st_f->get_result()->fetch_assoc();
    $st_f->close();

    // 2. ดึงข้อมูลนับจำนวนห้อง (Counts)
    $sql_counts = "
        SELECT 
            COUNT(CASE WHEN p.status = 'verified' THEN 1 END) as paid,
            COUNT(CASE WHEN p.status = 'pending' THEN 1 END) as pending,
            COUNT(CASE WHEN (p.status IS NULL OR p.status = 'unpaid') THEN 1 END) as unpaid
        FROM ".T_TENANTS." t
        LEFT JOIN ".T_PAYMENTS." p ON p.tenant_id = t.tenant_id AND p.year = ? AND p.month = ?
        WHERE t.dorm_id = ? AND t.tenant_status = 'active'
    ";
    
    $st_c = $conn->prepare($sql_counts);
    $st_c->bind_param("iii", $year, $month, $dorm_id);
    $st_c->execute();
    $counts = $st_c->get_result()->fetch_assoc();
    $st_c->close();

    // 3. ดึงค่าตั้งค่าหอพัก
    $st_s = $conn->prepare("SELECT common_fee, billing_day FROM ".T_DORM." WHERE dorm_id = ? LIMIT 1");
    $st_s->bind_param("i", $dorm_id);
    $st_s->execute();
    $settings = $st_s->get_result()->fetch_assoc();
    $st_s->close();

    $expected = floatval($finance["total_expected"]);
    $received = floatval($finance["received"]);

    jexit([
        "success" => true,
        "expected_income" => $expected,
        "received_income" => $received,
        "pending_income" => floatval($finance["pending"]),
        "outstanding_income" => max(0, $expected - $received),
        "counts" => [
            "paid" => intval($counts["paid"]),
            "pending" => intval($counts["pending"]),
            "unpaid" => intval($counts["unpaid"]),
            "overdue" => 0 
        ],
        "billing_day" => intval($settings["billing_day"] ?? 1),
        "due_date_text" => "กำหนดชำระ: " . ($settings["billing_day"] ?? 5) . " ของเดือน",
        "breakdown" => [
            "rent" => $expected,
            "utility" => 0, // ปรับแต่งเพิ่มตามต้องการ
            "common" => 0
        ]
    ]);
}

jexit(["success"=>false,"message"=>"Unknown action"], 400);