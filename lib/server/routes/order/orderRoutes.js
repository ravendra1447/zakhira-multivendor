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

// Create new order
router.post('/create', async (req, res) => {
  const connection = await pool.getConnection();
  
  try {
    await connection.beginTransaction();
    
    const {
      user_id,
      total_amount,
      shipping_street,
      shipping_city,
      shipping_state,
      shipping_pincode,
      shipping_phone,
      payment_method,
      items
    } = req.body;

    console.log(`Creating order for user_id: ${user_id}`); // Debug log
    console.log('Order data:', { user_id, total_amount, items }); // Debug log

    // Create order
    const [orderResult] = await connection.execute(
      `INSERT INTO orders (
        user_id, total_amount, shipping_street, shipping_city, 
        shipping_state, shipping_pincode, shipping_phone, 
        payment_method, order_status, payment_status, order_date
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())`,
      [
        user_id,
        total_amount,
        shipping_street,
        shipping_city,
        shipping_state,
        shipping_pincode,
        shipping_phone,
        payment_method,
        'Pending',
        'Pending'
      ]
    );

    const orderId = orderResult.insertId;

    // Insert order items with proper color and size names
    for (const item of items) {
      console.log('Processing item:', item); // Debug log
      
      // Get all sizes for this product
      const [sizes] = await connection.execute(
        `SELECT size FROM product_sizes WHERE product_id = ?`,
        [item.product_id]
      );
      console.log('Available sizes:', sizes); // Debug log
      
      // Get all colors for this product
      const [colors] = await connection.execute(
        `SELECT color_name FROM product_colors WHERE product_id = ?`,
        [item.product_id]
      );
      console.log('Available colors:', colors); // Debug log
      
      // Find matching size from frontend (case-insensitive)
      let sizeName = item.size || '';
      if (item.size && item.size !== '' && sizes.length > 0) {
        const foundSize = sizes.find(s => s.size && s.size.toLowerCase() === item.size.toLowerCase());
        if (foundSize) {
          sizeName = foundSize.size;
          console.log('Found size:', sizeName); // Debug log
        } else {
          console.log('Size not found:', item.size); // Debug log
        }
      }
      
      // Find matching color from frontend (case-insensitive)
      let colorName = item.color || '';
      if (item.color && item.color !== '' && colors.length > 0) {
        const foundColor = colors.find(c => c.color_name && c.color_name.toLowerCase() === item.color.toLowerCase());
        if (foundColor) {
          colorName = foundColor.color_name;
          console.log('Found color:', colorName); // Debug log
        } else {
          console.log('Color not found:', item.color); // Debug log
        }
      }

      console.log('Final values - Size:', sizeName, 'Color:', colorName); // Debug log

      // Get product details to save with order
      const [productDetails] = await connection.execute(
        `SELECT name, price, description FROM products WHERE id = ?`,
        [item.product_id]
      );

      const product = productDetails.length > 0 ? productDetails[0] : null;

      await connection.execute(
        `INSERT INTO order_items (
          order_id, product_id, quantity, price, size, color, product_name, product_price
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          orderId,
          item.product_id,
          item.quantity,
          item.price,
          sizeName,  // Use matched size from database
          colorName,  // Use matched color from database
          product ? product.name : '',  // Save product name
          product ? product.price : 0   // Save product price
        ]
      );
    }

    await connection.commit();
    
    res.json({
      success: true,
      message: 'Order created successfully',
      orderId: orderId
    });

  } catch (error) {
    await connection.rollback();
    console.error('Error creating order:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create order'
    });
  } finally {
    connection.release();
  }
});

// Get order details by ID
router.get('/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;

    // Get order details with product images
    const [orderRows] = await pool.execute(`
      SELECT 
        o.*,
        pi.image_url,
        p.product_name,
        p.product_description
      FROM orders o
      LEFT JOIN order_items oi ON o.id = oi.order_id
      LEFT JOIN products p ON oi.product_id = p.id
      LEFT JOIN product_images pi ON p.id = pi.product_id
      WHERE o.id = ?
      ORDER BY oi.id DESC
    `, [orderId]);

    if (orderRows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Order not found'
      });
    }

    // Get order items with product images
    const [itemRows] = await pool.execute(`
      SELECT 
        oi.*,
        oi.product_id,
        oi.quantity,
        oi.price,
        oi.size,
        oi.color,
        p.product_name,
        pi.image_url
      FROM order_items oi
      LEFT JOIN products p ON oi.product_id = p.id
      LEFT JOIN product_images pi ON p.id = pi.product_id
      WHERE oi.order_id = ?
      ORDER BY oi.id DESC
    `, [orderId]);

    res.json({
      success: true,
      order: orderRows[0],
      items: itemRows
    });

  } catch (error) {
    console.error('Error fetching order details:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// Get user orders
router.get('/user/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    
    console.log(`Fetching orders for user_id: ${userId}`); // Debug log

    const [orders] = await pool.execute(
      'SELECT * FROM orders WHERE user_id = ? ORDER BY order_date DESC',
      [userId]
    );

    console.log(`Found ${orders.length} orders for user ${userId}`); // Debug log
    console.log('Orders data:', orders); // Debug log

    res.json({
      success: true,
      orders
    });

  } catch (error) {
    console.error('Error fetching user orders:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// Update order status
router.patch('/:orderId/status', async (req, res) => {
  try {
    const { orderId } = req.params;
    const { order_status } = req.body;

    if (!order_status) {
      return res.status(400).json({
        success: false,
        message: 'Order status is required'
      });
    }

    const [result] = await pool.execute(
      'UPDATE orders SET order_status = ? WHERE id = ?',
      [order_status, orderId]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        message: 'Order not found'
      });
    }

    res.json({
      success: true,
      message: 'Order status updated successfully'
    });

  } catch (error) {
    console.error('Error updating order status:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// Create test order
router.post('/create-test', async (req, res) => {
  try {
    const connection = await pool.getConnection();
    await connection.beginTransaction();
    
    const {
      user_id,
      total_amount,
      shipping_street,
      shipping_city,
      shipping_state,
      shipping_pincode,
      shipping_phone,
      payment_method,
      items
    } = req.body;

    // Create order
    const [orderResult] = await connection.execute(
      `INSERT INTO orders (
        user_id, total_amount, shipping_street, shipping_city, 
        shipping_state, shipping_pincode, shipping_phone, 
        payment_method, order_status, payment_status, order_date
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())`,
      [
        user_id,
        total_amount,
        shipping_street,
        shipping_city,
        shipping_state,
        shipping_pincode,
        shipping_phone,
        payment_method,
        'Pending',
        'Pending'
      ]
    );

    const orderId = orderResult.insertId;

    // Insert order item
    await connection.execute(
      `INSERT INTO order_items (
        order_id, product_id, quantity, price, size, color, product_name, product_price
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        orderId,
        items[0].product_id,
        items[0].quantity,
        items[0].price,
        items[0].size,
        items[0].color,
        'Test Product',
        items[0].price
      ]
    );

    await connection.commit();
    
    res.json({
      success: true,
      message: 'Test order created successfully',
      orderId: orderId
    });

  } catch (error) {
    await connection.rollback();
    console.error('Error creating test order:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create test order'
    });
  } finally {
    connection.release();
  }
});

module.exports = router;
