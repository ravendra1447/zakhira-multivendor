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

// Send order confirmation to user
router.post('/order-confirmation', async (req, res) => {
  try {
    const { userId, orderId, orderDetails } = req.body;
    
    if (!userId || !orderId) {
      return res.status(400).json({
        success: false,
        message: 'User ID and Order ID are required'
      });
    }

    // Get user details
    const [users] = await pool.execute(`
      SELECT name, email, normalized_phone, fcm_token
      FROM users 
      WHERE user_id = ?
    `, [userId]);

    if (users.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const user = users[0];
    
    // Get order details with products
    const [orderItems] = await pool.execute(`
      SELECT oi.*, p.name as product_name, p.price
      FROM order_items oi
      INNER JOIN products p ON oi.product_id = p.id
      WHERE oi.order_id = ?
    `, [orderId]);

    // Get order details
    const [orders] = await pool.execute(`
      SELECT total_amount, order_status, order_date, 
             shipping_street, shipping_city, shipping_state, shipping_pincode, shipping_phone
      FROM orders
      WHERE id = ?
    `, [orderId]);

    if (orders.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Order not found'
      });
    }

    const order = orders[0];

    // 1. Send FCM notification to user
    if (user.fcm_token) {
      try {
        await sendFCMNotification(
          user.fcm_token,
          'Order Confirmed! 🎉',
          `Your order #${orderId} has been placed successfully. Amount: ₹${order.total_amount}`,
          {
            type: 'order_confirmation',
            orderId: orderId.toString(),
            amount: order.total_amount.toString(),
            timestamp: new Date().toISOString()
          }
        );
      } catch (fcmError) {
        console.log('FCM notification failed for user, but continuing with other notifications:', fcmError.message);
      }
    }

    // 2. Send SMS notification
    const smsMessage = `WhatsAppMart: Your order #${orderId} has been confirmed. Amount: ₹${order.total_amount}. Thank you for shopping!`;
    await sendSMS(user.normalized_phone, smsMessage);

    // 3. Send email notification
    const emailSubject = `Order Confirmation - Order #${orderId}`;
    const emailBody = generateOrderConfirmationEmail(user, order, orderItems);
    await sendEmail(user.email, emailSubject, emailBody);

    // 4. Store notification in database
    await pool.execute(`
      INSERT INTO notifications (user_id, type, title, message, data, created_at)
      VALUES (?, 'order_confirmation', ?, ?, ?, NOW())
    `, [
      userId,
      'Order Confirmed! 🎉',
      `Your order #${orderId} has been placed successfully. Amount: ₹${order.total_amount}`,
      JSON.stringify({
        orderId: orderId,
        amount: order.total_amount,
        timestamp: new Date().toISOString()
      })
    ]);

    res.json({
      success: true,
      message: 'Order confirmation notifications sent successfully',
      notifications: {
        fcm: user.fcm_token ? 'sent' : 'no_fcm_token',
        sms: 'sent',
        email: 'sent',
        database: 'stored'
      }
    });

  } catch (error) {
    console.error('Error sending order confirmation:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// Send new order notification to admin
router.post('/new-order-admin', async (req, res) => {
  try {
    const { orderId, adminIds } = req.body;
    
    if (!orderId) {
      return res.status(400).json({
        success: false,
        message: 'Order ID is required'
      });
    }

    // Get order details with website information
    const [orderDetails] = await pool.execute(`
      SELECT o.*, u.name as customer_name, u.normalized_phone as customer_phone, w.website_name
      FROM orders o
      INNER JOIN users u ON o.user_id = u.user_id
      LEFT JOIN user_websites uw ON u.user_id = uw.user_id
      LEFT JOIN websites w ON uw.website_id = w.website_id
      WHERE o.id = ?
    `, [orderId]);

    if (orderDetails.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Order not found'
      });
    }

    const order = orderDetails[0];

    // Get admin users for this website using user's website_id from user_websites table
    console.log('Finding admins for user_id:', order.user_id); // Debug log
    
    // First check user's website
    const [userWebsite] = await pool.execute(
      `SELECT website_id FROM user_websites WHERE user_id = ? AND status = 'Y' LIMIT 1`,
      [order.user_id]
    );
    console.log('User website details:', userWebsite); // Debug log
    
    if (userWebsite.length === 0) {
      console.log('No website found for user:', order.user_id);
      return res.status(404).json({
        success: false,
        message: 'No website found for this user'
      });
    }
    
    const userWebsiteId = userWebsite[0].website_id;
    console.log('User website_id:', userWebsiteId); // Debug log
    
    // Now check all admins for this website
    const [allAdmins] = await pool.execute(
      `SELECT u.user_id, u.name, u.email, u.fcm_token, uw.role, uw.website_id, uw.status
       FROM users u
       INNER JOIN user_websites uw ON u.user_id = uw.user_id
       WHERE uw.website_id = ? AND uw.role = 'admin'`,
      [userWebsiteId]
    );
    console.log('All admins for website', userWebsiteId, ':', allAdmins); // Debug log
    
    // Filter out the user who placed the order
    const adminUsers = allAdmins.filter(admin => admin.user_id != order.user_id);
    console.log('Filtered admin users (excluding order user):', adminUsers); // Debug log

    if (adminUsers.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'No admin users found for this website'
      });
    }

    // Get order items for admin notification
    const [orderItems] = await pool.execute(`
      SELECT oi.*, p.name as product_name
      FROM order_items oi
      INNER JOIN products p ON oi.product_id = p.id
      WHERE oi.order_id = ?
    `, [orderId]);

    let notificationsSent = 0;

    // Send notifications to all admin users
    for (const admin of adminUsers) {
      // 1. Send FCM notification to admin
      if (admin.fcm_token) {
        try {
          await sendFCMNotification(
            admin.fcm_token,
            'New Order Received! 📦',
            `Order #${orderId} from ${order.customer_name}. Amount: ₹${order.total_amount}`,
            {
              type: 'new_order_admin',
              orderId: orderId.toString(),
              customerName: order.customer_name,
              amount: order.total_amount.toString(),
              website: order.website_name,
              timestamp: new Date().toISOString()
            }
          );
        } catch (fcmError) {
          console.log(`FCM notification failed for admin ${admin.name}, but continuing with other notifications:`, fcmError.message);
        }
      }

      // 2. Send email to admin
      const adminEmailSubject = `New Order Received - Order #${orderId}`;
      const adminEmailBody = generateNewOrderEmail(admin, order, orderItems);
      await sendEmail(admin.email, adminEmailSubject, adminEmailBody);

      // 3. Store admin notification in database
      await pool.execute(`
        INSERT INTO notifications (user_id, type, title, message, data, created_at)
        VALUES (?, 'new_order_admin', ?, ?, ?, NOW())
      `, [
        admin.user_id,
        'New Order Received! 📦',
        `Order #${orderId} from ${order.customer_name}. Amount: ₹${order.total_amount}`,
        JSON.stringify({
          orderId: orderId,
          customerName: order.customer_name,
          amount: order.total_amount,
          website: order.website_name,
          websiteId: admin.website_id,
          adminRole: admin.role,
          adminUserId: admin.user_id,
          timestamp: new Date().toISOString()
        })
      ]);

      notificationsSent++;
    }

    res.json({
      success: true,
      message: `Admin notifications sent to ${notificationsSent} admin users`,
      notificationsSent: notificationsSent,
      adminUsers: adminUsers.length
    });

  } catch (error) {
    console.error('Error sending admin notifications:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error'
    });
  }
});

