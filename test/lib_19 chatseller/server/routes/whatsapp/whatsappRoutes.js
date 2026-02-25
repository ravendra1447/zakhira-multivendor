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

// Log WhatsApp message
router.post('/log-message', async (req, res) => {
  try {
    const {
      order_id,
      phone_number,
      message,
      sent_at
    } = req.body;

    if (!order_id || !phone_number || !message) {
      return res.status(400).json({
        success: false,
        message: 'Order ID, phone number, and message are required'
      });
    }

    // Create table if it doesn't exist
    await pool.execute(`
      CREATE TABLE IF NOT EXISTS whatsapp_messages (
        id INT AUTO_INCREMENT PRIMARY KEY,
        order_id INT NOT NULL,
        phone_number VARCHAR(20) NOT NULL,
        message TEXT NOT NULL,
        sent_at DATETIME NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_order_id (order_id),
        INDEX idx_phone_number (phone_number)
      )
    `);

    // Insert message log
    const [result] = await pool.execute(
      'INSERT INTO whatsapp_messages (order_id, phone_number, message, sent_at) VALUES (?, ?, ?, ?)',
      [order_id, phone_number, message, sent_at || new Date().toISOString()]
    );

    res.json({
      success: true,
      message: 'WhatsApp message logged successfully',
      log_id: result.insertId
    });

  } catch (error) {
    console.error('Error logging WhatsApp message:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// Get WhatsApp messages for an order
router.get('/messages/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;

    const [messages] = await pool.execute(
      'SELECT * FROM whatsapp_messages WHERE order_id = ? ORDER BY sent_at DESC',
      [orderId]
    );

    res.json({
      success: true,
      messages: messages
    });

  } catch (error) {
    console.error('Error fetching WhatsApp messages:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// Check if WhatsApp message was sent for an order
router.get('/message-sent/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;

    const [messages] = await pool.execute(
      'SELECT COUNT(*) as count, sent_at FROM whatsapp_messages WHERE order_id = ? ORDER BY sent_at DESC LIMIT 1',
      [orderId]
    );

    const messageSent = messages.length > 0 && messages[0].count > 0;
    const lastSentAt = messageSent ? messages[0].sent_at : null;

    res.json({
      success: true,
      message_sent: messageSent,
      last_sent_at: lastSentAt
    });

  } catch (error) {
    console.error('Error checking WhatsApp message status:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// Automated payment status check (for monitoring)
router.post('/check-payment/:orderId', async (req, res) => {
  try {
    const { orderId } = req.params;

    // Get order details
    const [orderDetails] = await pool.execute(
      'SELECT * FROM orders WHERE id = ?',
      [orderId]
    );

    if (orderDetails.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Order not found'
      });
    }

    const order = orderDetails[0];
    const orderDate = new Date(order.order_date);
    const currentTime = new Date();
    const timeDiff = (currentTime - orderDate) / (1000 * 60); // Difference in minutes

    // Check if WhatsApp message was sent
    const [whatsappCheck] = await pool.execute(
      'SELECT sent_at FROM whatsapp_messages WHERE order_id = ? ORDER BY sent_at DESC LIMIT 1',
      [orderId]
    );

    const whatsappSent = whatsappCheck.length > 0;
    let whatsappSentAt = null;
    let paymentWindowExpired = false;

    if (whatsappSent) {
      whatsappSentAt = whatsappCheck[0].sent_at;
      const whatsappSentTime = new Date(whatsappSentAt);
      const paymentTimeDiff = (currentTime - whatsappSentTime) / (1000 * 60);
      paymentWindowExpired = paymentTimeDiff > 5;
    }

    res.json({
      success: true,
      order_id: orderId,
      payment_status: order.payment_status,
      order_status: order.order_status,
      time_elapsed_minutes: Math.round(timeDiff),
      whatsapp_sent: whatsappSent,
      whatsapp_sent_at: whatsappSentAt,
      payment_window_expired: paymentWindowExpired,
      is_within_5_minutes: timeDiff <= 5
    });

  } catch (error) {
    console.error('Error checking payment status:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

module.exports = router;
