const express = require('express');
const router = express.Router();
const mysql = require("mysql2/promise");

// Database connection (same as server.js)
let pool;

// Initialize database connection with error handling
try {
  pool = mysql.createPool({
    host: "localhost",
    user: "chatuser", 
    password: "chat1234#db",
    database: "chat_db"
  });
  console.log('✅ Banner routes: Database connection initialized');
} catch (error) {
  console.error('❌ Banner routes: Database connection failed:', error.message);
}

// ✅ GET ALL BANNERS
router.get('/', async (req, res) => {
  try {
    console.log('🎯 GET /banners called');
    
    if (!pool) {
      return res.status(500).json({
        success: false,
        message: 'Database connection not available',
        debug: 'Pool not initialized'
      });
    }
    
    const [banners] = await pool.execute(
      'SELECT * FROM marketplace_banners ORDER BY display_order ASC, created_at DESC'
    );
    
    console.log(`🎯 Found ${banners.length} banners`);
    
    res.json({
      success: true,
      data: banners,
      message: 'Banners fetched successfully'
    });
  } catch (error) {
    console.error('❌ Error fetching banners:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch banners',
      error: error.message,
      debug: 'Database query failed'
    });
  }
});
// ✅ GET ACTIVE BANNERS (for marketplace)
router.get('/active', async (req, res) => {
  try {
    console.log('🎯 GET /banners/active called');
    
    if (!pool) {
      return res.status(500).json({
        success: false,
        message: 'Database connection not available',
        debug: 'Pool not initialized'
      });
    }
    
    const [banners] = await pool.execute(
      'SELECT * FROM marketplace_banners WHERE is_active = 1 AND (start_date IS NULL OR start_date <= NOW()) AND (end_date IS NULL OR end_date >= NOW()) ORDER BY display_order ASC, created_at DESC'
    );
    
    console.log(`🎯 Found ${banners.length} active banners`);
    
    res.json({
      success: true,
      data: banners,
      message: 'Active banners fetched successfully'
    });
  } catch (error) {
    console.error('❌ Error fetching active banners:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch active banners',
      error: error.message,
      debug: 'Database query failed'
    });
  }
});

// ✅ CREATE BANNER
router.post('/', async (req, res) => {
  try {
    const { 
      title, 
      subtitle, 
      description, 
      image_url, 
      background_color, 
      text_color, 
      button_text, 
      button_url, 
      display_order, 
      is_active,
      start_date,
      end_date 
    } = req.body;

    // Validation
    if (!title || !image_url) {
      return res.status(400).json({
        success: false,
        message: 'Title and image URL are required'
      });
    }

    const [result] = await pool.execute(
      `INSERT INTO marketplace_banners 
       (title, subtitle, description, image_url, background_color, text_color, button_text, button_url, display_order, is_active, start_date, end_date, created_at) 
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())`,
      [title, subtitle, description, image_url, background_color, text_color, button_text, button_url, display_order, is_active, start_date, end_date]
    );

    res.json({
      success: true,
      data: { id: result.insertId, ...req.body },
      message: 'Banner created successfully'
    });
  } catch (error) {
    console.error('Error creating banner:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create banner',
      error: error.message
    });
  }
});

// ✅ UPDATE BANNER
router.put('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { 
      title, 
      subtitle, 
      description, 
      image_url, 
      background_color, 
      text_color, 
      button_text, 
      button_url, 
      display_order, 
      is_active,
      start_date,
      end_date 
    } = req.body;

    const [result] = await pool.execute(
      `UPDATE marketplace_banners SET 
       title = ?, subtitle = ?, description = ?, image_url = ?, background_color = ?, text_color = ?, 
       button_text = ?, button_url = ?, display_order = ?, is_active = ?, start_date = ?, end_date = ? 
       WHERE id = ?`,
      [title, subtitle, description, image_url, background_color, text_color, button_text, button_url, display_order, is_active, start_date, end_date, id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        message: 'Banner not found'
      });
    }

    res.json({
      success: true,
      message: 'Banner updated successfully'
    });
  } catch (error) {
    console.error('Error updating banner:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update banner',
      error: error.message
    });
  }
});

// ✅ DELETE BANNER
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const [result] = await pool.execute(
      'DELETE FROM marketplace_banners WHERE id = ?',
      [id]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        message: 'Banner not found'
      });
    }

    res.json({
      success: true,
      message: 'Banner deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting banner:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete banner',
      error: error.message
    });
  }
});

module.exports = router;

module.exports = router;
