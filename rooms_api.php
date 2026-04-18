<?php
header("Content-Type: application/json; charset=utf-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(200);
    exit;
}

$host = "localhost";
$user = "root";
$pass = "";
$db   = "reshub";

$conn = new mysqli($host, $user, $pass, $db);
$conn->set_charset("utf8mb4");

function respond_ok($extra = []) {
    echo json_encode(array_merge([
        "ok" => true,
        "success" => true,
    ], $extra), JSON_UNESCAPED_UNICODE);
    exit;
}

function respond_fail($msg, $code = 400, $extra = []) {
    http_response_code($code);
    echo json_encode(array_merge([
        "ok" => false,
        "success" => false,
        "message" => $msg,
    ], $extra), JSON_UNESCAPED_UNICODE);
    exit;
}

if ($conn->connect_error) {
    respond_fail("DB connect fail: " . $conn->connect_error, 500);
}

$raw = file_get_contents("php://input");
$inputJson = null;
$ct = strtolower($_SERVER["CONTENT_TYPE"] ?? "");
if ($raw && strpos($ct, "application/json") !== false) {
    $inputJson = json_decode($raw, true);
    if (!is_array($inputJson)) {
        respond_fail("JSON ไม่ถูกต้อง");
    }
}

$data = array_merge($_GET, $_POST, $inputJson ?? []);
$action = $data["action"] ?? "list";
if ($action === "save") $action = "bulk_update";

$dorm_id = intval($data["dorm_id"] ?? 0);
if ($dorm_id <= 0) respond_fail("missing dorm_id");

function normalize_room_type_name($name) {
    $s = mb_strtolower(trim((string)$name), 'UTF-8');
    if ($s === '') return 'fan';
    if (strpos($s, 'air') !== false || strpos($s, 'แอร์') !== false || strpos($s, 'ac') !== false) return 'air';
    return 'fan';
}

function get_type_id_by_kind($conn, $dorm_id, $kind) {
    $typeRows = [];
    $stmt = $conn->prepare("SELECT type_id, type_name, default_rent FROM rh_room_types WHERE dorm_id=? ORDER BY type_id ASC");
    $stmt->bind_param("i", $dorm_id);
    $stmt->execute();
    $res = $stmt->get_result();
    while ($row = $res->fetch_assoc()) {
        $typeRows[] = $row;
    }

    foreach ($typeRows as $row) {
        if (normalize_room_type_name($row['type_name']) === $kind) {
            return [intval($row['type_id']), floatval($row['default_rent'])];
        }
    }

    if (!empty($typeRows)) {
        return [intval($typeRows[0]['type_id']), floatval($typeRows[0]['default_rent'])];
    }

    return [0, 0.0];
}

if ($action === "defaults") {
    $stmt = $conn->prepare("SELECT type_id, type_name, default_rent FROM rh_room_types WHERE dorm_id=? ORDER BY type_id ASC");
    $stmt->bind_param("i", $dorm_id);
    $stmt->execute();
    $result = $stmt->get_result();

    $fan = 0;
    $air = 0;
    $types = [];

    while ($row = $result->fetch_assoc()) {
        $kind = normalize_room_type_name($row['type_name']);
        $row['kind'] = $kind;
        $row['default_rent'] = floatval($row['default_rent']);
        $types[] = $row;

        if ($kind === 'fan' && $fan <= 0) $fan = intval(round($row['default_rent']));
        if ($kind === 'air' && $air <= 0) $air = intval(round($row['default_rent']));
    }

    respond_ok([
        'settings' => [
            'default_rent_fan' => $fan,
            'default_rent_air' => $air,
        ],
        'types' => $types,
    ]);
}

