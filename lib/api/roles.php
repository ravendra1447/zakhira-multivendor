<?php
/**
 * Roles API - Get All Roles
 * GET /roles
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

try {
    $database = new Database();
    $db = $database->getConnection();

    switch ($method) {
        case 'GET':
            // Get all roles with user and website details
            $query = "SELECT r.*, u.username, u.email, u.full_name, w.website_name, w.domain 
                      FROM roles r 
                      LEFT JOIN users u ON r.user_id = u.user_id 
                      LEFT JOIN websites w ON r.website_id = w.website_id 
                      ORDER BY r.created_at DESC";
            
            $stmt = $db->prepare($query);
            $stmt->execute();
            $roles = $stmt->fetchAll(PDO::FETCH_ASSOC);

            echo json_encode([
                'success' => true,
                'data' => $roles,
                'count' => count($roles)
            ]);
            break;

        case 'POST':
            // Assign new role
            $data = json_decode(file_get_contents('php://input'), true);

            if (!isset($data['user_id']) || !isset($data['website_id']) || !isset($data['role'])) {
                http_response_code(400);
                echo json_encode([
                    'success' => false,
                    'message' => 'user_id, website_id, and role are required'
                ]);
                exit;
            }

            // Check if role already exists for this user and website
            $checkQuery = "SELECT role_id FROM roles WHERE user_id = :user_id AND website_id = :website_id";
            $checkStmt = $db->prepare($checkQuery);
            $checkStmt->bindParam(':user_id', $data['user_id']);
            $checkStmt->bindParam(':website_id', $data['website_id']);
            $checkStmt->execute();

            if ($checkStmt->rowCount() > 0) {
                // Update existing role
                $updateQuery = "UPDATE roles SET 
                    role = :role, 
                    platform = :platform, 
                    status = :status, 
                    permissions = :permissions,
                    assigned_by = :assigned_by,
                    assigned_at = CURRENT_TIMESTAMP
                    WHERE user_id = :user_id AND website_id = :website_id";
                
                $updateStmt = $db->prepare($updateQuery);
                $updateStmt->bindParam(':user_id', $data['user_id']);
                $updateStmt->bindParam(':website_id', $data['website_id']);
                $updateStmt->bindParam(':role', $data['role']);
                $platform = $data['platform'] ?? 'BOTH';
                $updateStmt->bindParam(':platform', $platform);
                $status = $data['status'] ?? 'active';
                $updateStmt->bindParam(':status', $status);
                $permissions = json_encode($data['permissions'] ?? []);
                $updateStmt->bindParam(':permissions', $permissions);
                $assigned_by = $data['assigned_by'] ?? null;
                $updateStmt->bindParam(':assigned_by', $assigned_by);
                $updateStmt->execute();

                echo json_encode([
                    'success' => true,
                    'message' => 'Role updated successfully'
                ]);
            } else {
                // Insert new role
                $insertQuery = "INSERT INTO roles (user_id, website_id, role, platform, status, permissions, assigned_by) 
                               VALUES (:user_id, :website_id, :role, :platform, :status, :permissions, :assigned_by)";
                
                $insertStmt = $db->prepare($insertQuery);
                $insertStmt->bindParam(':user_id', $data['user_id']);
                $insertStmt->bindParam(':website_id', $data['website_id']);
                $insertStmt->bindParam(':role', $data['role']);
                $platform = $data['platform'] ?? 'BOTH';
                $insertStmt->bindParam(':platform', $platform);
                $status = $data['status'] ?? 'active';
                $insertStmt->bindParam(':status', $status);
                $permissions = json_encode($data['permissions'] ?? []);
                $insertStmt->bindParam(':permissions', $permissions);
                $assigned_by = $data['assigned_by'] ?? null;
                $insertStmt->bindParam(':assigned_by', $assigned_by);
                $insertStmt->execute();

                $roleId = $db->lastInsertId();

                echo json_encode([
                    'success' => true,
                    'message' => 'Role assigned successfully',
                    'role_id' => $roleId
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
