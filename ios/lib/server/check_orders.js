const mysql = require('mysql2/promise');
const pool = mysql.createPool({
  host: 'localhost',
  user: 'chatuser',
  password: 'chat1234#db',
  database: 'chat_db'
});

async function checkSellerOrders() {
  try {
    const sellerId = 32;
    
    // Check orders for seller ID 32
    const [orders] = await pool.execute(`
      SELECT COUNT(DISTINCT o.id) as total_orders
      FROM orders o
      INNER JOIN order_items oi ON o.id = oi.order_id
      INNER JOIN products p ON oi.product_id = p.id
      WHERE p.user_id = ?
    `, [sellerId]);

    console.log(`📊 Seller ${sellerId} Total Orders: ${orders[0].total_orders}`);
    
    // Check individual orders
    const [orderDetails] = await pool.execute(`
      SELECT DISTINCT 
        o.id,
        o.order_date,
        o.total_amount,
        o.order_status,
        p.name as product_name,
        p.user_id as seller_id
      FROM orders o
      INNER JOIN order_items oi ON o.id = oi.order_id
      INNER JOIN products p ON oi.product_id = p.id
      WHERE p.user_id = ?
      ORDER BY o.order_date DESC
      LIMIT 10
    `, [sellerId]);

    console.log(`📋 Recent Orders for Seller ${sellerId}:`);
    console.log(JSON.stringify(orderDetails, null, 2));
    
    // Check if seller has products
    const [products] = await pool.execute(`
      SELECT id, name, user_id, status
      FROM products
      WHERE user_id = ?
      LIMIT 5
    `, [sellerId]);

    console.log(`📦 Seller ${sellerId} Products:`);
    console.log(JSON.stringify(products, null, 2));
    
    process.exit(0);
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

checkSellerOrders();
