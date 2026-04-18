<?php
ini_set('display_errors', '0');
ini_set('html_errors', '0');
error_reporting(E_ALL);

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

register_shutdown_function(function () {
    $e = error_get_last();
    if ($e && in_array($e['type'], [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR])) {
        if (!headers_sent()) {
            header('Content-Type: application/json; charset=utf-8');
            http_response_code(500);
        }
        echo json_encode([
            'ok' => false,
            'message' => 'PHP Fatal: ' . $e['message']
        ], JSON_UNESCAPED_UNICODE);
    }
});

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once __DIR__ . '/db.php';
mysqli_set_charset($conn, 'utf8mb4');
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

function respond_ok(array $data = [], int $code = 200): void {
    http_response_code($code);
    echo json_encode(array_merge(['ok' => true, 'success' => true], $data), JSON_UNESCAPED_UNICODE);
    exit;
}

function respond_fail(string $message, int $code = 400): void {
    http_response_code($code);
    echo json_encode(['ok' => false, 'message' => $message], JSON_UNESCAPED_UNICODE);
    exit;
}

function param(string $key, $default = null) {
    return $_POST[$key] ?? $_GET[$key] ?? $default;
}

function has_column(mysqli $conn, string $table, string $column): bool {
    $table = $conn->real_escape_string($table);
    $column = $conn->real_escape_string($column);
    $res = $conn->query("SHOW COLUMNS FROM `$table` LIKE '$column'");
    return $res && $res->num_rows > 0;
}

function slips_file_path(): string {
    return __DIR__ . '/payment_slips.json';
}

function load_slip_map(): array {
    $file = slips_file_path();
    if (!file_exists($file)) return [];
    $txt = @file_get_contents($file);
    $arr = json_decode($txt, true);
    return is_array($arr) ? $arr : [];
}

function get_slip_path_for_payment(int $paymentId): ?string {
    $map = load_slip_map();
    if (isset($map[$paymentId]['path']) && is_string($map[$paymentId]['path'])) {
        return $map[$paymentId]['path'];
    }
    return null;
}

function due_date_str($year, $month, $billing_day): string {
    $lastDay = cal_days_in_month(CAL_GREGORIAN, max(1, min(12, intval($month))), intval($year));
    $day = max(1, min($lastDay, intval($billing_day)));
    return sprintf('%04d-%02d-%02d', intval($year), intval($month), $day);
}

function map_status($payment_status, $month, $year, $hasTenant, $billing_day = 5): array {
    if (!$hasTenant) {
        return ["key" => "no_tenant", "label" => "ห้องว่าง", "color" => "#9E9E9E"];
    }

    $ps = strtolower(trim((string)$payment_status));
    if ($ps === 'verified' || $ps === 'paid') {
        return ["key" => "paid", "label" => "ชำระแล้ว", "color" => "#4CAF50"];
    }

    $due = due_date_str($year, $month, $billing_day) . ' 23:59:59';
    if (strtotime(date('Y-m-d H:i:s')) > strtotime($due)) {
        return ["key" => "overdue", "label" => "เลยกำหนด", "color" => "#FF9800"];
    }

    return ["key" => "unpaid", "label" => "ค้างชำระ", "color" => "#F44336"];
}

function getDormSettings(mysqli $conn, int $dorm_id): array {
    $st = $conn->prepare("SELECT water_rate, electric_rate FROM rh_dorm_settings WHERE dorm_id=? LIMIT 1");
    $st->bind_param("i", $dorm_id);
    $st->execute();
    $row = $st->get_result()->fetch_assoc() ?: [];
    $st->close();

    return [
        "water_rate" => floatval($row['water_rate'] ?? 0),
        "electric_rate" => floatval($row['electric_rate'] ?? 0),
        "billing_day" => 5
    ];
}

