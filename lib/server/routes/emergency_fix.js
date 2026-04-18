const mysql = require("mysql2/promise");

// Database connection
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db",
});

async function emergencyFix() {
  console.log("=== EMERGENCY FIX STARTING ===");
  
  try {
    // 1. First, identify corrupted variants
    console.log("Step 1: Finding corrupted variants...");
    const [corruptedVariants] = await pool.execute(`
      SELECT 
        pv.id,
        pv.product_id,
        pv.color_name,
        pv.size,
        pv.price,
        pv.stock,
        p.name as product_name,
        p.price as original_product_price
      FROM product_variants pv
      JOIN products p ON pv.product_id = p.id
      WHERE pv.price = 750 AND pv.stock = 10
      ORDER BY pv.product_id, pv.color_name, pv.size
    `);
    
    console.log(`Found ${corruptedVariants.length} corrupted variants`);
    
    if (corruptedVariants.length > 0) {
      console.log("Sample corrupted data:");
      console.log(corruptedVariants.slice(0, 5));
      
      // 2. Create backup before fixing
      console.log("Step 2: Creating backup...");
      const timestamp = Date.now();
      await pool.execute(`
        CREATE TABLE IF NOT EXISTS product_variants_backup_${timestamp} AS
        SELECT * FROM product_variants WHERE price = 750 AND stock = 10
      `);
      console.log(`Backup created: product_variants_backup_${timestamp}`);
      
      // 3. Fix corrupted variants - use original product price
      console.log("Step 3: Fixing corrupted variants...");
      
      for (const variant of corruptedVariants) {
        const originalPrice = variant.original_product_price || 1550; // Use original price or default to 1550
        const newStock = 50; // Set reasonable stock instead of 10
        
        await pool.execute(`
          UPDATE product_variants 
          SET price = ?, stock = ?
          WHERE id = ?
        `, [originalPrice, newStock, variant.id]);
        
        console.log(`Fixed variant ${variant.id}: ${variant.product_name} - ${variant.color_name} ${variant.size} -> Price: ${originalPrice}, Stock: ${newStock}`);
      }
      
      console.log("Step 4: Verifying fix...");
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
      
      // 5. Check remaining corruption
      const [remainingCorrupted] = await pool.execute(`
        SELECT COUNT(*) as remaining_count
        FROM product_variants 
        WHERE price = 750 AND stock = 10
      `);
      
      console.log("Step 5: API Fix - Disabling auto-creation logic...");
      console.log("✅ API already fixed in adminProductRoutes.js (auto-creation disabled)");
      
      console.log("=== EMERGENCY FIX COMPLETED ===");
      console.log(`Fixed ${corruptedVariants.length} variants`);
      console.log(`Remaining corrupted variants: ${remainingCorrupted[0].remaining_count}`);
      console.log(`Backup table: product_variants_backup_${timestamp}`);
      
      if (remainingCorrupted[0].remaining_count === 0) {
        console.log("SUCCESS: All corrupted variants have been fixed!");
      } else {
        console.log("WARNING: Some corrupted variants still remain");
      }
      
    } else {
      console.log("No corrupted variants found - data is clean");
    }
    
  } catch (error) {
    console.error("Emergency fix failed:", error);
  } finally {
    await pool.end();
  }
}

// Run the fix
emergencyFix();
