const mysql = require("mysql2/promise");

// Database connection
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db",
});

async function checkExistingBackups() {
  console.log("=== CHECKING EXISTING BACKUP TABLES ===");
  
  try {
    // Check for existing backup tables
    const [backupTables] = await pool.execute(`
      SHOW TABLES LIKE 'product_variants_backup%'
    `);
    
    console.log("Existing backup tables:");
    if (backupTables.length === 0) {
      console.log("  No backup tables found");
    } else {
      backupTables.forEach(table => {
        const tableName = Object.values(table)[0];
        console.log(`  - ${tableName}`);
      });
    }
    
    // Check if there's already a product_variants_backup table
    const [specificBackup] = await pool.execute(`
      SHOW TABLES LIKE 'product_variants_backup'
    `);
    
    if (specificBackup.length > 0) {
      console.log("\n⚠️  'product_variants_backup' table already exists!");
      
      // Check what's in it
      const [backupData] = await pool.execute(`
        SELECT COUNT(*) as count FROM product_variants_backup
      `);
      
      console.log(`  Records in backup: ${backupData[0].count}`);
      
      // Show sample data
      const [sampleData] = await pool.execute(`
        SELECT * FROM product_variants_backup LIMIT 3
      `);
      
      if (sampleData.length > 0) {
        console.log("  Sample data:");
        console.log(sampleData);
      }
      
      console.log("\n📋 Options:");
      console.log("1. Use existing backup: product_variants_backup");
      console.log("2. Create new backup with timestamp: product_variants_backup_" + Date.now());
      console.log("3. Drop existing backup and create new one");
      
    } else {
      console.log("\n✅ No 'product_variants_backup' table exists - safe to create new backup");
    }
    
  } catch (error) {
    console.error("Error checking backups:", error);
  } finally {
    await pool.end();
  }
}

// Run check
checkExistingBackups();
