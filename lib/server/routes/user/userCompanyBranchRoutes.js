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

// Assign user to company and branch
router.put('/assign-company-branch', async (req, res) => {
  try {
    const { phone, company_id, branch_id } = req.body;
    
    if (!phone || !company_id || !branch_id) {
      return res.status(400).json({ 
        success: false, 
        message: 'Phone, company_id, and branch_id are required' 
      });
    }

    // Verify company and branch exist
    const [companyCheck] = await pool.execute(
      'SELECT company_id FROM companies WHERE company_id = ?',
      [company_id]
    );

    if (companyCheck.length === 0) {
      return res.status(400).json({ success: false, message: 'Company not found' });
    }

    const [branchCheck] = await pool.execute(
      'SELECT branch_id FROM branches WHERE branch_id = ? AND company_id = ?',
      [branch_id, company_id]
    );

    if (branchCheck.length === 0) {
      return res.status(400).json({ success: false, message: 'Branch not found or does not belong to this company' });
    }

    // Update user
    const [result] = await pool.execute(
      'UPDATE users SET company_id = ?, branch_id = ? WHERE phone = ?',
      [company_id, branch_id, phone]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    res.json({ success: true, message: 'User assigned to company and branch successfully' });
  } catch (error) {
    console.error('Error assigning user to company/branch:', error);
    res.status(500).json({ success: false, message: 'Failed to assign user' });
  }
});

// Get user's company and branch info by phone
router.get('/user-info/:phone', async (req, res) => {
  try {
    const { phone } = req.params;
    
    // Validate phone number
    if (!/^[0-9+]+$/.test(phone)) {
      return res.status(400).json({ 
        success: false, 
        message: 'Invalid phone number format' 
      });
    }
    
    const [userInfo] = await pool.execute(`
      SELECT u.*, c.company_name, b.branch_name, b.city
      FROM users u
      LEFT JOIN companies c ON u.company_id = c.company_id
      LEFT JOIN branches b ON u.branch_id = b.branch_id
      WHERE u.phone = ?
    `, [phone]);

    if (userInfo.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    res.json({ success: true, data: userInfo[0] });
  } catch (error) {
    console.error('Error fetching user info:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch user info' });
  }
});

// Get user's company and branch info by user_id
router.get('/user-info-by-id/:user_id', async (req, res) => {
  try {
    const { user_id } = req.params;
    
    // Validate user_id
    const userIdNum = parseInt(user_id);
    if (isNaN(userIdNum) || userIdNum <= 0) {
      return res.status(400).json({ 
        success: false, 
        message: 'Invalid user ID format' 
      });
    }
    
    const [userInfo] = await pool.execute(`
      SELECT u.*, c.company_name, b.branch_name, b.city
      FROM users u
      LEFT JOIN companies c ON u.company_id = c.company_id
      LEFT JOIN branches b ON u.branch_id = b.branch_id
      WHERE u.user_id = ?
    `, [userIdNum]);

    if (userInfo.length === 0) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    console.log('🔍 User info by ID:', userInfo[0]);
    res.json({ success: true, data: userInfo[0] });
  } catch (error) {
    console.error('Error fetching user info by ID:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch user info' });
  }
});

// Get all users by company and branch
router.get('/by-company-branch/:company_id/:branch_id', async (req, res) => {
  try {
    const { company_id, branch_id } = req.params;
    
    const [users] = await pool.execute(`
      SELECT u.*, c.company_name, b.branch_name, b.city
      FROM users u
      LEFT JOIN companies c ON u.company_id = c.company_id
      LEFT JOIN branches b ON u.branch_id = b.branch_id
      WHERE u.company_id = ? AND u.branch_id = ?
      ORDER BY u.name
    `, [company_id, branch_id]);
    
    res.json({ success: true, data: users });
  } catch (error) {
    console.error('Error fetching users by company/branch:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch users' });
  }
});

// Get all users by company only
router.get('/by-company/:company_id', async (req, res) => {
  try {
    const { company_id } = req.params;
    
    const [users] = await pool.execute(`
      SELECT u.*, c.company_name, b.branch_name, b.city
      FROM users u
      LEFT JOIN companies c ON u.company_id = c.company_id
      LEFT JOIN branches b ON u.branch_id = b.branch_id
      WHERE u.company_id = ?
      ORDER BY u.name
    `, [company_id]);
    
    res.json({ success: true, data: users });
  } catch (error) {
    console.error('Error fetching users by company:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch users' });
  }
});

