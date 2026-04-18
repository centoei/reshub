<?php
header("Content-Type: application/json; charset=utf-8");
include "db.php";

function jsonOut($arr, $code = 200){
    http_response_code($code);
    echo json_encode($arr, JSON_UNESCAPED_UNICODE);
    exit;
}

if (!isset($conn) || !($conn instanceof mysqli)) {
    jsonOut(["ok" => false, "message" => "Database connection fail"], 500);
}
$conn->set_charset("utf8mb4");

const T_DORMS = 'rh_dorms';
const T_SETTINGS = 'rh_dorm_settings';
const T_BUILDINGS = 'rh_buildings';
const T_ROOM_TYPES = 'rh_room_types';
const T_ROOMS = 'rh_rooms';

$raw = file_get_contents("php://input");
$input = json_decode($raw, true);
if (!is_array($input)) $input = [];
$data = array_merge($_GET, $_POST, $input);
$action = trim((string)($data['action'] ?? ''));
$dorm_id = (int)($data['dorm_id'] ?? 0);

function ensureDormSettings(mysqli $conn, int $dorm_id): void {
    $st = $conn->prepare("INSERT IGNORE INTO ".T_SETTINGS." (dorm_id, water_rate, electric_rate) VALUES (?, 0.00, 0.00)");
    $st->bind_param("i", $dorm_id);
    $st->execute();
    $st->close();
}

function findTypeByKeyword(mysqli $conn, int $dorm_id, string $keyword): ?array {
    $kw = "%" . $keyword . "%";
    $st = $conn->prepare(
        "SELECT type_id, type_name, default_rent
         FROM ".T_ROOM_TYPES."
         WHERE dorm_id = ? AND type_name LIKE ?
         ORDER BY type_id ASC
         LIMIT 1"
    );
    $st->bind_param("is", $dorm_id, $kw);
    $st->execute();
    $row = $st->get_result()->fetch_assoc();
    $st->close();
    return $row ?: null;
}

function ensureDefaultRoomTypes(mysqli $conn, int $dorm_id): array {
    $fan = findTypeByKeyword($conn, $dorm_id, 'Fan');
    $air = findTypeByKeyword($conn, $dorm_id, 'Air');

    if (!$fan) {
        $name = 'Standard Fan';
        $rent = 0.00;
        $st = $conn->prepare("INSERT INTO ".T_ROOM_TYPES." (dorm_id, type_name, default_rent) VALUES (?, ?, ?)");
        $st->bind_param("isd", $dorm_id, $name, $rent);
        $st->execute();
        $st->close();
        $fan = findTypeByKeyword($conn, $dorm_id, 'Fan');
    }

    if (!$air) {
        $name = 'Standard Air';
        $rent = 0.00;
        $st = $conn->prepare("INSERT INTO ".T_ROOM_TYPES." (dorm_id, type_name, default_rent) VALUES (?, ?, ?)");
        $st->bind_param("isd", $dorm_id, $name, $rent);
        $st->execute();
        $st->close();
        $air = findTypeByKeyword($conn, $dorm_id, 'Air');
    }

    return [
        'fan' => $fan,
        'air' => $air,
    ];
}

function getSettings(mysqli $conn, int $dorm_id): array {
    ensureDormSettings($conn, $dorm_id);
    $types = ensureDefaultRoomTypes($conn, $dorm_id);

    $st = $conn->prepare("SELECT water_rate, electric_rate FROM ".T_SETTINGS." WHERE dorm_id = ? LIMIT 1");
    $st->bind_param("i", $dorm_id);
    $st->execute();
    $row = $st->get_result()->fetch_assoc() ?: [];
    $st->close();

    return [
        'water_rate' => (float)($row['water_rate'] ?? 0),
        'electric_rate' => (float)($row['electric_rate'] ?? 0),
        'default_rent_fan' => (float)($types['fan']['default_rent'] ?? 0),
        'default_rent_air' => (float)($types['air']['default_rent'] ?? 0),
        'fan_type_id' => (int)($types['fan']['type_id'] ?? 0),
        'air_type_id' => (int)($types['air']['type_id'] ?? 0),
    ];
}

