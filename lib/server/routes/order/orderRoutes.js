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

    // Create order (without website_id)
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
      
      console.log('Product details for ID', item.product_id, ':', product); // Debug log

      // Insert order item with product name and price from products table
      const finalPrice = product?.price || item?.price || 0;
      
      console.log('Price calculation - product.price:', product?.price, 'item.price:', item?.price, 'finalPrice:', finalPrice); // Debug log
      
      await connection.execute(
        `INSERT INTO order_items (
          order_id, product_id, quantity, price, size, color, product_name
        ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [
          orderId,
          item.product_id,
          item.quantity,
          finalPrice,  // Use calculated price
          sizeName,  // Use matched size from database
          colorName,  // Use matched color from database
          product ? product.name : 'Unknown Product'  // Always get name from products table
        ]
      );
    }

    await connection.commit();
    
    // Send notifications after successful order creation
    try {
      // Check if user is admin or regular user
      const [userRole] = await connection.execute(
        `SELECT uw.role FROM user_websites uw 
         WHERE uw.user_id = ? AND uw.status = 'Y' 
         ORDER BY uw.role DESC LIMIT 1`,
        [user_id]
      );
      
      const isAdmin = userRole.length > 0 && userRole[0].role === 'admin';
      console.log('User role check - userId:', user_id, 'isAdmin:', isAdmin);

      if (isAdmin) {
        // If admin placed order, only send order confirmation to admin
        console.log('Admin placed order, sending only order confirmation');
        await fetch('https://node-api.bangkokmart.in/api/notifications/order-confirmation', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            userId: user_id,
            orderId: orderId,
            orderDetails: {
              total_amount: total_amount,
              items: items
            }
          })
        });
      } else {
        // If regular user placed order, send both notifications
        console.log('Regular user placed order, sending both notifications');
        
        // Send order confirmation to user
        await fetch('https://node-api.bangkokmart.in/api/notifications/order-confirmation', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            userId: user_id,
            orderId: orderId,
            orderDetails: {
              total_amount: total_amount,
              items: items
            }
          })
        });

        // Send new order notification to admin
        await fetch('https://node-api.bangkokmart.in/api/notifications/new-order-admin', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            orderId: orderId
          })
        });
      }

      console.log('Notifications sent successfully for order:', orderId);
    } catch (notificationError) {
      console.error('Error sending notifications:', notificationError);
      // Don't fail the order creation if notifications fail
    }
    
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
        p.name as product_name,
        p.description as product_description
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
        p.name as product_name,
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

// Get dashboard statistics
router.get('/dashboard/stats', async (req, res) => {
  try {
    // Get today's orders
    const [todayOrders] = await pool.execute(
      'SELECT COUNT(*) as count FROM orders WHERE DATE(order_date) = CURDATE()'
    );
    
    // Get yesterday's orders
    const [yesterdayOrders] = await pool.execute(
      'SELECT COUNT(*) as count FROM orders WHERE DATE(order_date) = DATE_SUB(CURDATE(), INTERVAL 1 DAY)'
    );
    
    // Get total orders
    const [totalOrders] = await pool.execute(
      'SELECT COUNT(*) as count FROM orders'
    );
    
    // Get cancelled orders
    const [cancelledOrders] = await pool.execute(
      'SELECT COUNT(*) as count FROM orders WHERE order_status = "Cancelled"'
    );
    
    // Get total revenue
    const [totalRevenue] = await pool.execute(
      'SELECT SUM(total_amount) as revenue FROM orders WHERE order_status != "Cancelled"'
    );
    
    // Get this week revenue
    const [weekRevenue] = await pool.execute(
      'SELECT SUM(total_amount) as revenue FROM orders WHERE order_status != "Cancelled" AND YEARWEEK(order_date) = YEARWEEK(CURDATE())'
    );
    
    // Get this month revenue
    const [monthRevenue] = await pool.execute(
      'SELECT SUM(total_amount) as revenue FROM orders WHERE order_status != "Cancelled" AND MONTH(order_date) = MONTH(CURDATE()) AND YEAR(order_date) = YEAR(CURDATE())'
    );

    res.json({
      success: true,
      stats: {
        todayOrders: todayOrders[0].count,
        yesterdayOrders: yesterdayOrders[0].count,
        totalOrders: totalOrders[0].count,
        cancelledOrders: cancelledOrders[0].count,
        totalRevenue: totalRevenue[0].revenue || 0,
        weekRevenue: weekRevenue[0].revenue || 0,
        monthRevenue: monthRevenue[0].revenue || 0
      }
    });

  } catch (error) {
    console.error('Error fetching dashboard stats:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// Get all orders for dashboard
router.get('/dashboard/all', async (req, res) => {
  try {
    const [orders] = await pool.execute(`
      SELECT 
        o.*,
        oi.product_name,
        pi.image_url,
        COUNT(oi.id) as item_count
      FROM orders o
      LEFT JOIN order_items oi ON o.id = oi.order_id
      LEFT JOIN product_images pi ON oi.product_id = pi.product_id
      GROUP BY o.id
      ORDER BY o.order_date DESC
    `);

    res.json({
      success: true,
      orders
    });

  } catch (error) {
    console.error('Error fetching all orders:', error);
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
        order_id, product_id, quantity, price, size, color, product_name
      ) VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [
        orderId,
        items[0].product_id,
        items[0].quantity,
        items[0].price,
        items[0].size,
        items[0].color,
        'Test Product'
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

// Get orders for a specific website (admin only)
router.get('/website/:websiteId', async (req, res) => {
  try {
    const { websiteId } = req.params;
    
    const [orders] = await pool.execute(`
      SELECT DISTINCT o.*, u.name as customer_name, u.normalized_phone as customer_phone, w.website_name
      FROM orders o
      INNER JOIN users u ON o.user_id = u.user_id
      INNER JOIN user_websites uw ON u.user_id = uw.user_id
      INNER JOIN websites w ON uw.website_id = w.website_id
      WHERE uw.website_id = ? AND uw.status = 'Y'
      ORDER BY o.order_date DESC
    `, [websiteId]);

    res.json({
      success: true,
      orders
    });

  } catch (error) {
    console.error('Error fetching website orders:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// Get admin dashboard statistics (for admin users)
router.get('/admin/dashboard', async (req, res) => {
  try {
    const { userId } = req.query;
    
    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'User ID is required'
      });
    }

    // Check if user is admin for any website
    const [adminWebsites] = await pool.execute(`
      SELECT DISTINCT w.website_id, w.website_name, w.domain
      FROM websites w
      INNER JOIN user_websites uw ON w.website_id = uw.website_id
      WHERE uw.user_id = ? AND uw.role = 'admin' AND uw.status = 'Y'
    `, [userId]);

    if (adminWebsites.length === 0) {
      return res.status(403).json({
        success: false,
        message: 'User is not an admin for any website'
      });
    }

    // Get website IDs for admin
    const websiteIds = adminWebsites.map(w => w.website_id);
    
    // Get all orders for these websites (using user_websites table)
    const [orders] = await pool.execute(`
      SELECT DISTINCT o.*, u.name as customer_name, u.normalized_phone as customer_phone, w.website_name
      FROM orders o
      INNER JOIN users u ON o.user_id = u.user_id
      INNER JOIN user_websites uw ON u.user_id = uw.user_id
      INNER JOIN websites w ON uw.website_id = w.website_id
      WHERE uw.website_id IN (${websiteIds.map(() => '?').join(',')}) AND uw.status = 'Y'
      ORDER BY o.order_date DESC
    `, websiteIds);

    // Get all products for these websites (using product_domain_visibility table)
    const [products] = await pool.execute(`
      SELECT DISTINCT p.*, pi.image_url, pdv.domain_id as website_id
      FROM products p
      LEFT JOIN product_images pi ON p.id = pi.product_id
      LEFT JOIN product_domain_visibility pdv ON p.id = pdv.product_id
      WHERE pdv.domain_id IN (${websiteIds.map(() => '?').join(',')}) AND pdv.is_visible = 1
      ORDER BY p.created_at DESC
    `, websiteIds);

    // Calculate statistics
    const today = new Date();
    const todayOrders = orders.filter(order => {
      const orderDate = new Date(order.order_date);
      return orderDate.toDateString() === today.toDateString();
    });

    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayOrders = orders.filter(order => {
      const orderDate = new Date(order.order_date);
      return orderDate.toDateString() === yesterday.toDateString();
    });

    const cancelledOrders = orders.filter(order => 
      order.order_status?.toLowerCase() === 'cancelled'
    );

    const totalRevenue = orders
      .filter(order => order.order_status?.toLowerCase() !== 'cancelled')
      .reduce((sum, order) => sum + parseFloat(order.total_amount || 0), 0);

    const weekRevenue = orders
      .filter(order => {
        const orderDate = new Date(order.order_date);
        const weekStart = new Date(today);
        weekStart.setDate(today.getDate() - today.getDay());
        return orderDate >= weekStart && order.order_status?.toLowerCase() !== 'cancelled';
      })
      .reduce((sum, order) => sum + parseFloat(order.total_amount || 0), 0);

    const monthRevenue = orders
      .filter(order => {
        const orderDate = new Date(order.order_date);
        return orderDate.getMonth() === today.getMonth() && 
               orderDate.getFullYear() === today.getFullYear() &&
               order.order_status?.toLowerCase() !== 'cancelled';
      })
      .reduce((sum, order) => sum + parseFloat(order.total_amount || 0), 0);

    res.json({
      success: true,
      data: {
        websites: adminWebsites,
        stats: {
          todayOrders: todayOrders.length,
          yesterdayOrders: yesterdayOrders.length,
          totalOrders: orders.length,
          cancelledOrders: cancelledOrders.length,
          totalRevenue: totalRevenue,
          weekRevenue: weekRevenue,
          monthRevenue: monthRevenue
        },
        orders: orders,
        products: products
      }
    });

  } catch (error) {
    console.error('Error fetching admin dashboard:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

module.exports = router;
