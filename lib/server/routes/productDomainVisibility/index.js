const express = require('express');
const router = express.Router();
const mysql = require('mysql2/promise');

// DB Connection
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db"
});

// GET /api/product-domain-visibility/websites/with-products/:userId
// Get all websites for a user that have published products
router.get('/websites/with-products/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    
    // Query to get websites with product counts for the user
    const query = `
      SELECT DISTINCT 
        w.website_id, 
        w.website_name, 
        w.domain, 
        w.status,
        COUNT(p.id) as product_count
      FROM websites w
      INNER JOIN user_websites uw ON w.website_id = uw.website_id
      LEFT JOIN product_domain_visibility pdv ON w.website_id = pdv.domain_id
      LEFT JOIN products p ON pdv.product_id = p.id AND p.status = 'publish'
      WHERE uw.user_id = ? 
        AND uw.status = 'A' 
        AND w.status = 'Y'
        AND pdv.is_visible = 1
        AND pdv.status = 'A'
      GROUP BY w.website_id, w.website_name, w.domain, w.status
      HAVING product_count > 0
      ORDER BY w.website_name ASC
    `;
    
    const [results] = await pool.execute(query, [userId]);
    
    res.json({
      success: true,
      websites: results
    });
  } catch (error) {
    console.error('Error fetching websites with products:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch websites with products',
      error: error.message
    });
  }
});

// GET /api/product-domain-visibility/products/website/:websiteId
// Get all products published to a specific website
router.get('/products/website/:websiteId', async (req, res) => {
  try {
    const { websiteId } = req.params;
    
    const query = `
      SELECT 
        p.*,
        pdv.is_visible,
        pdv.created_at as visibility_created_at,
        w.website_name,
        w.domain
      FROM products p
      INNER JOIN product_domain_visibility pdv ON p.product_id = pdv.product_id
      INNER JOIN websites w ON pdv.domain_id = w.website_id
      WHERE pdv.domain_id = ? 
        AND pdv.is_visible = 1 
        AND pdv.status = 'A'
        AND p.status = 'publish'
      ORDER BY pdv.created_at DESC
    `;
    
    const [results] = await pool.execute(query, [websiteId]);
    
    // Parse images JSON if it exists
    const products = results.map(product => {
      if (product.images) {
        try {
          product.images = JSON.parse(product.images);
        } catch (e) {
          product.images = [];
        }
      }
      return product;
    });
    
    res.json({
      success: true,
      products: products
    });
  } catch (error) {
    console.error('Error fetching website products:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch website products',
      error: error.message
    });
  }
});

// GET /api/product-domain-visibility/test/websites
// Test endpoint to check all websites in database
router.get('/test/websites', async (req, res) => {
  try {
    console.log(`🔍 Testing: Fetching ALL websites from database`);
    
    const query = `
      SELECT * FROM websites 
      ORDER BY website_name ASC
    `;
    
    const [results] = await pool.execute(query);
    
    console.log(`📊 Found ${results.length} total websites in database`);
    console.log(`📊 Results:`, results);
    
    res.json({
      success: true,
      count: results.length,
      websites: results
    });
  } catch (error) {
    console.error('❌ Error in test endpoint:', error);
    res.status(500).json({
      success: false,
      message: 'Test endpoint failed',
      error: error.message
    });
  }
});

// GET /api/product-domain-visibility/websites/all
// Get all websites (for debugging purposes)
router.get('/websites/all', async (req, res) => {
  try {
    console.log(`🔍 Fetching all websites (debug endpoint)`);
    
    const query = `
      SELECT website_id, website_name, domain, status
      FROM websites 
      WHERE status = 'Y'
      ORDER BY website_name ASC
    `;
    
    const [results] = await pool.execute(query);
    
    console.log(`📊 Found ${results.length} total websites`);
    console.log(`📊 Results:`, results);
    
    res.json({
      success: true,
      websites: results
    });
  } catch (error) {
    console.error('❌ Error fetching all websites:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch all websites',
      error: error.message
    });
  }
});

