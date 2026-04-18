const mysql = require("mysql2/promise");

// Database connection
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db",
});

async function checkProductSizes() {
  console.log("=== CHECKING PRODUCT SIZES ISSUES ===");
  
  try {
    // 1. Check total variants
    const [totalVariants] = await pool.execute(`
      SELECT COUNT(*) as total_variants FROM product_variants
    `);
    console.log(`Total variants in product_variants: ${totalVariants[0].total_variants}`);
    
    // 2. Check for hardcoded sizes (S, M, L, XL, 6, 7, 8, 9, 10)
    const [hardcodedSizes] = await pool.execute(`
      SELECT 
        id,
        product_id,
        color_name,
        size,
        price,
        stock,
        status
      FROM product_variants 
      WHERE size IN ('S', 'M', 'L', 'XL', '6', '7', '8', '9', '10')
      ORDER BY product_id, color_name, size
    `);
    
    console.log(`\nVariants with hardcoded sizes: ${hardcodedSizes.length}`);
    if (hardcodedSizes.length > 0) {
      console.log("Hardcoded sizes found:");
      hardcodedSizes.slice(0, 10).forEach(variant => {
        console.log(`  ID: ${variant.id}, Product: ${variant.product_id}, Color: ${variant.color_name}, Size: ${variant.size}, Price: ${variant.price}, Stock: ${variant.stock}`);
      });
      
      // Check which products are affected
      const [affectedProducts] = await pool.execute(`
        SELECT DISTINCT 
          pv.product_id,
          p.name as product_name,
          COUNT(pv.id) as hardcoded_sizes_count
        FROM product_variants pv
        JOIN products p ON pv.product_id = p.id
        WHERE pv.size IN ('S', 'M', 'L', 'XL', '6', '7', '8', '9', '10')
        GROUP BY pv.product_id, p.name
        ORDER BY hardcoded_sizes_count DESC
      `);
      
      console.log("\nAffected products:");
      affectedProducts.slice(0, 10).forEach(product => {
        console.log(`  Product ID: ${product.product_id}, Name: ${product.product_name}, Hardcoded Sizes: ${product.hardcoded_sizes_count}`);
      });
    }
    
    // 3. Check headphone products specifically
    const [headphoneVariants] = await pool.execute(`
      SELECT 
        pv.id,
        pv.product_id,
        p.name as product_name,
        pv.color_name,
        pv.size,
        pv.price,
        pv.stock,
        pv.status
      FROM product_variants pv
      JOIN products p ON pv.product_id = p.id
      WHERE pv.product_id IN (177, 178)
      ORDER BY pv.product_id, pv.color_name, pv.size
    `);
    
    console.log(`\nVariants for headphone products (177, 178):`);
    if (headphoneVariants.length === 0) {
      console.log("  No variants found for headphone products");
    } else {
      headphoneVariants.forEach(variant => {
        console.log(`  Product: ${variant.product_name}, Color: ${variant.color_name}, Size: ${variant.size}, Price: ${variant.price}, Stock: ${variant.stock}, Status: ${variant.status}`);
      });
    }
    
    // 4. Check for size patterns
    const [sizePatterns] = await pool.execute(`
      SELECT 
        size,
        COUNT(*) as count,
        COUNT(DISTINCT product_id) as products_count
      FROM product_variants 
      WHERE size IN ('S', 'M', 'L', 'XL', '6', '7', '8', '9', '10')
      GROUP BY size
      ORDER BY count DESC
    `);
    
    console.log("\nSize patterns found:");
    sizePatterns.forEach(pattern => {
      console.log(`  Size '${pattern.size}': ${pattern.count} variants across ${pattern.products_count} products`);
    });
    
    // 5. Summary
    console.log("\n=== SUMMARY ===");
    console.log(`Total variants: ${totalVariants[0].total_variants}`);
    console.log(`Hardcoded sizes: ${hardcodedSizes.length}`);
    console.log(`Headphone variants: ${headphoneVariants.length}`);
    console.log(`Products with hardcoded sizes: ${hardcodedSizes.length > 0 ? affectedProducts.length : 0}`);
    
    if (hardcodedSizes.length > 0) {
      console.log("\n\u26a0\ufe0f ACTION NEEDED:");
      console.log("1. Check if hardcoded sizes are legitimate or auto-created");
      console.log("2. Remove auto-created hardcoded sizes if needed");
      console.log("3. Update sizes to proper product-specific values");
    } else {
      console.log("\n\u2705 No hardcoded size issues found");
    }
    
  } catch (error) {
    console.error("Error checking product sizes:", error);
  } finally {
    await pool.end();
  }
}

// Run check
checkProductSizes();
