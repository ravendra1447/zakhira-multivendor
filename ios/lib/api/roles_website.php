<?php
/**
 * Website Roles API - Get roles by website ID
 * GET /roles/website/{website_id}
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

// Get website ID from URL
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$pathParts = explode('/', $path);
$websiteId = end($pathParts);

if (!is_numeric($websiteId)) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => 'Invalid website ID'
    ]);
    exit;
}

try {
    $database = new Database();
    $db = $database->getConnection();

    if ($method === 'GET') {
        // Get roles for specific website with user details
        $query = "SELECT r.*, u.username, u.email, u.full_name, u.phone 
                  FROM roles r 
                  LEFT JOIN users u ON r.user_id = u.user_id 
                  WHERE r.website_id = :website_id 
                  ORDER BY r.created_at DESC";
        
        $stmt = $db->prepare($query);
        $stmt->bindParam(':website_id', $websiteId, PDO::PARAM_INT);
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