function calc_bill_parts($baseRent, $waterOld, $waterNew, $elecOld, $elecNew, $waterRate, $electricRate): array {
    $waterUnit = max(0, intval($waterNew) - intval($waterOld));
    $elecUnit = max(0, intval($elecNew) - intval($elecOld));
    $waterBill = $waterUnit * floatval($waterRate);
    $elecBill = $elecUnit * floatval($electricRate);
    $utilityTotal = $waterBill + $elecBill;
    $commonFee = 0.0;
    $total = floatval($baseRent) + $utilityTotal + $commonFee;

    return [
        'rent' => floatval($baseRent),
        'water_unit' => $waterUnit,
        'elec_unit' => $elecUnit,
        'water_bill' => $waterBill,
        'elec_bill' => $elecBill,
        'utility_total' => $utilityTotal,
        'common_fee' => $commonFee,
        'total' => $total,
    ];
}

function latest_meter_join_sql(): string {
    return "
        LEFT JOIN rh_meter m
               ON m.reading_id = (
                    SELECT mm.reading_id
                    FROM rh_meter mm
                    WHERE mm.dorm_id = r.dorm_id
                      AND mm.room_id = r.room_id
                      AND (
                            (mm.year = ? AND mm.month = ?)
                            OR ((mm.year * 100 + mm.month) <= (? * 100 + ?))
                          )
                    ORDER BY
                        CASE WHEN mm.year = ? AND mm.month = ? THEN 0 ELSE 1 END,
                        mm.year DESC, mm.month DESC
                    LIMIT 1
               )
    ";
}

$action = (string)param('action', 'list');

