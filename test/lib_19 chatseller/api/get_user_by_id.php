<?php
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
require "db.php";

// Check if user_id is provided
if (!isset($_GET["user_id"])) {
    echo json_encode(["success" => false, "message" => "Missing user_id parameter"]);
    exit;
}

$user_id = intval($_GET["user_id"]);

// ✅ Select all required fields: name, address, profile_photo_url, phone
$sql = "SELECT user_id, name, address, profile_photo_url, normalized_phone as phone, created_at, updated_at FROM users WHERE user_id = ?";
$stmt = $conn->prepare($sql);

if (!$stmt) {
    echo json_encode(["success" => false, "message" => "Prepare failed: " . $conn->error]);
    exit;
}

$stmt->bind_param("i", $user_id);
$stmt->execute();
$result = $stmt->get_result();

$user = $result->fetch_assoc();

if ($user) {
    echo json_encode([
        "success" => true,
        "user" => [
            "user_id" => $user["user_id"],
            "name" => $user["name"] ?? "",
            "address" => $user["address"] ?? "",
            "profile_photo_url" => $user["profile_photo_url"] ?? null,
            "phone" => $user["phone"] ?? "",
            "created_at" => $user["created_at"] ?? null,
            "updated_at" => $user["updated_at"] ?? null
        ]
    ]);
} else {
    echo json_encode([
        "success" => false,
        "message" => "User not found"
    ]);
}

$stmt->close();
$conn->close();
?>