// GET /api/product-domain-visibility/websites/user/:userId
// Get all websites for a user (TEMPORARY: showing all websites for testing)
router.get('/websites/user/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    console.log(`🔍 Fetching websites for user: ${userId}`);
    
    // TEMPORARY: Get all websites without user_websites check for testing
    const query = `
      SELECT w.website_id, w.website_name, w.domain, w.status
      FROM websites w
      WHERE w.status = 'Y'
      ORDER BY w.website_name ASC
    `;
    
    console.log(`📝 Executing TEMPORARY query (all websites): ${query}`);
    
    const [results] = await pool.execute(query);
    
    console.log(`📊 Found ${results.length} websites (TEMPORARY - all websites)`);
    console.log(`📊 Results:`, results);
    
    res.json({
      success: true,
      websites: results
    });
  } catch (error) {
    console.error('❌ Error fetching websites:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch websites',
      error: error.message
    });
  }
});

// POST /api/product-domain-visibility/save
// Save product domain visibility
router.post('/save', async (req, res) => {
  try {
    const { productId, selectedWebsiteIds } = req.body;
    
    console.log(`🌐 [SAVE] Received request to save product-website associations`);
    console.log(`🌐 [SAVE] Product ID: ${productId}`);
    console.log(`🌐 [SAVE] Selected Website IDs: ${JSON.stringify(selectedWebsiteIds)}`);
    
    if (!productId || !selectedWebsiteIds || !Array.isArray(selectedWebsiteIds)) {
      console.log(`❌ [SAVE] Invalid request data`);
      return res.status(400).json({
        success: false,
        message: 'Invalid request data'
      });
    }
    
    console.log(`🌐 [SAVE] Starting to save ${selectedWebsiteIds.length} website associations`);
    
    // Start transaction
    const connection = await pool.getConnection();
    await connection.beginTransaction();
    
    try {
      for (const domainId of selectedWebsiteIds) {
        console.log(`🌐 [SAVE] Inserting product ${productId} -> website ${domainId}`);
        
        const query = `
          INSERT INTO product_domain_visibility 
          (product_id, domain_id, is_visible, status, created_at, updated_at)
          VALUES (?, ?, 1, 'A', NOW(), NOW())
          ON DUPLICATE KEY UPDATE 
          is_visible = 1, updated_at = NOW()
        `;
        
        await connection.execute(query, [productId, domainId]);
        console.log(`✅ [SAVE] Successfully inserted product ${productId} -> website ${domainId}`);
      }
      
      await connection.commit();
      console.log(`✅ [SAVE] All ${selectedWebsiteIds.length} associations saved successfully`);
      
      res.json({
        success: true,
        message: 'Product domain visibility saved successfully',
        data: {
          productId: productId,
          selectedWebsiteIds: selectedWebsiteIds
        }
      });
      
    } catch (innerError) {
      await connection.rollback();
      console.error(`❌ [SAVE] Transaction failed:`, innerError);
      throw innerError;
    } finally {
      connection.release();
    }
    
  } catch (error) {
    console.error('❌ [SAVE] Error saving product domain visibility:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to save product domain visibility',
      error: error.message
    });
  }
});

// GET /api/product-domain-visibility/product/:productId
// Get websites where a product is visible
router.get('/product/:productId', async (req, res) => {
  try {
    const { productId } = req.params;
    
    const query = `
      SELECT w.website_id, w.website_name, w.domain, pdv.is_visible
      FROM product_domain_visibility pdv
      INNER JOIN websites w ON pdv.domain_id = w.website_id
      WHERE pdv.product_id = ? AND pdv.status = 'A'
      ORDER BY w.website_name ASC
    `;
    
    const [results] = await pool.execute(query, [productId]);
    
    res.json({
      success: true,
      websites: results
    });
  } catch (error) {
    console.error('Error fetching product domain visibility:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch product domain visibility',
      error: error.message
    });
  }
});

// PUT /api/product-domain-visibility/toggle
// Toggle visibility for a product on a specific domain
router.put('/toggle', async (req, res) => {
  try {
    const { productId, domainId, isVisible } = req.body;
    
    if (!productId || !domainId) {
      return res.status(400).json({
        success: false,
        message: 'Product ID and Domain ID are required'
      });
    }
    
    const query = `
      INSERT INTO product_domain_visibility 
      (product_id, domain_id, is_visible, status, created_at, updated_at) 
      VALUES (?, ?, ?, 'A', NOW(), NOW())
      ON DUPLICATE KEY UPDATE 
      is_visible = ?, updated_at = NOW()
    `;
    
    await pool.execute(query, [productId, domainId, isVisible ? 1 : 0, isVisible ? 1 : 0]);
    
    res.json({
      success: true,
      message: 'Product visibility updated successfully'
    });
    
  } catch (error) {
    console.error('Error toggling product visibility:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update product visibility',
      error: error.message
    });
  }
});

module.exports = router;

