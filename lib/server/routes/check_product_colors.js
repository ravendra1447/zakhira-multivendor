const mysql = require("mysql2/promise");

// Database connection
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db",
});

async function checkProductColors() {
  console.log("=== CHECKING PRODUCT_COLORS TABLE ISSUES ===");
  
  try {
    // 1. Check total colors in product_colors table
    const [totalColors] = await pool.execute(`
      SELECT COUNT(*) as total_colors FROM product_colors
    `);
    console.log(`Total colors in product_colors: ${totalColors[0].total_colors}`);
    
    // 2. Check for hardcoded prices (750) and stock (10)
    const [hardcodedColors] = await pool.execute(`
      SELECT 
        id,
        product_id,
        color_name,
        color_code,
        price,
        stock,
        image_url
      FROM product_colors 
      WHERE price = 750 AND stock = 10
      ORDER BY product_id, color_name
    `);
    
    console.log(`\nColors with hardcoded values (750, 10): ${hardcodedColors.length}`);
    if (hardcodedColors.length > 0) {
      console.log("Hardcoded colors found:");
      hardcodedColors.forEach(color => {
        console.log(`  ID: ${color.id}, Product: ${color.product_id}, Color: ${color.color_name}, Price: ${color.price}, Stock: ${color.stock}`);
      });
      
      // Check which products these belong to
      const [affectedProducts] = await pool.execute(`
        SELECT DISTINCT 
          pc.product_id,
          p.name as product_name,
          COUNT(pc.id) as hardcoded_colors_count
        FROM product_colors pc
        JOIN products p ON pc.product_id = p.id
        WHERE pc.price = 750 AND pc.stock = 10
        GROUP BY pc.product_id, p.name
      `);
      
      console.log("\nAffected products:");
      affectedProducts.forEach(product => {
        console.log(`  Product ID: ${product.product_id}, Name: ${product.product_name}, Hardcoded Colors: ${product.hardcoded_colors_count}`);
      });
    }
    
    // 3. Check for the same headphone products (177, 178)
    const [headphoneColors] = await pool.execute(`
      SELECT 
        pc.id,
        pc.product_id,
        p.name as product_name,
        pc.color_name,
        pc.color_code,
        pc.price,
        pc.stock
      FROM product_colors pc
      JOIN products p ON pc.product_id = p.id
      WHERE pc.product_id IN (177, 178)
      ORDER BY pc.product_id, pc.color_name
    `);
    
    console.log(`\nColors for headphone products (177, 178):`);
    if (headphoneColors.length === 0) {
      console.log("  No colors found for headphone products");
    } else {
      headphoneColors.forEach(color => {
        console.log(`  Product: ${color.product_name}, Color: ${color.color_name}, Price: ${color.price}, Stock: ${color.stock}`);
      });
    }
    
    // 4. Summary
    console.log("\n=== SUMMARY ===");
    console.log(`Total colors in product_colors: ${totalColors[0].total_colors}`);
    console.log(`Colors with hardcoded values: ${hardcodedColors.length}`);
    console.log(`Headphone product colors: ${headphoneColors.length}`);
    
    if (hardcodedColors.length > 0) {
      console.log("\n\u26a0\ufe0f ACTION NEEDED:");
      console.log("1. Fix hardcoded colors in product_colors table");
      console.log("2. Update price from 750 to original product price");
      console.log("3. Update stock from 10 to reasonable value");
    } else {
      console.log("\n\u2705 No issues found in product_colors table");
    }
    
  } catch (error) {
    console.error("Error checking product_colors:", error);
  } finally {
    await pool.end();
  }
}

// Run check
checkProductColors();
