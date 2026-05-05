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

// Check if user has company/branch assigned
router.get('/check-company/:phone', async (req, res) => {
  try {
    const { phone } = req.params;
    
    // Validate phone number - only allow numbers and + sign
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
      return res.json({ 
        success: false, 
        message: 'User not found',
        has_company: false,
        needs_registration: true
      });
    }

    const user = userInfo[0];
    
    res.json({ 
      success: true,
      has_company: !!user.company_id && !!user.branch_id,
      needs_registration: !user.company_id || !user.branch_id,
      user_info: {
        user_id: user.user_id,
        name: user.name,
        phone: user.phone,
        company_id: user.company_id,
        branch_id: user.branch_id,
        company_name: user.company_name,
        branch_name: user.branch_name,
        city: user.city
      }
    });
  } catch (error) {
    console.error('Error checking user company:', error);
    res.status(500).json({ success: false, message: 'Failed to check user company' });
  }
});

// Quick company registration for Flutter users
router.post('/quick-register-company', async (req, res) => {
  try {
    const { phone, company_name, branch_name, city } = req.body;
    
    if (!phone || !company_name || !branch_name) {
      return res.status(400).json({ 
        success: false, 
        message: 'Phone, company_name, and branch_name are required' 
      });
    }

    const connection = await pool.getConnection();
    
    try {
      await connection.beginTransaction();

      // Check if user exists
      const [userCheck] = await connection.execute(
        'SELECT user_id FROM users WHERE phone = ?',
        [phone]
      );

      if (userCheck.length === 0) {
        await connection.rollback();
        return res.status(404).json({ success: false, message: 'User not found' });
      }

      const userId = userCheck[0].user_id;

      // Check if user already has company
      const [companyCheck] = await connection.execute(
        'SELECT company_id FROM users WHERE user_id = ? AND company_id IS NOT NULL',
        [userId]
      );

      if (companyCheck.length > 0) {
        await connection.rollback();
        return res.status(400).json({ 
          success: false, 
          message: 'User already has a company assigned' 
        });
      }

      // Create company
      const [companyResult] = await connection.execute(
        'INSERT INTO companies (company_name) VALUES (?)',
        [company_name]
      );

      const companyId = companyResult.insertId;

      // Create branch
      const [branchResult] = await connection.execute(
        'INSERT INTO branches (company_id, branch_name, city) VALUES (?, ?, ?)',
        [companyId, branch_name, city || null]
      );

      const branchId = branchResult.insertId;

      // Update user with company and branch
      await connection.execute(
        'UPDATE users SET company_id = ?, branch_id = ? WHERE user_id = ?',
        [companyId, branchId, userId]
      );

      await connection.commit();

      res.json({ 
        success: true, 
        message: 'Company and branch registered successfully',
        data: {
          company_id: companyId,
          branch_id: branchId,
          company_name,
          branch_name,
          city
        }
      });

    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }

  } catch (error) {
    console.error('Error in quick company registration:', error);
    res.status(500).json({ success: false, message: 'Failed to register company' });
  }
});

// Get user's company details for Flutter
router.get('/company-details/:phone', async (req, res) => {
  try {
    const { phone } = req.params;
    
    // Validate phone number
    if (!/^[0-9+]+$/.test(phone)) {
      return res.status(400).json({ 
        success: false, 
        message: 'Invalid phone number format' 
      });
    }
    
    const [companyInfo] = await pool.execute(`
      SELECT 
        c.company_id, c.company_name,
        b.branch_id, b.branch_name, b.city,
        u.user_id, u.name as user_name
      FROM users u
      JOIN companies c ON u.company_id = c.company_id
      JOIN branches b ON u.branch_id = b.branch_id
      WHERE u.phone = ?
    `, [phone]);

    if (companyInfo.length === 0) {
      return res.status(404).json({ success: false, message: 'Company not found for this user' });
    }

    res.json({ 
      success: true, 
      data: companyInfo[0] 
    });

  } catch (error) {
    console.error('Error fetching company details:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch company details' });
  }
});

// Check if user can publish products
router.get('/can-publish/:phone', async (req, res) => {
  try {
    const { phone } = req.params;
    
    // Validate phone number
    if (!/^[0-9+]+$/.test(phone)) {
      return res.status(400).json({ 
        success: false, 
        message: 'Invalid phone number format' 
      });
    }
    
    const [userInfo] = await pool.execute(
      'SELECT company_id, branch_id FROM users WHERE phone = ?',
      [phone]
    );

    if (userInfo.length === 0) {
      return res.json({ 
        success: false, 
        can_publish: false,
        message: 'User not found',
        reason: 'user_not_found'
      });
    }

    const user = userInfo[0];
    
    if (!user.company_id || !user.branch_id) {
      return res.json({ 
        success: true, 
        can_publish: false,
        message: 'User needs to register company first',
        reason: 'no_company'
      });
    }

    res.json({ 
      success: true, 
      can_publish: true,
      message: 'User can publish products',
      reason: 'ready'
    });

  } catch (error) {
    console.error('Error checking publish permission:', error);
    res.status(500).json({ success: false, message: 'Failed to check publish permission' });
  }
});

module.exports = router;
