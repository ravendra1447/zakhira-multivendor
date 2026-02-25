const express = require('express');
const router = express.Router();
const mysql = require('mysql2/promise');

// DB Connection
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db"
});

// Get all roles with user and website details
router.get('/', async (req, res) => {
  try {
    const connection = await pool.getConnection();

    const [rows] = await connection.execute(
      `SELECT r.*, u.name as username, u.email, u.name as full_name, u.phone_number as phone, 
              w.website_name, w.domain 
       FROM roles r 
       LEFT JOIN users u ON r.user_id = u.user_id 
       LEFT JOIN websites w ON r.website_id = w.website_id 
       ORDER BY r.created_at DESC`
    );

    connection.release();

    res.json({
      success: true,
      data: rows,
      count: rows.length
    });
  } catch (error) {
    console.error('Error fetching roles:', error);
    res.status(500).json({
      success: false,
      message: 'Server error: ' + error.message
    });
  }
});

// Get roles by user ID
router.get('/user/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const connection = await pool.getConnection();

    const [rows] = await connection.execute(
      `SELECT r.*, w.website_name, w.domain 
       FROM roles r 
       LEFT JOIN websites w ON r.website_id = w.website_id 
       WHERE r.user_id = ? 
       ORDER BY r.created_at DESC`,
      [userId]
    );

    connection.release();

    res.json({
      success: true,
      data: rows,
      count: rows.length
    });
  } catch (error) {
    console.error('Error fetching user roles:', error);
    res.status(500).json({
      success: false,
      message: 'Server error: ' + error.message
    });
  }
});

// Get roles by website ID
router.get('/website/:websiteId', async (req, res) => {
  try {
    const { websiteId } = req.params;
    const connection = await pool.getConnection();

    const [rows] = await connection.execute(
      `SELECT r.*, u.name as username, u.email, u.name as full_name, u.phone_number as phone 
       FROM roles r 
       LEFT JOIN users u ON r.user_id = u.user_id 
       WHERE r.website_id = ? 
       ORDER BY r.created_at DESC`,
      [websiteId]
    );

    connection.release();

    res.json({
      success: true,
      data: rows,
      count: rows.length
    });
  } catch (error) {
    console.error('Error fetching website roles:', error);
    res.status(500).json({
      success: false,
      message: 'Server error: ' + error.message
    });
  }
});

// Get specific role by ID
router.get('/:roleId', async (req, res) => {
  try {
    const { roleId } = req.params;
    const connection = await pool.getConnection();

    const [rows] = await connection.execute(
      `SELECT r.*, u.name as username, u.email, u.name as full_name, u.phone_number as phone, 
              w.website_name, w.domain 
       FROM roles r 
       LEFT JOIN users u ON r.user_id = u.user_id 
       LEFT JOIN websites w ON r.website_id = w.website_id 
       WHERE r.role_id = ?`,
      [roleId]
    );

    connection.release();

    if (rows.length > 0) {
      res.json({
        success: true,
        data: rows[0]
      });
    } else {
      res.status(404).json({
        success: false,
        message: 'Role not found'
      });
    }
  } catch (error) {
    console.error('Error fetching role:', error);
    res.status(500).json({
      success: false,
      message: 'Server error: ' + error.message
    });
  }
});