function getSummary(mysqli $conn, int $dorm_id): array {
    $roomSql = "
        SELECT
            COUNT(*) AS total_rooms,
            SUM(CASE WHEN rt.type_name LIKE '%Fan%' THEN 1 ELSE 0 END) AS fan_count,
            SUM(CASE WHEN rt.type_name LIKE '%Air%' THEN 1 ELSE 0 END) AS air_count,
            SUM(CASE WHEN r.status = 'vacant' THEN 1 ELSE 0 END) AS vacant_count
        FROM ".T_ROOMS." r
        LEFT JOIN ".T_ROOM_TYPES." rt ON rt.type_id = r.type_id
        WHERE r.dorm_id = ?
    ";
    $st = $conn->prepare($roomSql);
    $st->bind_param("i", $dorm_id);
    $st->execute();
    $room = $st->get_result()->fetch_assoc() ?: [];
    $st->close();

    $st = $conn->prepare("SELECT COUNT(*) AS building_count FROM ".T_BUILDINGS." WHERE dorm_id = ?");
    $st->bind_param("i", $dorm_id);
    $st->execute();
    $building = $st->get_result()->fetch_assoc() ?: [];
    $st->close();

    return [
        'total_rooms' => (int)($room['total_rooms'] ?? 0),
        'fan_count' => (int)($room['fan_count'] ?? 0),
        'air_count' => (int)($room['air_count'] ?? 0),
        'vacant_count' => (int)($room['vacant_count'] ?? 0),
        'building_count' => (int)($building['building_count'] ?? 0),
    ];
}

function getOrCreateBuilding(mysqli $conn, int $dorm_id, string $building_name): int {
    $st = $conn->prepare("SELECT building_id FROM ".T_BUILDINGS." WHERE dorm_id = ? AND building_name = ? LIMIT 1");
    $st->bind_param("is", $dorm_id, $building_name);
    $st->execute();
    $row = $st->get_result()->fetch_assoc();
    $st->close();
    if ($row) return (int)$row['building_id'];

    $st = $conn->prepare("INSERT INTO ".T_BUILDINGS." (dorm_id, building_name) VALUES (?, ?)");
    $st->bind_param("is", $dorm_id, $building_name);
    $st->execute();
    $id = (int)$conn->insert_id;
    $st->close();
    return $id;
}

function normalizeBuildingNames($rawNames): array {
    if (is_string($rawNames)) {
        $decoded = json_decode($rawNames, true);
        if (is_array($decoded)) $rawNames = $decoded;
    }
    if (!is_array($rawNames)) return [];

    $out = [];
    foreach ($rawNames as $name) {
        $name = trim((string)$name);
        if ($name !== '' && !in_array($name, $out, true)) {
            $out[] = $name;
        }
    }
    return $out;
}

if ($action !== '' && $dorm_id <= 0) {
    jsonOut(["ok" => false, "message" => "จำเป็นต้องระบุ dorm_id"], 400);
}

if ($action === 'get') {
    $st = $conn->prepare("SELECT dorm_id, dorm_name, dorm_address, dorm_phone, dorm_code, status FROM ".T_DORMS." WHERE dorm_id = ? LIMIT 1");
    $st->bind_param("i", $dorm_id);
    $st->execute();
    $dorm = $st->get_result()->fetch_assoc();
    $st->close();

    if (!$dorm) {
        jsonOut(["ok" => false, "message" => "ไม่พบข้อมูลหอพัก"], 404);
    }

    jsonOut([
        'ok' => true,
        'success' => true,
        'dorm' => $dorm,
        'settings' => getSettings($conn, $dorm_id),
        'summary' => getSummary($conn, $dorm_id),
    ]);
}

