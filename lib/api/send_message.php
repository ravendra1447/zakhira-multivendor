<?php
header("Content-Type: application/json");
require "db.php";

date_default_timezone_set("Asia/Kolkata");

// ✅ ERROR REPORTING ENABLE KAREN
error_reporting(E_ALL);
ini_set('display_errors', 1);

// ✅ Read JSON input
$input = file_get_contents("php://input");
error_log("📩 Raw input: " . $input);
$data = json_decode($input, true);

if (json_last_error() !== JSON_ERROR_NONE) {
    echo json_encode(["success" => false, "message" => "Invalid JSON: " . json_last_error_msg()]);
    exit;
}

error_log("📩 Received data: " . print_r($data, true));

// ✅ Validation
if (!isset($data["chat_id"], $data["sender_id"], $data["receiver_id"], $data["message_text"])) {
    echo json_encode(["success" => false, "message" => "Missing required parameters"]);
    exit;
}

// ✅ Core variables
$chat_id     = intval($data["chat_id"]);
$sender_id   = intval($data["sender_id"]);
$receiver_id = intval($data["receiver_id"]);
$message_text = trim($data["message_text"]);
$message_type = "encrypted";

// ✅ Validate message text not empty
if (empty($message_text)) {
    echo json_encode(["success" => false, "message" => "Message text cannot be empty"]);
    exit;
}

$media_url         = $data["media_url"] ?? null;
$low_quality_url   = $data["low_quality_url"] ?? null;
$blur_hash         = $data["blur_hash"] ?? null;
$thumbnail_data    = $data["thumbnail_data"] ?? null;
$image_variant     = $data["image_variant"] ?? null;
$forwarded_from_id = isset($data["forwarded_from_id"]) ? intval($data["forwarded_from_id"]) : null;
$reply_to_message_id = $data["reply_to_message_id"] ?? null;

// ✅ GROUP DATA FIELDS
$group_id = $data["group_id"] ?? null;
$image_index = isset($data["image_index"]) ? intval($data["image_index"]) : 0;
$total_images = isset($data["total_images"]) ? intval($data["total_images"]) : 1;

$current_time = date("Y-m-d H:i:s");

// ✅ GROUP DATA JSON BANAO
$group_data = null;
if ($group_id || $image_index > 0 || $total_images > 1) {
    $group_data = json_encode([
        "group_id" => $group_id,
        "image_index" => $image_index,
        "total_images" => $total_images
    ]);
}

// ✅ Auto defaults for media
if ($media_url && $image_variant === null) {
    $image_variant = "actual";
}

if ($media_url && $low_quality_url === null) {
    if (strpos($media_url, '?') === false) {
        $low_quality_url = $media_url . "?variant=low";
    } else {
        $low_quality_url = $media_url . "&variant=low";
    }
}

// ✅ MEDIA VARIANTS ARRAY
$media_variants = [];
if ($media_url) {
    $media_variants[] = [
        "type" => "image",
        "variant" => "actual", 
        "url" => $media_url,
        "width" => $data["width"] ?? null,
        "height" => $data["height"] ?? null
    ];
    
    if ($low_quality_url) {
        $media_variants[] = [
            "type" => "image",
            "variant" => "blurred",
            "url" => $low_quality_url,
            "width" => 400,
            "height" => 300
        ];
    }
}

// ✅ Convert media_variants to JSON
$media_variants_json = !empty($media_variants) ? json_encode($media_variants) : null;

// ✅ CORRECTED SQL - ALL VALUES AS PARAMETERS
$stmt = $conn->prepare("
    INSERT INTO messages (
        chat_id, sender_id, receiver_id, message_type, message_text,
        media_url, low_quality_url, blur_hash, thumbnail_data, 
        image_variant, media_variants, is_delivered, is_read, timestamp,
        forwarded_from_id, reply_to_message_id, group_data, group_id, image_index, total_images
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
");

if (!$stmt) {
    error_log("❌ Prepare failed: " . $conn->error);
    echo json_encode(["success" => false, "message" => "Prepare failed: " . $conn->error]);
    exit;
}

// ✅ CORRECTED bind types (20 parameters = 20 type specifiers)
$is_delivered = 0;
$is_read = 0;

$stmt->bind_param(
    "iiissssssssiissssiii",  // ✅ 20 type specifiers
    // i = integer, s = string
    $chat_id,              // i
    $sender_id,            // i  
    $receiver_id,          // i
    $message_type,         // s
    $message_text,         // s
    $media_url,            // s
    $low_quality_url,      // s
    $blur_hash,            // s
    $thumbnail_data,       // s
    $image_variant,        // s
    $media_variants_json,  // s
    $is_delivered,         // i
    $is_read,              // i  
    $current_time,         // s
    $forwarded_from_id,    // i
    $reply_to_message_id,  // s
    $group_data,           // s
    $group_id,             // s
    $image_index,          // i
    $total_images          // i
);

// ✅ Execute
if ($stmt->execute()) {
    $message_id = $stmt->insert_id;

    // ✅ Build response data
    $response_data = [
        "message_id"        => $message_id,
        "chat_id"           => $chat_id,
        "sender_id"         => $sender_id,
        "receiver_id"       => $receiver_id,
        "message_type"      => $message_type,
        "message_text"      => $message_text,
        "media_url"         => $media_url,
        "low_quality_url"   => $low_quality_url,
        "blur_hash"         => $blur_hash,
        "thumbnail_data"    => $thumbnail_data,
        "image_variant"     => $image_variant,
        "media_variants"    => $media_variants,
        "forwarded_from_id" => $forwarded_from_id,
        "reply_to_message_id" => $reply_to_message_id,
        "timestamp"         => $current_time,
        "is_read"           => $is_read,
        "is_delivered"      => $is_delivered,
        // ✅ GROUP DATA IN RESPONSE
        "group_data"        => $group_data ? json_decode($group_data, true) : null,
        "group_id"          => $group_id,
        "image_index"       => $image_index,
        "total_images"      => $total_images
    ];

    echo json_encode([
        "success" => true,
        "message" => "Message sent successfully",
        "data" => $response_data
    ]);
    
    error_log("✅ Message inserted with group support - ID: {$message_id}");
    
} else {
    error_log("❌ Execute failed: " . $stmt->error);
    echo json_encode(["success" => false, "message" => "Database error: " . $stmt->error]);
}

// ✅ Close connections
$stmt->close();
$conn->close();
?>