// Assign new role (POST /roles)
router.post('/', async (req, res) => {
  const connection = await pool.getConnection();

  try {
    const {
      user_id,
      website_id,
      role,
      platform = 'BOTH',
      status = 'active',
      permissions = {},
      assigned_by
    } = req.body;

    // Validate required fields
    if (!user_id || !website_id || !role) {
      return res.status(400).json({
        success: false,
        message: 'user_id, website_id, and role are required'
      });
    }

    await connection.beginTransaction();

    // Check if role already exists for this user and website
    const [existing] = await connection.execute(
      'SELECT role_id FROM roles WHERE user_id = ? AND website_id = ?',
      [user_id, website_id]
    );

    let result;
    const permissionsJson = JSON.stringify(permissions);

    if (existing.length > 0) {
      // Update existing role
      await connection.execute(
        `UPDATE roles SET 
          role = ?, 
          platform = ?, 
          status = ?, 
          permissions = ?,
          assigned_by = ?,
          assigned_at = CURRENT_TIMESTAMP,
          updated_at = CURRENT_TIMESTAMP
         WHERE user_id = ? AND website_id = ?`,
        [role, platform, status, permissionsJson, assigned_by, user_id, website_id]
      );

      // Also update user's default role in users table based on highest priority role
      const [userRoles] = await connection.execute(
        `SELECT role FROM roles WHERE user_id = ? ORDER BY 
          CASE role 
            WHEN 'admin' THEN 1
            WHEN 'supplier' THEN 2  
            WHEN 'reseller' THEN 3
            WHEN 'delivery' THEN 4
            ELSE 5
          END LIMIT 1`,
        [user_id]
      );

      if (userRoles.length > 0) {
        await connection.execute(
          'UPDATE users SET role = ? WHERE user_id = ?',
          [userRoles[0].role, user_id]
        );
      }

      // Check if user_websites entry exists and update or insert
      const [existingUserWebsite] = await connection.execute(
        'SELECT user_website_id FROM user_websites WHERE user_id = ? AND website_id = ?',
        [user_id, website_id]
      );

      if (existingUserWebsite.length > 0) {
        // Update existing entry
        await connection.execute(
          'UPDATE user_websites SET role = ?, status = ?, updated_at = CURRENT_TIMESTAMP WHERE user_id = ? AND website_id = ?',
          [role, 'Y', user_id, website_id]
        );
      } else {
        // Insert new entry
        await connection.execute(
          'INSERT INTO user_websites (user_id, website_id, role, status) VALUES (?, ?, ?, ?)',
          [user_id, website_id, role, 'Y']
        );
      }

      await connection.commit();
      connection.release();

      return res.json({
        success: true,
        message: 'Role updated successfully',
        role_id: existing[0].role_id
      });
    } else {
      // Insert new role
      const [insertResult] = await connection.execute(
        `INSERT INTO roles 
          (user_id, website_id, role, platform, status, permissions, assigned_by) 
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [user_id, website_id, role, platform, status, permissionsJson, assigned_by]
      );

      // Also update user's default role in users table based on highest priority role
      const [userRoles] = await connection.execute(
        `SELECT role FROM roles WHERE user_id = ? ORDER BY 
          CASE role 
            WHEN 'admin' THEN 1
            WHEN 'supplier' THEN 2  
            WHEN 'reseller' THEN 3
            WHEN 'delivery' THEN 4
            ELSE 5
          END LIMIT 1`,
        [user_id]
      );

      if (userRoles.length > 0) {
        await connection.execute(
          'UPDATE users SET role = ? WHERE user_id = ?',
          [userRoles[0].role, user_id]
        );
      }

      // Check if user_websites entry exists and update or insert
      const [existingUserWebsite] = await connection.execute(
        'SELECT user_website_id FROM user_websites WHERE user_id = ? AND website_id = ?',
        [user_id, website_id]
      );

      if (existingUserWebsite.length > 0) {
        // Update existing entry
        await connection.execute(
          'UPDATE user_websites SET role = ?, status = ?, updated_at = CURRENT_TIMESTAMP WHERE user_id = ? AND website_id = ?',
          [role, 'Y', user_id, website_id]
        );
      } else {
        // Insert new entry
        await connection.execute(
          'INSERT INTO user_websites (user_id, website_id, role, status) VALUES (?, ?, ?, ?)',
          [user_id, website_id, role, 'Y']
        );
      }

      await connection.commit();
      connection.release();

      return res.status(201).json({
        success: true,
        message: 'Role assigned successfully',
        role_id: insertResult.insertId
      });
    }
  } catch (error) {
    await connection.rollback();
    connection.release();
    console.error('Error assigning role:', error);
    res.status(500).json({
      success: false,
      message: 'Server error: ' + error.message
    });
  }
});

// Update role (PUT /roles/:roleId)
router.put('/:roleId', async (req, res) => {
  try {
    const { roleId } = req.params;
    const updates = req.body;

    const connection = await pool.getConnection();

    // Build update query dynamically
    const updateFields = [];
    const values = [];

    if (updates.role !== undefined) {
      updateFields.push('role = ?');
      values.push(updates.role);
    }
    if (updates.platform !== undefined) {
      updateFields.push('platform = ?');
      values.push(updates.platform);
    }
    if (updates.status !== undefined) {
      updateFields.push('status = ?');
      values.push(updates.status);
    }
    if (updates.permissions !== undefined) {
      updateFields.push('permissions = ?');
      values.push(JSON.stringify(updates.permissions));
    }

    if (updateFields.length === 0) {
      connection.release();
      return res.status(400).json({
        success: false,
        message: 'No fields to update'
      });
    }

    values.push(roleId);

    const query = `UPDATE roles SET ${updateFields.join(', ')}, updated_at = CURRENT_TIMESTAMP WHERE role_id = ?`;

    const [result] = await connection.execute(query, values);

    connection.release();

    if (result.affectedRows > 0) {
      res.json({
        success: true,
        message: 'Role updated successfully'
      });
    } else {
      res.status(404).json({
        success: false,
        message: 'Role not found'
      });
    }
  } catch (error) {
    console.error('Error updating role:', error);
    res.status(500).json({
      success: false,
      message: 'Server error: ' + error.message
    });
  }
});

// Delete role (DELETE /roles/:roleId)
router.delete('/:roleId', async (req, res) => {
  try {
    const { roleId } = req.params;
    const connection = await pool.getConnection();

    const [result] = await connection.execute(
      'DELETE FROM roles WHERE role_id = ?',
      [roleId]
    );

    connection.release();

    if (result.affectedRows > 0) {
      res.json({
        success: true,
        message: 'Role deleted successfully'
      });
    } else {
      res.status(404).json({
        success: false,
        message: 'Role not found'
      });
    }
  } catch (error) {
    console.error('Error deleting role:', error);
    res.status(500).json({
      success: false,
      message: 'Server error: ' + error.message
    });
  }
});

// Get all users (for dropdown)
router.get('/users/all', async (req, res) => {
  try {
    const connection = await pool.getConnection();

    const [rows] = await connection.execute(
      `SELECT user_id, name as username, email, phone_number as phone, profile_image 
       FROM users 
       ORDER BY name ASC`
    );

    connection.release();

    res.json({
      success: true,
      data: rows,
      count: rows.length
    });
  } catch (error) {
    console.error('Error fetching users:', error);
    res.status(500).json({
      success: false,
      message: 'Server error: ' + error.message
    });
  }
});

// Get websites by admin user
router.get('/websites/admin/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const connection = await pool.getConnection();

    const [rows] = await connection.execute(
      `SELECT w.* 
       FROM websites w
       INNER JOIN roles r ON w.website_id = r.website_id
       WHERE r.user_id = ? AND r.role = 'admin'`,
      [userId]
    );

    connection.release();

    res.json({
      success: true,
      data: rows,
      count: rows.length
    });
  } catch (error) {
    console.error('Error fetching admin websites:', error);
    res.status(500).json({
      success: false,
      message: 'Server error: ' + error.message
    });
  }
});

// Temporary: Auto-assign admin role to user 32 for testing
router.post('/auto-assign-admin', async (req, res) => {
  try {
    const connection = await pool.getConnection();

    // First get any website
    const [websites] = await connection.execute('SELECT website_id FROM websites LIMIT 1');

    if (websites.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'No websites found in database'
      });
    }

    const websiteId = websites[0].website_id;
    const { user_id } = req.body;

    if (!user_id) {
      return res.status(400).json({
        success: false,
        message: 'user_id is required'
      });
    }

    const userId = user_id;

    // Check if role already exists
    const [existing] = await connection.execute(
      'SELECT role_id FROM roles WHERE user_id = ? AND website_id = ?',
      [userId, websiteId]
    );

    if (existing.length === 0) {
      // Insert admin role
      await connection.execute(
        'INSERT INTO roles (user_id, website_id, role, platform, status, assigned_by, created_at) VALUES (?, ?, ?, ?, ?, ?, NOW())',
        [userId, websiteId, 'admin', 'BOTH', 'active', userId]
      );

      // Also update user's default role in users table based on highest priority role
      const [userRoles] = await connection.execute(
        `SELECT role FROM roles WHERE user_id = ? ORDER BY 
          CASE role 
            WHEN 'admin' THEN 1
            WHEN 'supplier' THEN 2  
            WHEN 'reseller' THEN 3
            WHEN 'delivery' THEN 4
            ELSE 5
          END LIMIT 1`,
        [userId]
      );

      if (userRoles.length > 0) {
        await connection.execute(
          'UPDATE users SET role = ? WHERE user_id = ?',
          [userRoles[0].role, userId]
        );
      }

      // Check if user_websites entry exists and update or insert
      const [existingUserWebsite] = await connection.execute(
        'SELECT user_website_id FROM user_websites WHERE user_id = ? AND website_id = ?',
        [userId, websiteId]
      );

      if (existingUserWebsite.length > 0) {
        // Update existing entry
        await connection.execute(
          'UPDATE user_websites SET role = ?, status = ?, updated_at = CURRENT_TIMESTAMP WHERE user_id = ? AND website_id = ?',
          ['admin', 'Y', userId, websiteId]
        );
      } else {
        // Insert new entry
        await connection.execute(
          'INSERT INTO user_websites (user_id, website_id, role, status) VALUES (?, ?, ?, ?)',
          [userId, websiteId, 'admin', 'Y']
        );
      }
    }

    connection.release();

    res.json({
      success: true,
      message: 'Admin role assigned to user 32 successfully',
      website_id: websiteId
    });
  } catch (error) {
    console.error('Error auto-assigning admin:', error);
    res.status(500).json({
      success: false,
      message: 'Server error: ' + error.message
    });
  }
});

module.exports = router;
