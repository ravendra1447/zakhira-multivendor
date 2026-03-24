// Simple delivery fee update - no complex logic
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

// Simple test endpoint
router.get('/test-delivery-fee', (req, res) => {
  console.log('[SimpleDelivery] Test endpoint hit');
  res.json({
    success: true,
    message: 'Simple delivery fee test working',
    timestamp: new Date().toISOString()
  });
});

// Simple update endpoint
router.put('/update-delivery-fee/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;
    const { deliveryFee } = req.body;
    
    console.log(`[SimpleDelivery] Order: ${orderId}, Fee: ${deliveryFee}`);
    
    // Basic validation
    if (!orderId || deliveryFee === undefined) {
      return res.status(400).json({
        success: false,
        message: 'Order ID and delivery fee are required'
      });
    }
    
    const fee = parseFloat(deliveryFee);
    if (isNaN(fee)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid delivery fee format'
      });
    }
    
    // Simple update query - no column creation
    const [result] = await pool.execute(
      'UPDATE orders SET delivery_fee = ?, updated_delivery_fee = TRUE WHERE id = ?',
      [fee, parseInt(orderId)]
    );
    
    console.log(`[SimpleDelivery] Update result: ${result.affectedRows} rows`);
    
    if (result.affectedRows > 0) {
      // Get order details
      const [orders] = await pool.execute(
        'SELECT total_amount, delivery_fee FROM orders WHERE id = ?',
        [parseInt(orderId)]
      );
      
      if (orders.length > 0) {
        const order = orders[0];
        const subtotal = parseFloat(order.total_amount) || 0;
        const delivery = parseFloat(order.delivery_fee) || fee;
        const total = subtotal + delivery;
        
        console.log(`[SimpleDelivery] Success - Subtotal: ${subtotal}, Delivery: ${delivery}, Total: ${total}`);
        
        res.json({
          success: true,
          message: 'Delivery fee updated successfully',
          data: {
            delivery_fee: delivery,
            subtotal: subtotal,
            total: total
          }
        });
      } else {
        res.json({
          success: true,
          message: 'Delivery fee updated',
          data: { delivery_fee: fee, subtotal: 0, total: fee }
        });
      }
    } else {
      res.status(404).json({
        success: false,
        message: 'Order not found or no changes made'
      });
    }
    
  } catch (error) {
    console.error('[SimpleDelivery] Error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error: ' + error.message
    });
  }
});

module.exports = router;