// FCM Notification Helper Function
async function sendFCMNotification(token, title, body, data = {}) {
  try {
    const admin = require('firebase-admin');
    
    if (!admin.apps.length) {
      const serviceAccount = require('../../firebase-service-account.json');
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
      });
    }

    const message = {
      token: token,
      notification: {
        title: title,
        body: body,
      },
      data: data,
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        }
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        }
      }
    };

    const response = await admin.messaging().send(message);
    console.log('FCM notification sent successfully:', response);
    return response;

  } catch (error) {
    console.error('Error sending FCM notification:', error);
    
    // Handle invalid/expired FCM tokens gracefully
    if (error.code === 'messaging/registration-token-not-registered') {
      console.log('FCM token is invalid or expired, removing from database...');
      
      // Remove invalid token from database (optional)
      // await pool.execute('UPDATE users SET fcm_token = NULL WHERE fcm_token = ?', [fcmToken]);
      
      // Don't throw error, just log it
      return { success: false, message: 'Invalid FCM token' };
    }
    
    throw error;
  }
}

// SMS Helper Function
async function sendSMS(phoneNumber, message) {
  try {
    // Integrate with SMS service (like Twilio, MessageBird, etc.)
    // For now, we'll just log the message
    console.log(`SMS to ${phoneNumber}: ${message}`);
    
    // Example with Twilio (uncomment and configure):
    /*
    const twilio = require('twilio');
    const client = twilio(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
    
    await client.messages.create({
      body: message,
      from: process.env.TWILIO_PHONE_NUMBER,
      to: phoneNumber
    });
    */
    
    return { success: true, message: 'SMS logged (implement SMS service)' };

  } catch (error) {
    console.error('Error sending SMS:', error);
    throw error;
  }
}

// Email Helper Function
async function sendEmail(to, subject, body) {
  try {
    // Integrate with email service (like Nodemailer, SendGrid, etc.)
    // For now, we'll just log the email
    console.log(`Email to ${to}: ${subject}`);
    console.log(`Body: ${body}`);
    
    // Example with Nodemailer (uncomment and configure):
    /*
    const nodemailer = require('nodemailer');
    const transporter = nodemailer.createTransporter({
      service: 'gmail',
      auth: {
        user: process.env.EMAIL_USER,
        pass: process.env.EMAIL_PASS
      }
    });
    
    await transporter.sendMail({
      from: process.env.EMAIL_USER,
      to: to,
      subject: subject,
      html: body
    });
    */
    
    return { success: true, message: 'Email logged (implement email service)' };

  } catch (error) {
    console.error('Error sending email:', error);
    throw error;
  }
}

