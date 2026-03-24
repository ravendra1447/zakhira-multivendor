const mysql = require('mysql2/promise');

// DB Connection
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db"
});

async function runMigration() {
  const connection = await pool.getConnection();
  
  try {
    console.log('Running migration to fix order_items schema...');
    
    // Check current table structure
    const [columns] = await connection.execute('DESCRIBE order_items');
    console.log('Current order_items columns:');
    columns.forEach(col => console.log(`- ${col.Field} (${col.Type})`));
    
    // Add product_name column if it doesn't exist
    const hasProductName = columns.some(col => col.Field === 'product_name');
    if (!hasProductName) {
      await connection.execute('ALTER TABLE order_items ADD COLUMN product_name VARCHAR(255) AFTER color');
      console.log('✓ Added product_name column');
    } else {
      console.log('✓ product_name column already exists');
    }
    
    // Add product_price column if it doesn't exist
    const hasProductPrice = columns.some(col => col.Field === 'product_price');
    if (!hasProductPrice) {
      await connection.execute('ALTER TABLE order_items ADD COLUMN product_price DECIMAL(10,2) AFTER product_name');
      console.log('✓ Added product_price column');
    } else {
      console.log('✓ product_price column already exists');
    }
    
    console.log('Migration completed successfully!');
    
  } catch (error) {
    console.error('Migration failed:', error);
  } finally {
    connection.release();
    await pool.end();
  }
}

runMigration();
