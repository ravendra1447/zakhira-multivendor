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

// Get products by branch
router.get('/products/branch/:branch_id', async (req, res) => {
  try {
    const { branch_id } = req.params;
    const { limit = 20, offset = 0, status = 'publish' } = req.query;
    
    const [products] = await pool.execute(`
      SELECT p.*, c.company_name, b.branch_name, u.name as publisher_name
      FROM products p
      LEFT JOIN companies c ON p.company_id = c.company_id
      LEFT JOIN branches b ON p.branch_id = b.branch_id
      LEFT JOIN users u ON p.published_by_admin_id = u.user_id
      WHERE p.branch_id = ? AND p.status = ?
      ORDER BY p.created_at DESC
      LIMIT ? OFFSET ?
    `, [branch_id, status, parseInt(limit), parseInt(offset)]);
    
    res.json({ success: true, data: products });
  } catch (error) {
    console.error('Error fetching branch products:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch products' });
  }
});

// Get orders by branch
router.get('/orders/branch/:branch_id', async (req, res) => {
  try {
    const { branch_id } = req.params;
    const { limit = 20, offset = 0, status } = req.query;
    
    let query = `
      SELECT o.*, c.company_name, b.branch_name, 
             u.name as customer_name, u.phone as customer_phone,
             admin.name as assigned_admin_name
      FROM orders o
      LEFT JOIN companies c ON o.company_id = c.company_id
      LEFT JOIN branches b ON o.branch_id = b.branch_id
      LEFT JOIN users u ON o.user_id = u.user_id
      LEFT JOIN users admin ON o.assigned_admin_id = admin.user_id
      WHERE o.branch_id = ?
    `;
    let params = [branch_id];
    
    if (status) {
      query += ' AND o.order_status = ?';
      params.push(status);
    }
    
    query += ' ORDER BY o.order_date DESC LIMIT ? OFFSET ?';
    params.push(parseInt(limit), parseInt(offset));
    
    const [orders] = await pool.execute(query, params);
    
    res.json({ success: true, data: orders });
  } catch (error) {
    console.error('Error fetching branch orders:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch orders' });
  }
});

// Get users by branch
router.get('/users/branch/:branch_id', async (req, res) => {
  try {
    const { branch_id } = req.params;
    const { limit = 20, offset = 0 } = req.query;
    
    const [users] = await pool.execute(`
      SELECT u.*, c.company_name, b.branch_name
      FROM users u
      LEFT JOIN companies c ON u.company_id = c.company_id
      LEFT JOIN branches b ON u.branch_id = b.branch_id
      WHERE u.branch_id = ?
      ORDER BY u.name
      LIMIT ? OFFSET ?
    `, [branch_id, parseInt(limit), parseInt(offset)]);
    
    res.json({ success: true, data: users });
  } catch (error) {
    console.error('Error fetching branch users:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch users' });
  }
});

// Get products by company
router.get('/products/company/:company_id', async (req, res) => {
  try {
    const { company_id } = req.params;
    const { limit = 20, offset = 0, status = 'publish', branch_id } = req.query;
    
    let query = `
      SELECT p.*, c.company_name, b.branch_name, u.name as publisher_name
      FROM products p
      LEFT JOIN companies c ON p.company_id = c.company_id
      LEFT JOIN branches b ON p.branch_id = b.branch_id
      LEFT JOIN users u ON p.published_by_admin_id = u.user_id
      WHERE p.company_id = ? AND p.status = ?
    `;
    let params = [company_id, status];
    
    if (branch_id) {
      query += ' AND p.branch_id = ?';
      params.push(branch_id);
    }
    
    query += ' ORDER BY p.created_at DESC LIMIT ? OFFSET ?';
    params.push(parseInt(limit), parseInt(offset));
    
    const [products] = await pool.execute(query, params);
    
    res.json({ success: true, data: products });
  } catch (error) {
    console.error('Error fetching company products:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch products' });
  }
});

// Get orders by company
router.get('/orders/company/:company_id', async (req, res) => {
  try {
    const { company_id } = req.params;
    const { limit = 20, offset = 0, status, branch_id } = req.query;
    
    let query = `
      SELECT o.*, c.company_name, b.branch_name, 
             u.name as customer_name, u.phone as customer_phone,
             admin.name as assigned_admin_name
      FROM orders o
      LEFT JOIN companies c ON o.company_id = c.company_id
      LEFT JOIN branches b ON o.branch_id = b.branch_id
      LEFT JOIN users u ON o.user_id = u.user_id
      LEFT JOIN users admin ON o.assigned_admin_id = admin.user_id
      WHERE o.company_id = ?
    `;
    let params = [company_id];
    
    if (branch_id) {
      query += ' AND o.branch_id = ?';
      params.push(branch_id);
    }
    
    if (status) {
      query += ' AND o.order_status = ?';
      params.push(status);
    }
    
    query += ' ORDER BY o.order_date DESC LIMIT ? OFFSET ?';
    params.push(parseInt(limit), parseInt(offset));
    
    const [orders] = await pool.execute(query, params);
    
    res.json({ success: true, data: orders });
  } catch (error) {
    console.error('Error fetching company orders:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch orders' });
  }
});

