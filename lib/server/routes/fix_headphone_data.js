const mysql = require("mysql2/promise");

// Database connection
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db",
});

async function fixHeadphoneData() {
  console.log("=== FIXING HEADPHONE DATA CORRUPTION ===");
  
  try {
    // 1. Create backup before fixing
    console.log("Step 1: Creating backup...");
    const timestamp = Date.now();
    await pool.execute(`
      CREATE TABLE product_variants_backup_${timestamp} AS
      SELECT * FROM product_variants WHERE price = 750 AND stock = 10
    `);
    console.log(`Backup created: product_variants_backup_${timestamp}`);

    // 2. Show current corrupted data
    console.log("Step 2: Current corrupted data:");
    const [corruptedData] = await pool.execute(`
      SELECT 
        pv.id,
        pv.product_id,
        p.name as product_name,
        p.price as original_price,
        pv.color_name,
        pv.size,
        pv.price as corrupted_price,
        pv.stock as corrupted_stock
      FROM product_variants pv
      JOIN products p ON pv.product_id = p.id
      WHERE pv.price = 750 AND pv.stock = 10
      ORDER BY pv.product_id, pv.color_name, pv.size
    `);
    
    console.log("Corrupted variants:");
    corruptedData.forEach(variant => {
      console.log(`  ID: ${variant.id}, Product: ${variant.product_name}, Color: ${variant.color_name}, Size: ${variant.size}, Corrupted Price: ${variant.corrupted_price}, Original Price: ${variant.original_price}`);
    });

    // 3. Fix the corrupted variants
    console.log("Step 3: Fixing corrupted variants...");
    
    let fixedCount = 0;
    for (const variant of corruptedData) {
      const originalPrice = variant.original_price || 1550; // Use original price or default to 1550
      const newStock = 50; // Set reasonable stock instead of 10
      
      await pool.execute(`
        UPDATE product_variants 
        SET price = ?, stock = ?
        WHERE id = ?
      `, [originalPrice, newStock, variant.id]);
      
      console.log(`Fixed variant ${variant.id}: ${variant.product_name} - ${variant.color_name} ${variant.size} -> Price: ${originalPrice}, Stock: ${newStock}`);
      fixedCount++;
    }

    // 4. Verify the fix
    console.log("Step 4: Verifying the fix...");
    const [verification] = await pool.execute(`
      SELECT 
        pv.product_id,
        p.name as product_name,
        COUNT(pv.id) as total_variants,
        AVG(pv.price) as avg_price,
        MIN(pv.price) as min_price,
        MAX(pv.price) as max_price
      FROM product_variants pv
      JOIN products p ON pv.product_id = p.id
      WHERE pv.product_id IN (177, 178)
      GROUP BY pv.product_id, p.name
    `);
    
    console.log("Verification results:");
    verification.forEach(result => {
      console.log(`  Product: ${result.product_name}, Variants: ${result.total_variants}, Price Range: ${result.min_price} - ${result.max_price}`);
    });

    // 5. Check if any corrupted variants remain
    const [remainingCorrupted] = await pool.execute(`
      SELECT COUNT(*) as remaining_count
      FROM product_variants 
      WHERE price = 750 AND stock = 10
    `);
    
    console.log(`\n=== FIX COMPLETED ===`);
    console.log(`Fixed variants: ${fixedCount}`);
    console.log(`Remaining corrupted variants: ${remainingCorrupted[0].remaining_count}`);
    console.log(`Backup table: product_variants_backup_${timestamp}`);
    
    if (remainingCorrupted[0].remaining_count === 0) {
      console.log("SUCCESS: All corrupted variants have been fixed!");
    } else {
      console.log("WARNING: Some corrupted variants still remain");
    }

  } catch (error) {
    console.error("Fix failed:", error);
  } finally {
    await pool.end();
  }
}

// Run the fix
fixHeadphoneData();