if ($action === 'update_rent') {
    $rent_fan = (float)($data['rent_fan'] ?? 0);
    $rent_air = (float)($data['rent_air'] ?? 0);
    $types = ensureDefaultRoomTypes($conn, $dorm_id);

    $conn->begin_transaction();
    try {
        if (!empty($types['fan']['type_id'])) {
            $type_id = (int)$types['fan']['type_id'];
            $st = $conn->prepare("UPDATE ".T_ROOM_TYPES." SET default_rent = ? WHERE type_id = ?");
            $st->bind_param("di", $rent_fan, $type_id);
            $st->execute();
            $st->close();

            $st = $conn->prepare("UPDATE ".T_ROOMS." SET base_rent = ? WHERE dorm_id = ? AND type_id = ? AND status = 'vacant'");
            $st->bind_param("dii", $rent_fan, $dorm_id, $type_id);
            $st->execute();
            $st->close();
        }

        if (!empty($types['air']['type_id'])) {
            $type_id = (int)$types['air']['type_id'];
            $st = $conn->prepare("UPDATE ".T_ROOM_TYPES." SET default_rent = ? WHERE type_id = ?");
            $st->bind_param("di", $rent_air, $type_id);
            $st->execute();
            $st->close();

            $st = $conn->prepare("UPDATE ".T_ROOMS." SET base_rent = ? WHERE dorm_id = ? AND type_id = ? AND status = 'vacant'");
            $st->bind_param("dii", $rent_air, $dorm_id, $type_id);
            $st->execute();
            $st->close();
        }

        $conn->commit();
        jsonOut([
            'ok' => true,
            'message' => 'บันทึกราคาเรียบร้อย',
            'settings' => getSettings($conn, $dorm_id),
            'summary' => getSummary($conn, $dorm_id),
        ]);
    } catch (Throwable $e) {
        $conn->rollback();
        jsonOut(['ok' => false, 'message' => 'บันทึกราคาไม่สำเร็จ: '.$e->getMessage()], 500);
    }
}

if ($action === 'update_rates') {
    $water = (float)($data['water_rate'] ?? 0);
    $electric = (float)($data['electric_rate'] ?? 0);
    ensureDormSettings($conn, $dorm_id);

    $st = $conn->prepare("UPDATE ".T_SETTINGS." SET water_rate = ?, electric_rate = ? WHERE dorm_id = ?");
    $st->bind_param("ddi", $water, $electric, $dorm_id);
    $ok = $st->execute();
    $st->close();

    jsonOut([
        'ok' => $ok,
        'message' => $ok ? 'อัปเดตค่าน้ำค่าไฟเรียบร้อย' : 'ไม่สามารถอัปเดตได้',
        'settings' => getSettings($conn, $dorm_id),
    ], $ok ? 200 : 500);
}

if ($action === 'save') {
    $hasDormFields = array_key_exists('dorm_name', $data) || array_key_exists('dorm_address', $data) || array_key_exists('dorm_phone', $data) || array_key_exists('dorm_code', $data);
    $hasRateFields = array_key_exists('water_rate', $data) || array_key_exists('electric_rate', $data);

    $conn->begin_transaction();
    try {
        if ($hasDormFields) {
            $dorm_name = trim((string)($data['dorm_name'] ?? ''));
            $dorm_address = trim((string)($data['dorm_address'] ?? ''));
            $dorm_phone = trim((string)($data['dorm_phone'] ?? ''));
            $dorm_code = trim((string)($data['dorm_code'] ?? ''));

            if ($dorm_name === '') {
                $st = $conn->prepare("SELECT dorm_name FROM ".T_DORMS." WHERE dorm_id = ? LIMIT 1");
                $st->bind_param("i", $dorm_id);
                $st->execute();
                $row = $st->get_result()->fetch_assoc();
                $st->close();
                $dorm_name = (string)($row['dorm_name'] ?? '');
            }

            $st = $conn->prepare("UPDATE ".T_DORMS." SET dorm_name = ?, dorm_address = ?, dorm_phone = ?, dorm_code = ? WHERE dorm_id = ?");
            $st->bind_param("ssssi", $dorm_name, $dorm_address, $dorm_phone, $dorm_code, $dorm_id);
            $st->execute();
            $st->close();
        }

        if ($hasRateFields) {
            ensureDormSettings($conn, $dorm_id);
            $water = (float)($data['water_rate'] ?? 0);
            $electric = (float)($data['electric_rate'] ?? 0);
            $st = $conn->prepare("UPDATE ".T_SETTINGS." SET water_rate = ?, electric_rate = ? WHERE dorm_id = ?");
            $st->bind_param("ddi", $water, $electric, $dorm_id);
            $st->execute();
            $st->close();
        }

        $conn->commit();
        jsonOut([
            'ok' => true,
            'message' => 'บันทึกข้อมูลสำเร็จ',
            'dorm' => null,
            'settings' => getSettings($conn, $dorm_id),
            'summary' => getSummary($conn, $dorm_id),
        ]);
    } catch (Throwable $e) {
        $conn->rollback();
        jsonOut(['ok' => false, 'message' => 'บันทึกไม่สำเร็จ: '.$e->getMessage()], 500);
    }
}