// Get branch statistics
router.get('/stats/branch/:branch_id', async (req, res) => {
  try {
    const { branch_id } = req.params;
    
    // Get product counts
    const [productStats] = await pool.execute(`
      SELECT 
        COUNT(*) as total_products,
        COUNT(CASE WHEN status = 'publish' THEN 1 END) as published_products,
        COUNT(CASE WHEN status = 'draft' THEN 1 END) as draft_products
      FROM products WHERE branch_id = ?
    `, [branch_id]);
    
    // Get order counts
    const [orderStats] = await pool.execute(`
      SELECT 
        COUNT(*) as total_orders,
        COUNT(CASE WHEN order_status = 'Pending' THEN 1 END) as pending_orders,
        COUNT(CASE WHEN order_status = 'Delivered' THEN 1 END) as delivered_orders,
        SUM(total_amount) as total_revenue
      FROM orders WHERE branch_id = ?
    `, [branch_id]);
    
    // Get user count
    const [userStats] = await pool.execute(`
      SELECT COUNT(*) as total_users
      FROM users WHERE branch_id = ?
    `, [branch_id]);
    
    res.json({
      success: true,
      data: {
        products: productStats[0],
        orders: orderStats[0],
        users: userStats[0]
      }
    });
  } catch (error) {
    console.error('Error fetching branch statistics:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch statistics' });
  }
});

// Get company statistics
router.get('/stats/company/:company_id', async (req, res) => {
  try {
    const { company_id } = req.params;
    
    // Get product counts
    const [productStats] = await pool.execute(`
      SELECT 
        COUNT(*) as total_products,
        COUNT(CASE WHEN status = 'publish' THEN 1 END) as published_products,
        COUNT(CASE WHEN status = 'draft' THEN 1 END) as draft_products,
        COUNT(DISTINCT branch_id) as branches_with_products
      FROM products WHERE company_id = ?
    `, [company_id]);
    
    // Get order counts
    const [orderStats] = await pool.execute(`
      SELECT 
        COUNT(*) as total_orders,
        COUNT(CASE WHEN order_status = 'Pending' THEN 1 END) as pending_orders,
        COUNT(CASE WHEN order_status = 'Delivered' THEN 1 END) as delivered_orders,
        SUM(total_amount) as total_revenue,
        COUNT(DISTINCT branch_id) as branches_with_orders
      FROM orders WHERE company_id = ?
    `, [company_id]);
    
    // Get branch and user counts
    const [branchStats] = await pool.execute(`
      SELECT COUNT(*) as total_branches FROM branches WHERE company_id = ?
    `, [company_id]);
    
    const [userStats] = await pool.execute(`
      SELECT COUNT(*) as total_users,
             COUNT(DISTINCT branch_id) as branches_with_users
      FROM users WHERE company_id = ?
    `, [company_id]);
    
    res.json({
      success: true,
      data: {
        products: productStats[0],
        orders: orderStats[0],
        branches: branchStats[0],
        users: userStats[0]
      }
    });
  } catch (error) {
    console.error('Error fetching company statistics:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch statistics' });
  }
});

// Get admin's branch orders (orders assigned to specific admin)
router.get('/orders/admin/:admin_id', async (req, res) => {
  try {
    const { admin_id } = req.params;
    const { limit = 20, offset = 0, status } = req.query;
    
    let query = `
      SELECT o.*, c.company_name, b.branch_name, 
             u.name as customer_name, u.phone as customer_phone
      FROM orders o
      LEFT JOIN companies c ON o.company_id = c.company_id
      LEFT JOIN branches b ON o.branch_id = b.branch_id
      LEFT JOIN users u ON o.user_id = u.user_id
      WHERE o.assigned_admin_id = ?
    `;
    let params = [admin_id];
    
    if (status) {
      query += ' AND o.order_status = ?';
      params.push(status);
    }
    
    query += ' ORDER BY o.order_date DESC LIMIT ? OFFSET ?';
    params.push(parseInt(limit), parseInt(offset));
    
    const [orders] = await pool.execute(query, params);
    
    res.json({ success: true, data: orders });
  } catch (error) {
    console.error('Error fetching admin orders:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch orders' });
  }
});

module.exports = router;