// Generate Order Confirmation Email
function generateOrderConfirmationEmail(user, order, orderItems) {
  const itemsHtml = orderItems.map(item => `
    <tr>
      <td style="padding: 10px; border-bottom: 1px solid #eee;">${item.product_name}</td>
      <td style="padding: 10px; border-bottom: 1px solid #eee;">${item.quantity}</td>
      <td style="padding: 10px; border-bottom: 1px solid #eee;">₹${item.price}</td>
      <td style="padding: 10px; border-bottom: 1px solid #eee;">₹${item.price * item.quantity}</td>
    </tr>
  `).join('');

  return `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Order Confirmation</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f4f4f4; }
        .container { max-width: 600px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; }
        .header { text-align: center; padding: 20px 0; border-bottom: 2px solid #4CAF50; }
        .order-info { padding: 20px 0; }
        .table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        .total { text-align: right; font-size: 18px; font-weight: bold; color: #4CAF50; }
        .footer { text-align: center; padding: 20px 0; color: #666; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>Order Confirmed! 🎉</h1>
          <p>Thank you for your order, ${user.name}!</p>
        </div>
        
        <div class="order-info">
          <h2>Order Details</h2>
          <p><strong>Order ID:</strong> #${order.id}</p>
          <p><strong>Date:</strong> ${new Date(order.order_date).toLocaleDateString()}</p>
          <p><strong>Status:</strong> ${order.order_status}</p>
        </div>

        <h3>Order Items</h3>
        <table class="table">
          <thead>
            <tr>
              <th style="padding: 10px; text-align: left; border-bottom: 2px solid #4CAF50;">Product</th>
              <th style="padding: 10px; text-align: center; border-bottom: 2px solid #4CAF50;">Quantity</th>
              <th style="padding: 10px; text-align: right; border-bottom: 2px solid #4CAF50;">Price</th>
              <th style="padding: 10px; text-align: right; border-bottom: 2px solid #4CAF50;">Total</th>
            </tr>
          </thead>
          <tbody>
            ${itemsHtml}
          </tbody>
        </table>

        <div class="total">
          Total Amount: ₹${order.total_amount}
        </div>

        <div class="footer">
          <p>Thank you for shopping with us!</p>
          <p>For any queries, contact our support team.</p>
        </div>
      </div>
    </body>
    </html>
  `;
}

// Generate New Order Email for Admin
function generateNewOrderEmail(admin, order, orderItems) {
  const itemsHtml = orderItems.map(item => `
    <tr>
      <td style="padding: 10px; border-bottom: 1px solid #eee;">${item.product_name}</td>
      <td style="padding: 10px; border-bottom: 1px solid #eee;">${item.quantity}</td>
      <td style="padding: 10px; border-bottom: 1px solid #eee;">₹${item.price}</td>
    </tr>
  `).join('');

  return `
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>New Order Received</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f4f4f4; }
        .container { max-width: 600px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; }
        .header { text-align: center; padding: 20px 0; border-bottom: 2px solid #FF6B6B; }
        .order-info { padding: 20px 0; }
        .table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        .alert { background-color: #FF6B6B; color: white; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .footer { text-align: center; padding: 20px 0; color: #666; }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>📦 New Order Received!</h1>
          <p>Hello ${admin.name},</p>
        </div>
        
        <div class="alert">
          <strong>Action Required:</strong> You have received a new order that needs your attention.
        </div>

        <div class="order-info">
          <h2>Order Details</h2>
          <p><strong>Order ID:</strong> #${order.id}</p>
          <p><strong>Customer:</strong> ${order.customer_name}</p>
          <p><strong>Phone:</strong> ${order.customer_phone}</p>
          <p><strong>Website:</strong> ${order.website_name}</p>
          <p><strong>Date:</strong> ${new Date(order.order_date).toLocaleDateString()}</p>
          <p><strong>Total Amount:</strong> <strong>₹${order.total_amount}</strong></p>
        </div>

        <h3>Order Items</h3>
        <table class="table">
          <thead>
            <tr>
              <th style="padding: 10px; text-align: left; border-bottom: 2px solid #FF6B6B;">Product</th>
              <th style="padding: 10px; text-align: center; border-bottom: 2px solid #FF6B6B;">Quantity</th>
              <th style="padding: 10px; text-align: right; border-bottom: 2px solid #FF6B6B;">Price</th>
            </tr>
          </thead>
          <tbody>
            ${itemsHtml}
          </tbody>
        </table>

        <div class="footer">
          <p>Please process this order as soon as possible.</p>
          <p>Check your admin dashboard for more details.</p>
        </div>
      </div>
    </body>
    </html>
  `;
}

module.exports = router;
