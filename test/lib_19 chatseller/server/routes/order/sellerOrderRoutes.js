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

// Get seller's total order count
router.get('/count/:sellerId', async (req, res) => {
  try {
    const { sellerId } = req.params;
    
    if (!sellerId) {
      return res.status(400).json({
        success: false,
        message: 'Seller ID is required'
      });
    }

    // Get total orders for this seller
    const [orderCount] = await pool.execute(`
      SELECT COUNT(DISTINCT o.id) as total_orders
      FROM orders o
      INNER JOIN order_items oi ON o.id = oi.order_id
      INNER JOIN products p ON oi.product_id = p.id
      WHERE p.user_id = ?
    `, [sellerId]);

    res.json({
      success: true,
      totalOrders: orderCount[0].total_orders,
      sellerId: sellerId
    });

  } catch (error) {
    console.error('Error fetching seller order count:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// Get seller's recent orders with details
router.get('/recent/:sellerId', async (req, res) => {
  try {
    const { sellerId } = req.params;
    const { limit = 10, offset = 0 } = req.query;
    
    if (!sellerId) {
      return res.status(400).json({
        success: false,
        message: 'Seller ID is required'
      });
    }

    // Get recent orders for this seller with product details
    const limitInt = parseInt(limit);
    const offsetInt = parseInt(offset);
    
    // Simple approach - get all orders without LIMIT first
    const [allOrders] = await pool.execute(`
      SELECT DISTINCT 
        o.id,
        o.order_date,
        o.total_amount,
        o.order_status,
        o.payment_status,
        u.name as customer_name,
        u.normalized_phone as customer_phone,
        COUNT(oi.id) as item_count,
        GROUP_CONCAT(p.name SEPARATOR ', ') as product_names
      FROM orders o
      INNER JOIN order_items oi ON o.id = oi.order_id
      INNER JOIN products p ON oi.product_id = p.id
      INNER JOIN users u ON o.user_id = u.user_id
      WHERE p.user_id = ?
      GROUP BY o.id
      ORDER BY o.order_date DESC
    `, [sellerId]);
    
    // Apply pagination in JavaScript
    const orders = allOrders.slice(offsetInt, offsetInt + limitInt);

    res.json({
      success: true,
      orders: orders,
      sellerId: sellerId
    });

  } catch (error) {
    console.error('Error fetching seller recent orders:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// Get seller's unread notifications (new orders)
router.get('/notifications/:sellerId', async (req, res) => {
  try {
    const { sellerId } = req.params;
    
    if (!sellerId) {
      return res.status(400).json({
        success: false,
        message: 'Seller ID is required'
      });
    }

    // Get unread notifications for this seller
    const [notifications] = await pool.execute(`
      SELECT 
        n.id,
        n.type,
        n.title,
        n.message,
        n.data,
        n.created_at,
        n.is_read
      FROM notifications n
      WHERE n.user_id = ? AND n.type = 'new_order_seller'
      ORDER BY n.created_at DESC
      LIMIT 50
    `, [sellerId]);

    // Parse JSON data for easier frontend use
    const formattedNotifications = notifications.map(notification => {
      try {
        return {
          ...notification,
          data: JSON.parse(notification.data || '{}')
        };
      } catch (parseError) {
        console.error('Error parsing notification data:', parseError);
        return {
          ...notification,
          data: {}
        };
      }
    });

    res.json({
      success: true,
      notifications: formattedNotifications,
      unreadCount: formattedNotifications.filter(n => !n.is_read).length
    });

  } catch (error) {
    console.error('Error fetching seller notifications:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// Mark notification as read
router.patch('/notifications/:notificationId/read', async (req, res) => {
  try {
    const { notificationId } = req.params;
    
    if (!notificationId) {
      return res.status(400).json({
        success: false,
        message: 'Notification ID is required'
      });
    }

    const [result] = await pool.execute(`
      UPDATE notifications 
      SET is_read = 1 
      WHERE id = ?
    `, [notificationId]);

    res.json({
      success: true,
      message: 'Notification marked as read'
    });

  } catch (error) {
    console.error('Error marking notification as read:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

module.exports = router;