// Get branch admins (users who can publish products)
router.get('/branch-admins/:company_id/:branch_id', async (req, res) => {
  try {
    const { company_id, branch_id } = req.params;
    
    // You might want to add a role field to users table to identify admins
    // For now, we'll get all users assigned to this branch
    const [admins] = await pool.execute(`
      SELECT user_id, name, phone, email, fcm_token
      FROM users 
      WHERE company_id = ? AND branch_id = ? AND phone IS NOT NULL
      ORDER BY name
    `, [company_id, branch_id]);
    
    res.json({ success: true, data: admins });
  } catch (error) {
    console.error('Error fetching branch admins:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch branch admins' });
  }
});

// Admin company assignment (exact database structure)
router.post('/admin-assign-company', async (req, res) => {
  try {
    console.log('🔧 Admin company assignment called');
    const { user_id, company_name, branch_name, phone } = req.body;
    
    if (!user_id || !phone) {
      return res.status(400).json({ 
        success: false, 
        message: 'user_id and phone are required' 
      });
    }
    
    const connection = await pool.getConnection();
    
    try {
      // Check if user exists
      const [userCheck] = await connection.execute(
        'SELECT user_id FROM users WHERE user_id = ? OR phone = ?',
        [user_id, phone]
      );
      
      if (userCheck.length === 0) {
        return res.status(404).json({ 
          success: false, 
          message: 'User not found' 
        });
      }
      
      // Get or create a default company using exact database structure
      let [companies] = await connection.execute(
        'SELECT company_id FROM companies WHERE company_name LIKE "%Default%" LIMIT 1'
      );
      
      let companyId;
      if (companies.length === 0) {
        // Create company with exact database fields
        const [companyResult] = await connection.execute(
          'INSERT INTO companies (company_name) VALUES (?)',
          [company_name || 'Default Company']
        );
        companyId = companyResult.insertId;
        console.log('✅ Created company with ID:', companyId);
      } else {
        companyId = companies[0].company_id;
        console.log('✅ Using existing company ID:', companyId);
      }
      
      // Get or create default branch using exact database structure
      let [branches] = await connection.execute(
        'SELECT branch_id FROM branches WHERE company_id = ? AND branch_name LIKE "%Main%" LIMIT 1',
        [companyId]
      );
      
      let branchId;
      if (branches.length === 0) {
        // Create branch with exact database fields
        const [branchResult] = await connection.execute(
          'INSERT INTO branches (company_id, branch_name, city) VALUES (?, ?, ?)',
          [companyId, branch_name || 'Main Branch', 'Noida']
        );
        branchId = branchResult.insertId;
        console.log('✅ Created branch with ID:', branchId);
      } else {
        branchId = branches[0].branch_id;
        console.log('✅ Using existing branch ID:', branchId);
      }
      
      // Assign user to company and branch
      const [updateResult] = await connection.execute(
        'UPDATE users SET company_id = ?, branch_id = ? WHERE user_id = ? OR phone = ?',
        [companyId, branchId, user_id, phone]
      );
      
      if (updateResult.affectedRows > 0) {
        console.log('✅ User assigned - Company ID:', companyId, 'Branch ID:', branchId);
        res.json({ 
          success: true, 
          message: 'Admin company assignment completed successfully',
          company_id: companyId,
          branch_id: branchId,
          user_id: user_id
        });
      } else {
        res.status(400).json({ 
          success: false, 
          message: 'Failed to assign user to company - no rows affected' 
        });
      }
      
    } finally {
      connection.release();
    }
    
  } catch (error) {
    console.error('Admin company assignment error:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to assign company to admin',
      error: error.message 
    });
  }
});

// Test endpoint to verify server is working
router.get('/test', async (req, res) => {
  try {
    console.log('🧪 Test endpoint called');
    res.json({ 
      success: true, 
      message: 'User routes are working!',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Test endpoint error:', error);
    res.status(500).json({ success: false, message: 'Test endpoint failed' });
  }
});

module.exports = router;
