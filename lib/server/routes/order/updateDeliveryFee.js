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

// Test endpoint to verify route is working
router.get('/test-delivery-fee', (req, res) => {
  console.log('[DeliveryFee] Test endpoint hit successfully');
  res.json({
    success: true,
    message: 'Delivery fee routes are working',
    timestamp: new Date().toISOString()
  });
});

// Simple update delivery fee for an order
router.put('/update-delivery-fee/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;
    const { deliveryFee } = req.body;
    
    console.log(`[DeliveryFee] Order: ${orderId}, Fee: ${deliveryFee}`);
    
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
    
    // Simple update query
    const [result] = await pool.execute(
      'UPDATE orders SET delivery_fee = ?, updated_delivery_fee = TRUE WHERE id = ?',
      [fee, parseInt(orderId)]
    );
    
    console.log(`[DeliveryFee] Update result: ${result.affectedRows} rows affected`);
    
    if (result.affectedRows > 0) {
      // Get updated order details
      const [orders] = await pool.execute(
        'SELECT total_amount, delivery_fee FROM orders WHERE id = ?',
        [parseInt(orderId)]
      );
      
      if (orders.length > 0) {
        const order = orders[0];
        const subtotalAmount = parseFloat(order.total_amount) || 0;
        const newDeliveryFee = parseFloat(order.delivery_fee) || fee;
        const totalAmount = subtotalAmount + newDeliveryFee;
        
        console.log(`[DeliveryFee] Success - Subtotal: ${subtotalAmount}, Delivery: ${newDeliveryFee}, Total: ${totalAmount}`);
        
        res.json({
          success: true,
          message: 'Delivery fee updated successfully',
          data: {
            delivery_fee: newDeliveryFee,
            subtotal: subtotalAmount,
            total: totalAmount
          }
        });
      } else {
        res.json({
          success: true,
          message: 'Delivery fee updated successfully',
          data: {
            delivery_fee: fee,
            subtotal: 0,
            total: fee
          }
        });
      }
    } else {
      res.status(404).json({
        success: false,
        message: 'Order not found or no changes made'
      });
    }
  } catch (error) {
    console.error('[DeliveryFee] Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update delivery fee: ' + error.message
    });
  }
});

// Get delivery fee for an order
router.get('/get-delivery-fee/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;
    
    const [orders] = await pool.execute(
      'SELECT total_amount, delivery_fee, updated_delivery_fee FROM orders WHERE id = ?',
      [parseInt(orderId)]
    );
    
    if (orders.length > 0) {
      const order = orders[0];
      const subtotalAmount = parseFloat(order.total_amount) || 0;
      let deliveryFee = 250; // Default
      
      // Use manual delivery fee if updated
      if (order.updated_delivery_fee && order.delivery_fee !== null) {
        deliveryFee = parseFloat(order.delivery_fee) || 250;
      }
      
      const totalAmount = subtotalAmount + deliveryFee;
      
      res.json({
        success: true,
        data: {
          delivery_fee: deliveryFee,
          subtotal: subtotalAmount,
          total: totalAmount,
          is_manual: order.updated_delivery_fee || false
        }
      });
    } else {
      res.status(404).json({
        success: false,
        message: 'Order not found'
      });
    }
  } catch (error) {
    console.error('Error fetching delivery fee:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch delivery fee'
    });
  }
});

module.exports = router;
