// Sample banner creation script
// Run this to create sample banners in your database

const mysql = require("mysql2/promise");

const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db"
});

async function createSampleBanners() {
  try {
    // Sample 1: MAHA INDIAN SAVINGS SALE (similar to current banner)
    await pool.execute(`
      INSERT INTO marketplace_banners 
      (title, subtitle, description, image_url, background_color, text_color, button_text, button_url, display_order, is_active, created_at) 
      VALUES 
      (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
    `, [
      'MAHA INDIAN',
      'SAVINGS SALE',
      'Get amazing discounts on your favorite products',
      'https://via.placeholder.com/400x120/FFD700/000000?text=MAHA+SALE',
      'linear-gradient(135deg, #FFD700, #9C27B0)',
      '#FFFFFF',
      'Shop Now',
      '/marketplace',
      1,
      1
    ]);

    // Sample 2: Flash Sale Banner
    await pool.execute(`
      INSERT INTO marketplace_banners 
      (title, subtitle, description, image_url, background_color, text_color, button_text, button_url, display_order, is_active, created_at) 
      VALUES 
      (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
    `, [
      'FLASH SALE',
      'Limited Time Offer',
      'Up to 70% off on selected items',
      'https://via.placeholder.com/400x120/FF6B6B/FFFFFF?text=FLASH+SALE',
      '#FF6B6B',
      '#FFFFFF',
      'Grab Deal',
      '/marketplace?sale=flash',
      2,
      1
    ]);

    // Sample 3: New Collection Banner
    await pool.execute(`
      INSERT INTO marketplace_banners 
      (title, subtitle, description, image_url, background_color, text_color, button_text, button_url, display_order, is_active, created_at) 
      VALUES 
      (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
    `, [
      'NEW COLLECTION',
      'Summer 2024',
      'Check out our latest arrivals',
      'https://via.placeholder.com/400x120/4ECDC4/FFFFFF?text=NEW+COLLECTION',
      '#4ECDC4',
      '#FFFFFF',
      'Explore',
      '/marketplace?new=true',
      3,
      1
    ]);

    console.log('✅ Sample banners created successfully!');
    
    // Fetch and display created banners
    const [banners] = await pool.execute(
      'SELECT * FROM marketplace_banners ORDER BY display_order ASC'
    );
    
    console.log('\n📋 Created Banners:');
    console.log(JSON.stringify(banners, null, 2));
    
  } catch (error) {
    console.error('❌ Error creating sample banners:', error);
  } finally {
    await pool.end();
  }
}

// Run the function
createSampleBanners();
