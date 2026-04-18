<?php
// db.php
$host = "localhost";
$user = "root";
$pass = "";
$dbname = "reshub"; // ✅ เปลี่ยนจาก reshub_db เป็น reshub

$conn = new mysqli($host, $user, $pass, $dbname);
$conn->set_charset("utf8mb4");

if ($conn->connect_error) {
    die(json_encode(["success" => false, "message" => "Connection failed"]));
}