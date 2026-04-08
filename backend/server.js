const express = require('express');
const cors = require('cors');
const mysql = require('mysql2/promise');
const bodyParser = require('body-parser');

const app = express();
const port = 3000;

// Middleware
app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Database connection
const db = mysql.createPool({
  host: 'localhost',
  user: 'root',
  password: '',
  database: 'whatsapp_chat',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0
});

// Test database connection
db.getConnection()
  .then(connection => {
    console.log('Connected to MySQL database');
    connection.release();
  })
  .catch(err => {
    console.error('Database connection failed:', err);
  });

// CORS headers
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');
  next();
});

// Order Status Update API
app.put('/api/orders/:id/status', async (req, res) => {
  try {
    const { order_status, payment_status } = req.body;
    const orderId = req.params.id;
    
    console.log(`Updating order ${orderId} to status: ${order_status}`);
    
    // Update order status
    await db.query(
      'UPDATE orders SET order_status = ?, payment_status = ?, updated_at = NOW() WHERE id = ?',
      [order_status, payment_status || null, orderId]
    );
    
    // Get updated order
    const [updatedOrder] = await db.query(
      'SELECT * FROM orders WHERE id = ?',
      [orderId]
    );
    
    res.json({ 
      success: true, 
      message: `Order status updated to ${order_status}`,
      order: updatedOrder[0]
    });
  } catch (error) {
    console.error('Error updating order status:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to update order status' 
    });
  }
});

// Get Orders API (for users)
app.get('/api/orders', async (req, res) => {
  try {
    const userId = req.query.user_id;
    const { status } = req.query;
    
    let query = 'SELECT * FROM orders WHERE 1=1';
    let params = [];
    
    if (userId) {
      query += ' AND user_id = ?';
      params.push(userId);
    }
    
    if (status) {
      query += ' AND order_status = ?';
      params.push(status);
    }
    
    query += ' ORDER BY created_at DESC';
    
    const [orders] = await db.query(query, params);
    
    res.json({ 
      success: true, 
      orders: orders 
    });
  } catch (error) {
    console.error('Error fetching orders:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch orders' 
    });
  }
});

// Get Orders API (for admin)
app.get('/api/admin/orders', async (req, res) => {
  try {
    const { status, website, date_filter } = req.query;
    
    let query = `
      SELECT o.*, 
             u.name as customer_name, 
             u.phone as customer_phone
      FROM orders o 
      LEFT JOIN users u ON o.user_id = u.id
      WHERE 1=1
    `;
    let params = [];
    
    // Status filter
    if (status && status !== 'All') {
      query += ' AND o.order_status = ?';
      params.push(status);
    }
    
    // Date filter
    if (date_filter) {
      if (date_filter === 'Today') {
        query += ' AND DATE(o.created_at) = CURDATE()';
      } else if (date_filter === 'Yesterday') {
        query += ' AND DATE(o.created_at) = DATE_SUB(CURDATE(), INTERVAL 1 DAY)';
      }
    }
    
    // Website filter
    if (website) {
      query += ' AND o.website_name = ?';
      params.push(website);
    }
    
    query += ' ORDER BY o.created_at DESC';
    
    const [orders] = await db.query(query, params);
    
    res.json({ 
      success: true, 
      orders: orders 
    });
  } catch (error) {
    console.error('Error fetching admin orders:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch orders' 
    });
  }
});

// Create Order API
app.post('/api/orders', async (req, res) => {
  try {
    const {
      user_id,
      total_amount,
      order_items,
      shipping_street,
      shipping_city,
      shipping_state,
      shipping_pincode,
      customer_phone,
      customer_name,
      delivery_fee = 250
    } = req.body;
    
    console.log('Creating new order for user:', user_id);
    
    // Create order
    const [result] = await db.query(
      `INSERT INTO orders (
        user_id, total_amount, order_status, payment_status,
        shipping_street, shipping_city, shipping_state, shipping_pincode,
        customer_phone, customer_name, delivery_fee, created_at
      ) VALUES (?, ?, 'Pending', 'Pending', ?, ?, ?, ?, ?, ?, ?, NOW())`,
      [
        user_id, total_amount,
        shipping_street, shipping_city, shipping_state, shipping_pincode,
        customer_phone, customer_name, delivery_fee
      ]
    );
    
    const orderId = result.insertId;
    
    // Insert order items
    if (order_items && order_items.length > 0) {
      for (const item of order_items) {
        await db.query(
          'INSERT INTO order_items (order_id, product_name, price, quantity, color, size) VALUES (?, ?, ?, ?, ?, ?)',
          [orderId, item.product_name, item.price, item.quantity, item.color, item.size]
        );
      }
    }
    
    res.json({ 
      success: true, 
      order: { 
        id: orderId, 
        order_status: 'Pending',
        payment_status: 'Pending',
        ...req.body 
      } 
    });
  } catch (error) {
    console.error('Error creating order:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to create order' 
    });
  }
});

// WhatsApp Payment Success API
app.post('/api/whatsapp/payment-success/:orderId', async (req, res) => {
  try {
    const orderId = req.params.orderId;
    
    console.log(`Payment confirmed for order ${orderId}`);
    
    // Update order status to "Ready for Shipment"
    await db.query(
      'UPDATE orders SET order_status = ?, payment_status = ?, payment_confirmed_at = NOW() WHERE id = ?',
      ['Ready for Shipment', 'Paid', orderId]
    );
    
    res.json({ 
      success: true, 
      message: 'Payment confirmed! Order is ready for shipment.' 
    });
  } catch (error) {
    console.error('Error confirming payment:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to confirm payment' 
    });
  }
});

// Get Order by ID
app.get('/api/orders/:id', async (req, res) => {
  try {
    const orderId = req.params.id;
    
    const [order] = await db.query(
      'SELECT * FROM orders WHERE id = ?',
      [orderId]
    );
    
    if (order.length === 0) {
      return res.status(404).json({ 
        success: false, 
        message: 'Order not found' 
      });
    }
    
    // Get order items
    const [items] = await db.query(
      'SELECT * FROM order_items WHERE order_id = ?',
      [orderId]
    );
    
    res.json({ 
      success: true, 
      order: order[0],
      items: items
    });
  } catch (error) {
    console.error('Error fetching order:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch order' 
    });
  }
});

// Start server
app.listen(port, () => {
  console.log(`Server running on http://localhost:${port}`);
});

module.exports = app;
