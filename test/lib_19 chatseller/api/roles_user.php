<?php
/**
 * User Roles API - Get roles by user ID
 * GET /roles/user/{user_id}
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once '../config/database.php';

$method = $_SERVER['REQUEST_METHOD'];

// Get user ID from URL
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$pathParts = explode('/', $path);
$userId = end($pathParts);

if (!is_numeric($userId)) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => 'Invalid user ID'
    ]);
    exit;
}

try {
    $database = new Database();
    $db = $database->getConnection();

    if ($method === 'GET') {
        // Get roles for specific user with website details
        $query = "SELECT r.*, w.website_name, w.domain 
                  FROM roles r 
                  LEFT JOIN websites w ON r.website_id = w.website_id 
                  WHERE r.user_id = :user_id 
                  ORDER BY r.created_at DESC";
        
        $stmt = $db->prepare($query);
        $stmt->bindParam(':user_id', $userId, PDO::PARAM_INT);
        $stmt->execute();
        $roles = $stmt->fetchAll(PDO::FETCH_ASSOC);

        echo json_encode([
            'success' => true,
            'data' => $roles,
            'count' => count($roles)
        ]);
    } else {
        http_response_code(405);
        echo json_encode([
            'success' => false,
            'message' => 'Method not allowed'
        ]);
    }
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => 'Server error: ' . $e->getMessage()
    ]);
}
?>