if ($action === 'generate') {
    $building_names = normalizeBuildingNames($data['building_names'] ?? []);
    $floors = max(1, (int)($data['floors'] ?? 1));
    $rooms_per_floor = max(1, (int)($data['rooms_per_floor'] ?? 1));
    $default_type = strtolower(trim((string)($data['default_type'] ?? 'fan')));
    $types = ensureDefaultRoomTypes($conn, $dorm_id);
    $selectedType = ($default_type === 'air') ? $types['air'] : $types['fan'];
    $type_id = (int)($selectedType['type_id'] ?? 0);
    $base_rent = (float)($selectedType['default_rent'] ?? 0);

    if (empty($building_names)) {
        jsonOut(['ok' => false, 'message' => 'กรุณาระบุชื่อตึกอย่างน้อย 1 ชื่อ'], 400);
    }
    if ($type_id <= 0) {
        jsonOut(['ok' => false, 'message' => 'ไม่พบประเภทห้องเริ่มต้น'], 400);
    }

    $created = 0;
    $conn->begin_transaction();
    try {
        $check = $conn->prepare("SELECT room_id FROM ".T_ROOMS." WHERE dorm_id = ? AND building_id = ? AND room_number = ? LIMIT 1");
        $ins = $conn->prepare("INSERT INTO ".T_ROOMS." (dorm_id, building_id, type_id, room_number, floor, base_rent, status, tenant_id) VALUES (?, ?, ?, ?, ?, ?, 'vacant', NULL)");

        foreach ($building_names as $building_name) {
            $building_id = getOrCreateBuilding($conn, $dorm_id, $building_name);

            for ($floor = 1; $floor <= $floors; $floor++) {
                for ($room = 1; $room <= $rooms_per_floor; $room++) {
                    $room_number = $floor . str_pad((string)$room, 2, '0', STR_PAD_LEFT);

                    $check->bind_param("iis", $dorm_id, $building_id, $room_number);
                    $check->execute();
                    $exists = $check->get_result()->fetch_assoc();
                    if ($exists) {
                        continue;
                    }

                    $ins->bind_param("iiisid", $dorm_id, $building_id, $type_id, $room_number, $floor, $base_rent);
                    $ins->execute();
                    $created++;
                }
            }
        }

        $check->close();
        $ins->close();
        $conn->commit();

        jsonOut([
            'ok' => true,
            'message' => "สร้างห้องพักสำเร็จ {$created} ห้อง",
            'count' => $created,
            'created' => $created,
            'summary' => getSummary($conn, $dorm_id),
            'settings' => getSettings($conn, $dorm_id),
        ]);
    } catch (Throwable $e) {
        $conn->rollback();
        jsonOut(['ok' => false, 'message' => 'ไม่สามารถสร้างห้องได้: '.$e->getMessage()], 500);
    }
}

jsonOut(["ok" => false, "message" => "Action ไม่ถูกต้อง"], 400);