if ($action === "detail") {
    $room_id = intval($data["room_id"] ?? 0);
    if ($room_id <= 0) respond_fail("missing room_id");

    $sql = "
        SELECT
            r.room_id,
            r.dorm_id,
            r.building_id,
            r.type_id,
            r.room_number,
            r.floor,
            r.base_rent AS rent_price,
            r.status,
            b.building_name AS building,
            rt.type_name AS room_type,
            rt.default_rent,
            u.user_id AS tenant_id,
            'active' AS tenant_status,
            NULL AS start_date,
            u.full_name,
            u.phone
        FROM rh_rooms r
        LEFT JOIN rh_buildings b ON b.building_id = r.building_id
        LEFT JOIN rh_room_types rt ON rt.type_id = r.type_id
        LEFT JOIN rh_users u ON u.user_id = r.tenant_id
        WHERE r.dorm_id=? AND r.room_id=?
        LIMIT 1
    ";

    $stmt = $conn->prepare($sql);
    $stmt->bind_param("ii", $dorm_id, $room_id);
    $stmt->execute();
    $res = $stmt->get_result();
    $row = $res->fetch_assoc();

    if (!$row) respond_fail("not found");
    respond_ok(["data" => $row]);
}

if ($action === "list") {
    $status   = trim($data["status"] ?? "");
    $type     = trim($data["room_type"] ?? "");
    $building = trim($data["building"] ?? "");
    $floor    = intval($data["floor"] ?? 0);

    $sql = "
        SELECT
            r.room_id,
            r.dorm_id,
            r.building_id,
            r.type_id,
            r.room_number,
            r.floor,
            r.base_rent AS rent_price,
            r.status,
            b.building_name AS building,
            rt.type_name AS room_type,
            rt.default_rent,
            u.user_id AS tenant_id,
            CASE WHEN u.user_id IS NOT NULL THEN 'active' ELSE '' END AS tenant_status,
            NULL AS start_date,
            u.full_name,
            u.phone
        FROM rh_rooms r
        LEFT JOIN rh_buildings b ON b.building_id = r.building_id
        LEFT JOIN rh_room_types rt ON rt.type_id = r.type_id
        LEFT JOIN rh_users u ON u.user_id = r.tenant_id
        WHERE r.dorm_id=?
    ";

    $params = [$dorm_id];
    $types  = "i";

    if ($status !== "") {
        $sql .= " AND r.status = ?";
        $params[] = $status;
        $types .= "s";
    }

    if ($type !== "") {
        if (in_array($type, ['fan', 'air'], true)) {
            $sql .= " AND LOWER(rt.type_name) LIKE ?";
            $params[] = '%' . $type . '%';
            $types .= "s";
        } else {
            $sql .= " AND rt.type_name = ?";
            $params[] = $type;
            $types .= "s";
        }
    }

    if ($building !== "") {
        $sql .= " AND b.building_name = ?";
        $params[] = $building;
        $types .= "s";
    }

    if ($floor > 0) {
        $sql .= " AND r.floor = ?";
        $params[] = $floor;
        $types .= "i";
    }

    $sql .= " ORDER BY COALESCE(b.building_name, ''), r.floor ASC, r.room_number ASC";

    $stmt = $conn->prepare($sql);
    $stmt->bind_param($types, ...$params);
    $stmt->execute();
    $result = $stmt->get_result();

    $rows = [];
    while ($row = $result->fetch_assoc()) {
        $rows[] = $row;
    }

    respond_ok(["data" => $rows, "rooms" => $rows]);
}

if ($action === "add") {
    $room_number = trim($data["room_number"] ?? "");
    $building_id = intval($data["building_id"] ?? 0);
    $floor       = intval($data["floor"] ?? 0);
    $room_type   = trim($data["room_type"] ?? "fan");
    $rent_price  = floatval($data["rent_price"] ?? ($data["price"] ?? 0));
    $status      = trim($data["status"] ?? "vacant");

    if ($room_number === "" || $floor <= 0) respond_fail("ข้อมูลไม่ครบ (room_number/floor)");
    if (!in_array($room_type, ["fan", "air"], true)) respond_fail("room_type ไม่ถูกต้อง");
    if (!in_array($status, ["vacant", "occupied", "maintenance"], true)) respond_fail("status ไม่ถูกต้อง");

    list($type_id, $default_rent) = get_type_id_by_kind($conn, $dorm_id, $room_type);
    if ($type_id <= 0) respond_fail("ไม่พบประเภทห้องของหอนี้");
    if ($rent_price <= 0) $rent_price = $default_rent;

    $stmt = $conn->prepare(
        "INSERT INTO rh_rooms (dorm_id, building_id, type_id, room_number, floor, base_rent, status)
         VALUES (?, ?, ?, ?, ?, ?, ?)"
    );
    $stmt->bind_param("iiisids", $dorm_id, $building_id, $type_id, $room_number, $floor, $rent_price, $status);

    if ($stmt->execute()) {
        respond_ok(["message" => "เพิ่มห้องสำเร็จ", "room_id" => $conn->insert_id]);
    }

    respond_fail("เพิ่มไม่สำเร็จ: " . $conn->error);
}