if ($action === 'getPaymentById') {
    $payment_id = intval(param('payment_id', 0));
    if ($payment_id <= 0) respond_fail('ไม่พบ payment_id');

    $hasSlipColumn = has_column($conn, 'rh_payments', 'slip_image');
    $hasPaymentDateColumn = has_column($conn, 'rh_payments', 'payment_date');

    $selectSlip = $hasSlipColumn ? 'p.slip_image,' : 'NULL AS slip_image,';
    $selectPayDate = $hasPaymentDateColumn ? 'p.payment_date,' : 'NULL AS payment_date,';

    $st = $conn->prepare("
        SELECT
            p.payment_id,
            p.user_id,
            p.dorm_id,
            p.room_id,
            p.month,
            p.year,
            p.total_amount,
            p.status,
            $selectSlip
            $selectPayDate
            p.room_id AS payment_room_id
        FROM rh_payments p
        WHERE p.payment_id=?
        LIMIT 1
    ");
    $st->bind_param('i', $payment_id);
    $st->execute();
    $payment = $st->get_result()->fetch_assoc();
    $st->close();

    if (!$payment) respond_fail('ไม่พบบิล');

    $dorm_id = intval($payment['dorm_id']);
    $room_id = intval($payment['room_id']);
    $month = intval($payment['month']);
    $year = intval($payment['year']);

    $settings = getDormSettings($conn, $dorm_id);

    $sql = "
        SELECT
            r.room_id,
            r.dorm_id,
            r.room_number,
            r.floor,
            r.base_rent,
            r.tenant_id,
            b.building_name,
            u.full_name,
            u.phone,
            p.payment_id,
            p.status AS payment_status,
            p.total_amount,
            " . ($hasSlipColumn ? "p.slip_image," : "NULL AS slip_image,") . "
            " . ($hasPaymentDateColumn ? "p.payment_date," : "NULL AS payment_date,") . "
            m.water_old,
            m.water_new,
            m.elec_old,
            m.elec_new
        FROM rh_rooms r
        LEFT JOIN rh_buildings b ON b.building_id = r.building_id
        LEFT JOIN rh_users u ON u.user_id = r.tenant_id
        LEFT JOIN rh_payments p
               ON p.dorm_id = r.dorm_id
              AND p.room_id = r.room_id
              AND p.month = ?
              AND p.year = ?
        " . latest_meter_join_sql() . "
        WHERE r.dorm_id = ?
          AND r.room_id = ?
        LIMIT 1
    ";

    $stmt = $conn->prepare($sql);
    $stmt->bind_param(
        'iiiiiiiiii',
        $month, $year,
        $year, $month,
        $year, $month,
        $year, $month,
        $dorm_id, $room_id
    );
    $stmt->execute();
    $row = $stmt->get_result()->fetch_assoc();
    $stmt->close();

    if (!$row) respond_fail('ไม่พบข้อมูลบิล');

    $parts = calc_bill_parts(
        $row['base_rent'] ?? 0,
        $row['water_old'] ?? 0,
        $row['water_new'] ?? 0,
        $row['elec_old'] ?? 0,
        $row['elec_new'] ?? 0,
        $settings['water_rate'],
        $settings['electric_rate']
    );

    $hasTenant = !empty($row['tenant_id']);
    $stt = map_status($row['payment_status'] ?? '', $month, $year, $hasTenant, $settings['billing_day']);

    $slipImage = !empty($row['slip_image'])
        ? (string)$row['slip_image']
        : get_slip_path_for_payment((int)($row['payment_id'] ?? $payment_id));

    $payDate = $row['payment_date'] ?? null;

    respond_ok([
        'data' => [
            'payment_id' => intval($row['payment_id'] ?? 0),
            'room_id' => intval($row['room_id']),
            'dorm_id' => intval($row['dorm_id']),
            'room_number' => (string)($row['room_number'] ?? ''),
            'building' => (string)($row['building_name'] ?? ''),
            'floor' => intval($row['floor'] ?? 0),
            'tenant_id' => empty($row['tenant_id']) ? null : intval($row['tenant_id']),
            'full_name' => $row['full_name'] ?? null,
            'phone' => $row['phone'] ?? null,
            'month' => $month,
            'year' => $year,
            'due_date' => due_date_str($year, $month, $settings['billing_day']),
            'payment_status' => (string)($row['payment_status'] ?? 'pending'),
            'status_key' => $stt['key'],
            'status_label' => $stt['label'],
            'status_color' => $stt['color'],
            'rent' => $parts['rent'],
            'utility_total' => $parts['utility_total'],
            'common_fee' => $parts['common_fee'],
            'total' => floatval($row['total_amount'] ?? $parts['total']),
            'slip_image' => $slipImage,
            'pay_date' => $payDate,
            'water_bill' => $parts['water_bill'],
            'elec_bill' => $parts['elec_bill'],
            'water_unit' => $parts['water_unit'],
            'water_price_per_unit' => floatval($settings['water_rate']),
            'elec_unit' => $parts['elec_unit'],
            'elec_price_per_unit' => floatval($settings['electric_rate']),
        ]
    ]);
}

if ($action === 'bulk_send') {
    $dorm_id = intval(param('dorm_id'));
    $month = intval(param('month')) ?: intval(date('n'));
    $year = intval(param('year')) ?: intval(date('Y'));

    if ($dorm_id <= 0) respond_fail('dorm_id ไม่ถูกต้อง');

    $settings = getDormSettings($conn, $dorm_id);

    $sqlRooms = "
        SELECT r.room_id, r.room_number, r.base_rent, r.tenant_id
        FROM rh_rooms r
        WHERE r.dorm_id = ?
          AND r.tenant_id IS NOT NULL
          AND r.status = 'occupied'
        ORDER BY r.room_number ASC
    ";
    $stR = $conn->prepare($sqlRooms);
    $stR->bind_param('i', $dorm_id);
    $stR->execute();
    $rooms = $stR->get_result();

    if ($rooms->num_rows === 0) {
        $stR->close();
        respond_fail('ไม่พบห้องที่มีผู้เช่าอยู่');
    }

    $created = 0;
    $skipped = 0;

    while ($r = $rooms->fetch_assoc()) {
        $room_id = intval($r['room_id']);
        $user_id = intval($r['tenant_id']);
        $baseRent = floatval($r['base_rent']);

        $check = $conn->prepare("SELECT payment_id FROM rh_payments WHERE dorm_id=? AND room_id=? AND user_id=? AND month=? AND year=? LIMIT 1");
        $check->bind_param('iiiii', $dorm_id, $room_id, $user_id, $month, $year);
        $check->execute();
        $exists = $check->get_result()->fetch_assoc();
        $check->close();

        if ($exists) {
            $skipped++;
            continue;
        }

        $stM = $conn->prepare("
            SELECT water_old, water_new, elec_old, elec_new
            FROM rh_meter
            WHERE dorm_id=? AND room_id=? AND month=? AND year=?
            LIMIT 1
        ");
        $stM->bind_param('iiii', $dorm_id, $room_id, $month, $year);
        $stM->execute();
        $m = $stM->get_result()->fetch_assoc() ?: [];
        $stM->close();

        $parts = calc_bill_parts(
            $baseRent,
            $m['water_old'] ?? 0,
            $m['water_new'] ?? 0,
            $m['elec_old'] ?? 0,
            $m['elec_new'] ?? 0,
            $settings['water_rate'],
            $settings['electric_rate']
        );

        $ins = $conn->prepare("
            INSERT INTO rh_payments (user_id, dorm_id, room_id, month, year, total_amount, status)
            VALUES (?, ?, ?, ?, ?, ?, 'pending')
        ");
        $ins->bind_param('iiiiid', $user_id, $dorm_id, $room_id, $month, $year, $parts['total']);
        $ins->execute();
        $paymentId = (int)$ins->insert_id;
        $ins->close();

        $created++;

        $message = 'บิลเดือน ' . sprintf('%02d/%04d', $month, $year) . ' ยอดรวม ' . number_format($parts['total'], 2) . ' บาท';
        $noti = $conn->prepare("INSERT INTO rh_notifications (user_id, dorm_id, type_id, ref_id, message, is_read) VALUES (?, ?, 2, ?, ?, 0)");
        $noti->bind_param('iiis', $user_id, $dorm_id, $paymentId, $message);
        $noti->execute();
        $noti->close();
    }

    $stR->close();
    respond_ok([
        'message' => "ส่งบิลสำเร็จ {$created} ห้อง",
        'created' => $created,
        'skipped' => $skipped,
    ]);
}

if ($action === 'list') {
    $dorm_id = intval(param('dorm_id'));
    $month = intval(param('month', date('n')));
    $year = intval(param('year', date('Y')));
    $statusFilter = trim((string)param('status', 'all'));

    if ($dorm_id <= 0) respond_fail('ระบุ dorm_id');

    $hasSlipColumn = has_column($conn, 'rh_payments', 'slip_image');
    $hasPaymentDateColumn = has_column($conn, 'rh_payments', 'payment_date');

    $settings = getDormSettings($conn, $dorm_id);

    $sql = "
        SELECT
            r.room_id,
            r.dorm_id,
            r.room_number,
            r.floor,
            r.base_rent,
            r.tenant_id,
            b.building_name,
            u.full_name,
            u.phone,
            p.payment_id,
            p.status AS payment_status,
            p.total_amount,
            " . ($hasSlipColumn ? "p.slip_image," : "NULL AS slip_image,") . "
            " . ($hasPaymentDateColumn ? "p.payment_date," : "NULL AS payment_date,") . "
            m.water_old,
            m.water_new,
            m.elec_old,
            m.elec_new
        FROM rh_rooms r
        LEFT JOIN rh_buildings b ON b.building_id = r.building_id
        LEFT JOIN rh_users u ON u.user_id = r.tenant_id
        LEFT JOIN rh_payments p
               ON p.dorm_id = r.dorm_id
              AND p.room_id = r.room_id
              AND p.month = ?
              AND p.year = ?
        " . latest_meter_join_sql() . "
        WHERE r.dorm_id = ?
        ORDER BY COALESCE(b.building_name, ''), r.floor ASC, r.room_number ASC
    ";

    $stmt = $conn->prepare($sql);
    $stmt->bind_param(
        'iiiiiiiii',
        $month, $year,
        $year, $month,
        $year, $month,
        $year, $month,
        $dorm_id
    );
    $stmt->execute();
    $res = $stmt->get_result();

    $rows = [];
    while ($row = $res->fetch_assoc()) {
        $parts = calc_bill_parts(
            $row['base_rent'] ?? 0,
            $row['water_old'] ?? 0,
            $row['water_new'] ?? 0,
            $row['elec_old'] ?? 0,
            $row['elec_new'] ?? 0,
            $settings['water_rate'],
            $settings['electric_rate']
        );

        $hasTenant = !empty($row['tenant_id']);
        $stt = map_status($row['payment_status'] ?? '', $month, $year, $hasTenant, $settings['billing_day']);

        if ($statusFilter !== 'all' && $statusFilter !== '' && $stt['key'] !== $statusFilter) {
            continue;
        }

        $slipImage = !empty($row['slip_image'])
            ? (string)$row['slip_image']
            : (!empty($row['payment_id']) ? get_slip_path_for_payment((int)$row['payment_id']) : null);

        $payDate = $row['payment_date'] ?? null;

        $rows[] = [
            'room_id' => intval($row['room_id']),
            'dorm_id' => intval($row['dorm_id']),
            'room_number' => (string)($row['room_number'] ?? ''),
            'building' => (string)($row['building_name'] ?? 'A'),
            'floor' => intval($row['floor'] ?? 0),
            'tenant_id' => empty($row['tenant_id']) ? null : intval($row['tenant_id']),
            'full_name' => $row['full_name'] ?? null,
            'phone' => $row['phone'] ?? null,
            'month' => $month,
            'year' => $year,
            'due_date' => due_date_str($year, $month, $settings['billing_day']),
            'payment_id' => empty($row['payment_id']) ? null : intval($row['payment_id']),
            'payment_status' => (string)($row['payment_status'] ?? 'pending'),
            'status_key' => $stt['key'],
            'status_label' => $stt['label'],
            'status_color' => $stt['color'],
            'rent' => $parts['rent'],
            'utility_total' => $parts['utility_total'],
            'common_fee' => $parts['common_fee'],
            'total' => floatval($row['total_amount'] ?? $parts['total']),
            'slip_image' => $slipImage,
            'pay_date' => $payDate,
            'water_bill' => $parts['water_bill'],
            'elec_bill' => $parts['elec_bill'],
            'water_unit' => $parts['water_unit'],
            'water_price_per_unit' => floatval($settings['water_rate']),
            'elec_unit' => $parts['elec_unit'],
            'elec_price_per_unit' => floatval($settings['electric_rate']),
        ];
    }
    $stmt->close();

    respond_ok(['data' => $rows]);
}

if ($action === 'set_status') {
    $dorm_id = intval(param('dorm_id'));
    $room_id = intval(param('room_id'));
    $month = intval(param('month'));
    $year = intval(param('year'));
    $status_key = trim((string)param('status_key'));

    if ($dorm_id <= 0 || $room_id <= 0 || $month <= 0 || $year <= 0) {
        respond_fail('ข้อมูลไม่ครบ');
    }

    $statusMap = [
        'paid' => 'verified',
        'unpaid' => 'pending',
        'overdue' => 'pending',
        'no_tenant' => 'pending',
    ];
    $newStatus = $statusMap[$status_key] ?? 'pending';

    $st = $conn->prepare("SELECT payment_id, user_id FROM rh_payments WHERE dorm_id=? AND room_id=? AND month=? AND year=? ORDER BY payment_id DESC LIMIT 1");
    $st->bind_param('iiii', $dorm_id, $room_id, $month, $year);
    $st->execute();
    $payment = $st->get_result()->fetch_assoc();
    $st->close();

    if (!$payment) respond_fail('ไม่พบบิล');

    $up = $conn->prepare("UPDATE rh_payments SET status=? WHERE payment_id=?");
    $up->bind_param('si', $newStatus, $payment['payment_id']);
    if (!$up->execute()) {
        $up->close();
        respond_fail('อัปเดตไม่สำเร็จ');
    }
    $up->close();

    if (!empty($payment['user_id'])) {
        $message = ($newStatus === 'verified')
            ? 'บิลเดือน ' . sprintf('%02d/%04d', $month, $year) . ' ได้รับการยืนยันแล้ว'
            : 'บิลเดือน ' . sprintf('%02d/%04d', $month, $year) . ' ถูกปรับสถานะเป็นค้างชำระ';
        $paymentIdForNoti = (int)$payment['payment_id'];
        $noti = $conn->prepare("INSERT INTO rh_notifications (user_id, dorm_id, type_id, ref_id, message, is_read) VALUES (?, ?, 2, ?, ?, 0)");
        $noti->bind_param('iiis', $payment['user_id'], $dorm_id, $paymentIdForNoti, $message);
        $noti->execute();
        $noti->close();
    }

    respond_ok(['message' => 'อัปเดตสำเร็จ ✅']);
}

respond_fail('ไม่พบ Action');