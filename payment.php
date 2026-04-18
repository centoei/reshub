<?php
header("Content-Type: application/json; charset=utf-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit; }

ini_set('display_errors', '0');
ini_set('log_errors', '1');
error_reporting(E_ALL);

function p_jexit($arr, $code = 200) {
    http_response_code($code);
    echo json_encode($arr, JSON_UNESCAPED_UNICODE);
    exit;
}

function post($k, $d = "") {
    if (isset($_POST[$k])) return $_POST[$k];
    if (isset($_GET[$k])) return $_GET[$k];
    static $json = null;
    if ($json === null) {
        $raw = file_get_contents("php://input");
        $json = json_decode($raw, true);
        if (!is_array($json)) $json = [];
    }
    return isset($json[$k]) ? $json[$k] : $d;
}

function has_column(mysqli $conn, $table, $column) {
    $table = $conn->real_escape_string($table);
    $column = $conn->real_escape_string($column);
    $sql = "SHOW COLUMNS FROM `$table` LIKE '$column'";
    $res = $conn->query($sql);
    return $res && $res->num_rows > 0;
}

function slips_file_path() {
    return __DIR__ . '/payment_slips.json';
}

function load_slip_map() {
    $file = slips_file_path();
    if (!file_exists($file)) return [];
    $txt = @file_get_contents($file);
    $arr = json_decode($txt, true);
    return is_array($arr) ? $arr : [];
}

function save_slip_map($map) {
    @file_put_contents(slips_file_path(), json_encode($map, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
}

function get_slip_path_for_payment($paymentId) {
    $map = load_slip_map();
    if (isset($map[$paymentId]['path']) && is_string($map[$paymentId]['path'])) {
        return $map[$paymentId]['path'];
    }
    return null;
}

function set_slip_path_for_payment($paymentId, $path) {
    $map = load_slip_map();
    $map[$paymentId] = [
        'path' => $path,
        'updated_at' => date('c'),
    ];
    save_slip_map($map);
}

function delete_slip_path_for_payment($paymentId) {
    $map = load_slip_map();
    $old = null;
    if (isset($map[$paymentId]['path'])) $old = $map[$paymentId]['path'];
    unset($map[$paymentId]);
    save_slip_map($map);
    return $old;
}

function notify_dorm_admins(mysqli $conn, $dormId, $message, $typeId = 2, $refId = 0) {
    $sql = "SELECT user_id FROM rh_dorm_memberships WHERE dorm_id = ? AND approve_status = 'approved' AND role_code IN ('a','o')";
    $st = $conn->prepare($sql);
    if (!$st) return;
    $st->bind_param('i', $dormId);
    $st->execute();
    $res = $st->get_result();
    $ins = $conn->prepare("INSERT INTO rh_notifications (user_id, dorm_id, type_id, ref_id, message, is_read) VALUES (?, ?, ?, ?, ?, 0)");
    if ($ins) {
        while ($row = $res->fetch_assoc()) {
            $uid = (int)$row['user_id'];
            $ins->bind_param('iiiis', $uid, $dormId, $typeId, $refId, $message);
            $ins->execute();
        }
        $ins->close();
    }
    $st->close();
}

function find_user_room(mysqli $conn, int $user_id): ?array {
    $st = $conn->prepare("SELECT room_id, dorm_id, room_number FROM rh_rooms WHERE tenant_id = ? ORDER BY room_id DESC LIMIT 1");
    if (!$st) return null;
    $st->bind_param('i', $user_id);
    $st->execute();
    $row = $st->get_result()->fetch_assoc();
    $st->close();
    if ($row) return $row;

    $st2 = $conn->prepare("SELECT m.dorm_id, r.room_id, r.room_number
                           FROM rh_dorm_memberships m
                           LEFT JOIN rh_rooms r ON r.tenant_id = m.user_id AND r.dorm_id = m.dorm_id
                           WHERE m.user_id = ? AND m.approve_status = 'approved'
                           ORDER BY r.room_id DESC, m.membership_id DESC
                           LIMIT 1");
    if (!$st2) return null;
    $st2->bind_param('i', $user_id);
    $st2->execute();
    $row2 = $st2->get_result()->fetch_assoc();
    $st2->close();
    return $row2 ?: null;
}

try {
    require_once 'db.php';
    mysqli_set_charset($conn, 'utf8mb4');

    $action = trim((string)post('action', ''));
    if ($action === '') p_jexit(['success' => false, 'message' => 'Missing action'], 400);

    $hasSlipColumn = has_column($conn, 'rh_payments', 'slip_image');
    $hasPaymentDateColumn = has_column($conn, 'rh_payments', 'payment_date');

    if ($action === 'get') {
        $user_id = intval(post('user_id', 0));
        $month   = intval(post('month', 0));
        $year    = intval(post('year', 0));

        if ($user_id <= 0 || $month <= 0 || $year <= 0) {
            p_jexit(['success' => false, 'message' => 'ข้อมูลไม่ครบ'], 400);
        }

        $room = find_user_room($conn, $user_id);
        if (!$room || empty($room['room_id']) || empty($room['dorm_id'])) {
            p_jexit(['success' => false, 'message' => 'คุณยังไม่ได้ผูกห้องพักในหอนี้', 'debug' => ['user_id' => $user_id]]);
        }

        $dorm_id = (int)$room['dorm_id'];
        $room_id = (int)$room['room_id'];
        $room_number = (string)($room['room_number'] ?? '-');

        $accounts = [];
        $stB = $conn->prepare("SELECT bank_name, account_name, account_no FROM rh_bank_accounts WHERE dorm_id = ? ORDER BY bank_id ASC");
        $stB->bind_param('i', $dorm_id);
        $stB->execute();
        $resB = $stB->get_result();
        while ($b = $resB->fetch_assoc()) $accounts[] = $b;
        $stB->close();

        $selectSlip = $hasSlipColumn ? 'p.slip_image,' : 'NULL AS slip_image,';
        $sql = "SELECT
                    p.payment_id,
                    p.user_id,
                    p.room_id,
                    p.total_amount,
                    p.status,
                    $selectSlip
                    COALESCE(met.water_old, 0) AS water_old,
                    COALESCE(met.water_new, 0) AS water_new,
                    COALESCE(met.elec_old, 0) AS elec_old,
                    COALESCE(met.elec_new, 0) AS elec_new,
                    COALESCE(s.water_rate, 0) AS water_rate,
                    COALESCE(s.electric_rate, 0) AS electric_rate
                FROM rh_payments p
                LEFT JOIN rh_meter met ON met.room_id = p.room_id AND met.month = p.month AND met.year = p.year
                LEFT JOIN rh_dorm_settings s ON s.dorm_id = p.dorm_id
                WHERE p.month = ?
                  AND p.year = ?
                  AND (
                        (p.user_id = ?)
                        OR (p.room_id = ?)
                      )
                ORDER BY CASE WHEN p.user_id = ? THEN 0 ELSE 1 END, p.payment_id DESC
                LIMIT 1";
        $st = $conn->prepare($sql);
        $st->bind_param('iiiii', $month, $year, $user_id, $room_id, $user_id);
        $st->execute();
        $p = $st->get_result()->fetch_assoc();
        $st->close();

        if (!$p) {
            p_jexit([
                'success' => false,
                'message' => "ยังไม่มีบิลสำหรับเดือน $month/$year",
                'room_number' => $room_number,
                'accounts' => $accounts,
                'debug' => [
                    'user_id' => $user_id,
                    'room_id' => $room_id,
                    'dorm_id' => $dorm_id,
                    'month' => $month,
                    'year' => $year,
                ]
            ]);
        }

        $waterUnit = max(0, (float)$p['water_new'] - (float)$p['water_old']);
        $elecUnit = max(0, (float)$p['elec_new'] - (float)$p['elec_old']);

        $slip_image = !empty($p['slip_image']) ? $p['slip_image'] : get_slip_path_for_payment((int)$p['payment_id']);

        $rawStatus = strtolower(trim((string)$p['status']));
        if ($rawStatus === 'verified') {
            $uiStatus = 'paid';
        } elseif ($rawStatus === 'pending') {
            $uiStatus = $slip_image ? 'pending' : 'unpaid';
        } else {
            $uiStatus = 'unpaid';
        }

        p_jexit([
            'success' => true,
            'data' => [
                'payment_id'     => (int)$p['payment_id'],
                'room_number'    => $room_number,
                'water_unit'     => $waterUnit,
                'water_rate'     => (float)$p['water_rate'],
                'water_price'    => $waterUnit * (float)$p['water_rate'],
                'electric_unit'  => $elecUnit,
                'electric_rate'  => (float)$p['electric_rate'],
                'electric_price' => $elecUnit * (float)$p['electric_rate'],
                'total_price'    => (float)$p['total_amount'],
                'status'         => $uiStatus,
                'slip_image'     => $slip_image,
                'accounts'       => $accounts,
            ],
            'debug' => [
                'user_id' => $user_id,
                'room_id' => $room_id,
                'dorm_id' => $dorm_id,
                'payment_user_id' => (int)($p['user_id'] ?? 0),
                'payment_room_id' => (int)($p['room_id'] ?? 0),
            ]
        ]);
    }

    if ($action === 'pay') {
        $user_id = intval(post('user_id', 0));
        $payment_id = intval(post('payment_id', 0));
        if ($payment_id <= 0) p_jexit(['success' => false, 'message' => 'ไม่พบ payment_id'], 400);
        if (!isset($_FILES['slip'])) p_jexit(['success' => false, 'message' => 'กรุณาแนบไฟล์สลิป'], 400);

        $stC = $conn->prepare("SELECT p.payment_id, p.dorm_id, p.room_id, r.room_number
                               FROM rh_payments p
                               JOIN rh_rooms r ON r.room_id = p.room_id
                               WHERE p.payment_id = ?
                                 AND (p.user_id = ? OR r.tenant_id = ?)
                               LIMIT 1");
        $stC->bind_param('iii', $payment_id, $user_id, $user_id);
        $stC->execute();
        $info = $stC->get_result()->fetch_assoc();
        $stC->close();

        if (!$info) p_jexit(['success' => false, 'message' => 'ไม่พบข้อมูลบิลของผู้ใช้คนนี้'], 404);

        $uploadDirRel = 'uploads/slips/';
        $uploadDirAbs = __DIR__ . '/' . $uploadDirRel;
        if (!is_dir($uploadDirAbs)) @mkdir($uploadDirAbs, 0755, true);

        $ext = strtolower(pathinfo($_FILES['slip']['name'] ?? '', PATHINFO_EXTENSION));
        if ($ext === '') $ext = 'jpg';
        $newName = 'slip_' . $payment_id . '_' . time() . '.' . preg_replace('/[^a-z0-9]/i', '', $ext);
        $pathRel = $uploadDirRel . $newName;
        $pathAbs = __DIR__ . '/' . $pathRel;

        if (!move_uploaded_file($_FILES['slip']['tmp_name'], $pathAbs)) {
            p_jexit(['success' => false, 'message' => 'ไม่สามารถอัปโหลดไฟล์ได้'], 500);
        }

        $oldPath = get_slip_path_for_payment($payment_id);
        if ($oldPath && file_exists(__DIR__ . '/' . $oldPath)) @unlink(__DIR__ . '/' . $oldPath);
        set_slip_path_for_payment($payment_id, $pathRel);

        if ($hasSlipColumn && $hasPaymentDateColumn) {
            $stU = $conn->prepare("UPDATE rh_payments SET slip_image = ?, status = 'pending', payment_date = NOW() WHERE payment_id = ?");
            $stU->bind_param('si', $pathRel, $payment_id);
            $stU->execute();
            $stU->close();
        } elseif ($hasSlipColumn) {
            $stU = $conn->prepare("UPDATE rh_payments SET slip_image = ?, status = 'pending' WHERE payment_id = ?");
            $stU->bind_param('si', $pathRel, $payment_id);
            $stU->execute();
            $stU->close();
        } else {
            $stU = $conn->prepare("UPDATE rh_payments SET status = 'pending' WHERE payment_id = ?");
            $stU->bind_param('i', $payment_id);
            $stU->execute();
            $stU->close();
        }

        notify_dorm_admins($conn, (int)$info['dorm_id'], 'ห้อง ' . $info['room_number'] . ' แจ้งชำระเงินแล้ว', 2, $payment_id);

        p_jexit(['success' => true, 'message' => 'ส่งหลักฐานการชำระเงินเรียบร้อย', 'slip_image' => $pathRel]);
    }

    if ($action === 'delete_slip') {
        $payment_id = intval(post('payment_id', 0));
        $user_id = intval(post('user_id', 0));
        if ($payment_id <= 0) p_jexit(['success' => false, 'message' => 'ไม่พบ payment_id'], 400);

        $st = $conn->prepare("SELECT p.payment_id, p.status, p.dorm_id
                              FROM rh_payments p
                              JOIN rh_rooms r ON r.room_id = p.room_id
                              WHERE p.payment_id = ?
                                AND (p.user_id = ? OR r.tenant_id = ?)
                              LIMIT 1");
        $st->bind_param('iii', $payment_id, $user_id, $user_id);
        $st->execute();
        $info = $st->get_result()->fetch_assoc();
        $st->close();

        if (!$info) p_jexit(['success' => false, 'message' => 'ไม่พบข้อมูลบิล'], 404);

        $old = delete_slip_path_for_payment($payment_id);
        if ($old && file_exists(__DIR__ . '/' . $old)) @unlink(__DIR__ . '/' . $old);

        if ($hasSlipColumn) {
            $stU = $conn->prepare("UPDATE rh_payments SET slip_image = NULL, status = 'rejected' WHERE payment_id = ?");
            $stU->bind_param('i', $payment_id);
            $stU->execute();
            $stU->close();
        } else {
            $stU = $conn->prepare("UPDATE rh_payments SET status = 'rejected' WHERE payment_id = ?");
            $stU->bind_param('i', $payment_id);
            $stU->execute();
            $stU->close();
        }

        p_jexit(['success' => true, 'message' => 'ยกเลิกสลิปเรียบร้อย']);
    }

    p_jexit(['success' => false, 'message' => 'Unknown action'], 400);
} catch (Throwable $e) {
    p_jexit(['success' => false, 'message' => 'เกิดข้อผิดพลาด: ' . $e->getMessage()], 500);
}
