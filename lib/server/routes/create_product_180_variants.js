const mysql = require("mysql2/promise");

// Database connection
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db",
});

async function createProduct180Variants() {
  console.log("=== CREATING VARIANTS FOR PRODUCT 180 ===");
  
  try {
    // 1. Check product 180 info
    const [productInfo] = await pool.execute(`
      SELECT id, name, price, stock_mode, stock FROM products WHERE id = 180
    `);
    
    if (productInfo.length === 0) {
      console.log("Product 180 not found!");
      return;
    }
    
    console.log("Product 180 info:");
    console.log(productInfo[0]);
    
    // 2. Check existing variants
    const [existingVariants] = await pool.execute(`
      SELECT COUNT(*) as count FROM product_variants WHERE product_id = 180
    `);
    
    console.log(`Existing variants for product 180: ${existingVariants[0].count}`);
    
    if (existingVariants[0].count > 0) {
      console.log("Variants already exist for product 180!");
      return;
    }
    
    // 3. Create colors first
    const colors = [
      { name: 'Black', code: '#000000' },
      { name: 'White', code: '#FFFFFF' },
      { name: 'Blue', code: '#0000FF' },
      { name: 'Red', code: '#FF0000' }
    ];
    
    const sizes = ['S', 'M', 'L', 'XL'];
    const price = productInfo[0].price || 1550;
    const stock = 50;
    
    console.log(`Creating ${colors.length} colors with ${sizes.length} sizes each...`);
    
    // 4. Insert colors
    for (const color of colors) {
      await pool.execute(`
        INSERT INTO product_colors (product_id, color_name, color_code, price, stock)
        VALUES (?, ?, ?, ?, ?)
      `, [180, color.name, color.code, price, stock]);
      
      console.log(`Created color: ${color.name}`);
    }
    
    // 5. Insert variants
    for (const color of colors) {
      for (const size of sizes) {
        await pool.execute(`
          INSERT INTO product_variants (product_id, color_name, size, price, stock, status)
          VALUES (?, ?, ?, ?, ?, 1)
        `, [180, color.name, size, price, stock]);
        
        console.log(`Created variant: ${color.name} ${size} - Price: ${price}, Stock: ${stock}`);
      }
    }
    
    // 6. Verify creation
    const [newVariants] = await pool.execute(`
      SELECT COUNT(*) as count FROM product_variants WHERE product_id = 180
    `);
    
    const [newColors] = await pool.execute(`
      SELECT COUNT(*) as count FROM product_colors WHERE product_id = 180
    `);
    
    console.log("=== CREATION COMPLETE ===");
    console.log(`Colors created: ${newColors[0].count}`);
    console.log(`Variants created: ${newVariants[0].count}`);
    console.log("Expected: 4 colors, 16 variants (4 colors × 4 sizes)");
    
    // 7. Show sample data
    const [sampleData] = await pool.execute(`
      SELECT color_name, size, price, stock, status 
      FROM product_variants 
      WHERE product_id = 180 
      ORDER BY color_name, size 
      LIMIT 8
    `);
    
    console.log("Sample variants:");
    sampleData.forEach(v => {
      console.log(`  ${v.color_name} ${v.size} - Price: ${v.price}, Stock: ${v.stock}, Status: ${v.status}`);
    });
    
  } catch (error) {
    console.error("Error creating variants:", error);
  } finally {
    await pool.end();
  }
}

// Run the creation
createProduct180Variants();