if ($action === "update") {
    $room_id    = intval($data["room_id"] ?? 0);
    $rent_price = floatval($data["rent_price"] ?? ($data["price"] ?? 0));
    $room_type  = trim($data["room_type"] ?? "");
    $status     = trim($data["status"] ?? "");

    if ($room_id <= 0) respond_fail("room_id ไม่ถูกต้อง");
    if (!in_array($room_type, ["fan", "air"], true)) respond_fail("room_type ไม่ถูกต้อง");
    if (!in_array($status, ["vacant", "occupied", "maintenance"], true)) respond_fail("status ไม่ถูกต้อง");

    list($type_id, $default_rent) = get_type_id_by_kind($conn, $dorm_id, $room_type);
    if ($type_id <= 0) respond_fail("ไม่พบประเภทห้องของหอนี้");
    if ($rent_price <= 0) $rent_price = $default_rent;

    $stmt = $conn->prepare(
        "UPDATE rh_rooms
         SET type_id=?, base_rent=?, status=?
         WHERE room_id=? AND dorm_id=?"
    );
    $stmt->bind_param("idsii", $type_id, $rent_price, $status, $room_id, $dorm_id);

    if ($stmt->execute()) {
        respond_ok(["message" => "อัปเดตสำเร็จ"]);
    }

    respond_fail("อัปเดตไม่สำเร็จ: " . $conn->error);
}

if ($action === "bulk_update") {
    $items = $data["items"] ?? [];
    if (!is_array($items)) respond_fail("items ต้องเป็น array");

    $conn->begin_transaction();
    try {
        $stmt = $conn->prepare(
            "UPDATE rh_rooms SET type_id=?, base_rent=?, status=? WHERE room_id=? AND dorm_id=?"
        );
        $updated = 0;

        foreach ($items as $it) {
            $r_id   = intval($it["room_id"] ?? 0);
            $r_type = trim($it["room_type"] ?? "");
            $r_rent = floatval($it["rent_price"] ?? ($it["price"] ?? 0));
            $r_stat = trim($it["status"] ?? "vacant");

            if ($r_id <= 0 || !in_array($r_type, ["fan", "air"], true) || !in_array($r_stat, ["vacant", "occupied", "maintenance"], true)) {
                continue;
            }

            list($type_id, $default_rent) = get_type_id_by_kind($conn, $dorm_id, $r_type);
            if ($type_id <= 0) continue;
            if ($r_rent <= 0) $r_rent = $default_rent;

            $stmt->bind_param("idsii", $type_id, $r_rent, $r_stat, $r_id, $dorm_id);
            $stmt->execute();
            $updated += max(0, $stmt->affected_rows);
        }

        $conn->commit();
        respond_ok(["message" => "bulk_update ok", "updated" => $updated]);
    } catch (Exception $e) {
        $conn->rollback();
        respond_fail("bulk_update fail: " . $e->getMessage());
    }
}

if ($action === "delete") {
    $room_id = intval($data["room_id"] ?? 0);
    if ($room_id <= 0) respond_fail("room_id ไม่ถูกต้อง");

    $stmt = $conn->prepare("DELETE FROM rh_rooms WHERE room_id=? AND dorm_id=?");
    $stmt->bind_param("ii", $room_id, $dorm_id);

    if ($stmt->execute()) {
        if ($stmt->affected_rows > 0) respond_ok(["message" => "ลบสำเร็จ"]);
        respond_fail("ไม่พบห้องนี้ในระบบ");
    }

    respond_fail("ลบไม่สำเร็จ: " . $conn->error);
}

respond_fail("Unknown action: " . $action);
