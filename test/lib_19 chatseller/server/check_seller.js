const mysql = require('mysql2/promise');
const pool = mysql.createPool({
  host: 'localhost',
  user: 'chatuser',
  password: 'chat1234#db',
  database: 'chat_db'
});

async function checkSeller() {
  try {
    // Check recent order and seller details
    const [orderItems] = await pool.execute(`
      SELECT oi.product_id, p.user_id as seller_id, p.name as product_name, u.name as seller_name, u.fcm_token
      FROM order_items oi
      INNER JOIN products p ON oi.product_id = p.id
      INNER JOIN users u ON p.user_id = u.user_id
      WHERE oi.order_id = 205
    `);
    
    console.log('📋 Order 205 - Seller Details:');
    console.log(JSON.stringify(orderItems, null, 2));
    
    // Also check if seller has valid FCM token
    for (const item of orderItems) {
      if (!item.fcm_token) {
        console.log(`❌ Seller ${item.seller_name} (ID: ${item.seller_id}) has NO FCM token!`);
      } else {
        console.log(`✅ Seller ${item.seller_name} (ID: ${item.seller_id}) has FCM token: ${item.fcm_token.substring(0, 20)}...`);
      }
    }
    
    process.exit(0);
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

checkSeller();
