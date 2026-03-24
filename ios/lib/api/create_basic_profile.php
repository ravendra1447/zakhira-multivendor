<?php
header("Content-Type: application/json");
require "db.php";

if ($_SERVER["REQUEST_METHOD"] !== "POST") {
    echo json_encode(["success" => false, "message" => "Invalid request method"]);
    exit;
}

// Fields
$user_id = isset($_POST["user_id"]) ? intval($_POST["user_id"]) : null;
$name    = $_POST["name"] ?? null;
$address = $_POST["address"] ?? "";

if (!$user_id || !$name) {
    echo json_encode(["success" => false, "message" => "user_id and name are required"]);
    exit;
}

// Try to use profile_file_id (chunked upload) first
$profile_photo_url = null;
$baseUrl = (isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http") . "://" . $_SERVER['HTTP_HOST'] . dirname($_SERVER['SCRIPT_NAME']);

if (!empty($_POST['profile_file_id'])) {
    $profile_file_id = preg_replace('/[^0-9A-Za-z_\-]/', '', $_POST['profile_file_id']);

    // verify in files table
    $stmtf = $conn->prepare("SELECT file_id FROM files WHERE file_id = ? LIMIT 1");
    $stmtf->bind_param("s", $profile_file_id);
    $stmtf->execute();
    $resf = $stmtf->get_result();
    if ($resf->num_rows > 0) {
        // set profile_photo_url to download endpoint (encrypted file)
        $profile_photo_url = $baseUrl . "/download.php?fileId=" . urlencode($profile_file_id);
    } else {
        // invalid file id => ignore and fall back to direct upload
        $profile_photo_url = null;
    }
}

// If no profile_file_id or not found, check for direct file upload (legacy)
if ($profile_photo_url === null && isset($_FILES["profile_photo"]) && $_FILES["profile_photo"]["error"] == 0) {
    $uploadDir = __DIR__ . "/uploads/";
    if (!is_dir($uploadDir)) mkdir($uploadDir, 0777, true);

    $fileName = time() . "_" . basename($_FILES["profile_photo"]["name"]);
    $targetFilePath = $uploadDir . $fileName;

    if (move_uploaded_file($_FILES["profile_photo"]["tmp_name"], $targetFilePath)) {
        $protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
        $profile_photo_url = $protocol . "://" . $_SERVER['HTTP_HOST'] . dirname($_SERVER['SCRIPT_NAME']) . "/uploads/" . $fileName;
    }
}

// Fetch existing user (to keep previous photo if none provided)
$check = $conn->prepare("SELECT user_id, profile_photo_url FROM users WHERE user_id = ?");
$check->bind_param("i", $user_id);
$check->execute();
$result = $check->get_result();

if ($result->num_rows === 0) {
    echo json_encode(["success" => false, "message" => "User not found"]);
    exit;
}

$row = $result->fetch_assoc();
if ($profile_photo_url === null) {
    // no new photo â€” keep old
    $profile_photo_url = $row["profile_photo_url"];
}

// Update users table
$updated_at = date("Y-m-d H:i:s");
$stmt = $conn->prepare("UPDATE users 
    SET name = ?, address = ?, profile_photo_url = ?, updated_at = ? 
    WHERE user_id = ?");
$stmt->bind_param("ssssi", $name, $address, $profile_photo_url, $updated_at, $user_id);

if ($stmt->execute()) {
    echo json_encode([
        "success" => true,
        "message" => "Profile updated successfully",
        "data" => [
            "user_id" => $user_id,
            "name" => $name,
            "address" => $address,
            "profile_photo_url" => $profile_photo_url
        ]
    ]);
} else {
    echo json_encode(["success" => false, "message" => "Failed to update profile: " . $conn->error]);
}

$stmt->close();
$check->close();
$conn->close();
