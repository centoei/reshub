<?php
header("Content-Type: application/json; charset=utf-8");
include "db.php";

$action = $_GET["action"] ?? "";

function out($arr, $code=200){
  http_response_code($code);
  echo json_encode($arr, JSON_UNESCAPED_UNICODE);
  exit;
}
function readJson(){
  $raw = file_get_contents("php://input");
  $data = json_decode($raw, true);
  return is_array($data) ? $data : [];
}

/* =========================
   LIST ROOMS
   ?action=list&dorm_id=1&building=A&floor=1 (optional)
========================= */
if ($action === "list") {
  $dorm_id  = intval($_GET["dorm_id"] ?? 0);
  $building = trim($_GET["building"] ?? "");
  $floor    = intval($_GET["floor"] ?? 0);

  if ($dorm_id <= 0) out(["ok"=>false,"message"=>"invalid dorm_id"], 400);

  $where  = "WHERE dorm_id=?";
  $types  = "i";
  $params = [$dorm_id];

  if ($building !== "") { $where .= " AND building=?"; $types.="s"; $params[] = $building; }
  if ($floor > 0)       { $where .= " AND floor=?";    $types.="i"; $params[] = $floor; }

  $sql = "
    SELECT room_id, dorm_id, room_number, building, floor, room_type, rent_price, status
    FROM rh_rooms
    $where
    ORDER BY building, floor,
      CASE WHEN room_number REGEXP '^[0-9]+$' THEN CAST(room_number AS UNSIGNED) ELSE 999999999 END,
      room_number
  ";

  $st = $conn->prepare($sql);
  $st->bind_param($types, ...$params);
  $st->execute();
  $rs = $st->get_result();

  $rooms = [];
  while ($r = $rs->fetch_assoc()) {
    $rooms[] = [
      "room_id"     => intval($r["room_id"]),
      "room_number" => $r["room_number"],
      "building"    => $r["building"],
      "floor"       => intval($r["floor"]),
      "room_type"   => $r["room_type"],
      "rent_price"  => floatval($r["rent_price"]),
      "status"      => $r["status"],
      "label"       => $r["building"].$r["room_number"], // A101
    ];
  }

  out(["ok"=>true, "rooms"=>$rooms]);
}

/* =========================
   UPDATE ROOMS
   POST JSON -> ?action=save
   {
     dorm_id,
     items: [
       {room_id, room_type, rent_price},
       ...
     ]
   }
========================= */
if ($action === "save") {
  $in      = readJson();
  $dorm_id = intval($in["dorm_id"] ?? 0);
  $items   = $in["items"] ?? [];

  if ($dorm_id<=0 || !is_array($items)) out(["ok"=>false,"message"=>"invalid params"], 400);

  $up = $conn->prepare("
    UPDATE rh_rooms
    SET room_type=?, rent_price=?
    WHERE dorm_id=? AND room_id=?
  ");

  $updated = 0;
  foreach ($items as $it) {
    $room_id   = intval($it["room_id"] ?? 0);
    $room_type = (($it["room_type"] ?? "fan") === "air") ? "air" : "fan";
    $rent_price = floatval($it["rent_price"] ?? 0);

    if ($room_id<=0) continue;

    $up->bind_param("sdii", $room_type, $rent_price, $dorm_id, $room_id);
    $up->execute();
    if ($up->affected_rows > 0) $updated++;
  }

  out(["ok"=>true, "updated"=>$updated]);
}

out(["ok"=>false,"message"=>"invalid action (list/save)"], 400);
