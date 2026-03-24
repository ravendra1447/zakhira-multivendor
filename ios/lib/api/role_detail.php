<?php
/**
 * Role Detail API - Get, Update, Delete specific role
 * GET /roles/{id}
 * PUT /roles/{id}
 * DELETE /roles/{id}
 */

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

require_once '../config/database.php';

$method = $_SERVER['REQUEST_METHOD'];

// Get role ID from URL
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$pathParts = explode('/', $path);
$roleId = end($pathParts);

if (!is_numeric($roleId)) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'message' => 'Invalid role ID'
    ]);
    exit;
}

try {
    $database = new Database();
    $db = $database->getConnection();

    switch ($method) {
        case 'GET':
            // Get specific role details
            $query = "SELECT r.*, u.username, u.email, u.full_name, w.website_name, w.domain 
                      FROM roles r 
                      LEFT JOIN users u ON r.user_id = u.user_id 
                      LEFT JOIN websites w ON r.website_id = w.website_id 
                      WHERE r.role_id = :role_id";
            
            $stmt = $db->prepare($query);
            $stmt->bindParam(':role_id', $roleId, PDO::PARAM_INT);
            $stmt->execute();
            $role = $stmt->fetch(PDO::FETCH_ASSOC);

            if ($role) {
                echo json_encode([
                    'success' => true,
                    'data' => $role
                ]);
            } else {
                http_response_code(404);
                echo json_encode([
                    'success' => false,
                    'message' => 'Role not found'
                ]);
            }
            break;

        case 'PUT':
            // Update role
            $data = json_decode(file_get_contents('php://input'), true);

            // Build update query dynamically
            $updateFields = [];
            $params = [':role_id' => $roleId];

            if (isset($data['role'])) {
                $updateFields[] = 'role = :role';
                $params[':role'] = $data['role'];
            }
            if (isset($data['platform'])) {
                $updateFields[] = 'platform = :platform';
                $params[':platform'] = $data['platform'];
            }
            if (isset($data['status'])) {
                $updateFields[] = 'status = :status';
                $params[':status'] = $data['status'];
            }
            if (isset($data['permissions'])) {
                $updateFields[] = 'permissions = :permissions';
                $params[':permissions'] = json_encode($data['permissions']);
            }

            if (empty($updateFields)) {
                http_response_code(400);
                echo json_encode([
                    'success' => false,
                    'message' => 'No fields to update'
                ]);
                exit;
            }

            $query = "UPDATE roles SET " . implode(', ', $updateFields) . ", updated_at = CURRENT_TIMESTAMP WHERE role_id = :role_id";
            $stmt = $db->prepare($query);

            foreach ($params as $key => $value) {
                $stmt->bindValue($key, $value, is_int($value) ? PDO::PARAM_INT : PDO::PARAM_STR);
            }

            $stmt->execute();

            echo json_encode([
                'success' => true,
                'message' => 'Role updated successfully'
            ]);
            break;

        case 'DELETE':
            // Delete role
            $query = "DELETE FROM roles WHERE role_id = :role_id";
            $stmt = $db->prepare($query);
            $stmt->bindParam(':role_id', $roleId, PDO::PARAM_INT);
            $stmt->execute();

            if ($stmt->rowCount() > 0) {
                echo json_encode([
                    'success' => true,
                    'message' => 'Role deleted successfully'
                ]);
            } else {
                http_response_code(404);
                echo json_encode([
                    'success' => false,
                    'message' => 'Role not found'
                ]);
            }
            break;

        default:
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
