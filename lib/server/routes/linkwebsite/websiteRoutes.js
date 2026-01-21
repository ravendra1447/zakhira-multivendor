const express = require('express');
const router = express.Router();
const mysql = require('mysql2/promise'); // Adjust path as needed

// DB Connection
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db"
});

// GET - Fetch all available websites
router.get('/available', async (req, res) => {
    try {
        const [websites] = await pool.execute(
            'SELECT website_id, website_name, domain FROM websites ORDER BY website_name'
        );
        
        res.json({
            success: true,
            data: websites
        });
    } catch (error) {
        console.error('Error fetching websites:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch websites'
        });
    }
});

// GET - Fetch user's linked websites
router.get('/user/:userId', async (req, res) => {
    try {
        const userId = req.params.userId;
        
        const [userWebsites] = await pool.execute(`
            SELECT w.website_id, w.website_name, w.domain, uw.status, uw.role, uw.created_at
            FROM websites w
            INNER JOIN user_websites uw ON w.website_id = uw.website_id
            WHERE uw.user_id = ? AND uw.status = 'Y'
            ORDER BY uw.created_at DESC
        `, [userId]);
        
        res.json({
            success: true,
            data: userWebsites
        });
    } catch (error) {
        console.error('Error fetching user websites:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch user websites'
        });
    }
});

// POST - Link user to website
router.post('/link', async (req, res) => {
    try {
        const { userId, websiteId, role = 'user' } = req.body;
        
        if (!userId || !websiteId) {
            return res.status(400).json({
                success: false,
                message: 'User ID and Website ID are required'
            });
        }
        
        // Check if already linked
        const [existing] = await pool.execute(
            'SELECT user_website_id FROM user_websites WHERE user_id = ? AND website_id = ?',
            [userId, websiteId]
        );
        
        if (existing.length > 0) {
            return res.status(400).json({
                success: false,
                message: 'User is already linked to this website'
            });
        }
        
        // Insert new link
        const [result] = await pool.execute(`
            INSERT INTO user_websites (user_id, website_id, status, role)
            VALUES (?, ?, 'Y', ?)
        `, [userId, websiteId, role]);
        
        res.json({
            success: true,
            message: 'Website linked successfully',
            data: {
                userWebsiteId: result.insertId
            }
        });
    } catch (error) {
        console.error('Error linking website:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to link website'
        });
    }
});

// PUT - Update website link status
router.put('/update-status', async (req, res) => {
    try {
        const { userId, websiteId, status } = req.body;
        
        if (!userId || !websiteId || !status) {
            return res.status(400).json({
                success: false,
                message: 'User ID, Website ID, and status are required'
            });
        }
        
        const [result] = await pool.execute(`
            UPDATE user_websites 
            SET status = ?, updated_at = CURRENT_TIMESTAMP
            WHERE user_id = ? AND website_id = ?
        `, [status, userId, websiteId]);
        
        if (result.affectedRows === 0) {
            return res.status(404).json({
                success: false,
                message: 'Website link not found'
            });
        }
        
        res.json({
            success: true,
            message: 'Website status updated successfully'
        });
    } catch (error) {
        console.error('Error updating website status:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to update website status'
        });
    }
});

// GET - Fetch products for a specific website (for a specific user)
router.get('/products/:websiteId/:userId', async (req, res) => {
    try {
        const { websiteId, userId } = req.params;
        
        // First verify user has access to this website
        const [userAccess] = await pool.execute(
            'SELECT user_website_id FROM user_websites WHERE user_id = ? AND website_id = ? AND status = "Y"',
            [userId, websiteId]
        );
        
        if (userAccess.length === 0) {
            return res.status(403).json({
                success: false,
                message: 'User does not have access to this website'
            });
        }
        
        // Fetch products for this user with proper sorting
        const [products] = await pool.execute(`
            SELECT p.*, pi.image_url
            FROM products p
            LEFT JOIN product_images pi ON p.id = pi.product_id
            WHERE p.user_id = ? AND p.status = 'publish'
            ORDER BY p.updated_at DESC, p.id DESC
        `, [userId]);
        
        // Group images by product while maintaining order
        const productsWithImages = {};
        const orderedProducts = [];
        
        products.forEach(product => {
            const productId = product.id;
            
            if (!productsWithImages[productId]) {
                productsWithImages[productId] = {
                    ...product,
                    images: []
                };
                delete productsWithImages[productId].image_url;
                orderedProducts.push(productsWithImages[productId]);
            }
            
            if (product.image_url) {
                productsWithImages[productId].images.push(product.image_url);
            }
        });
        
        // Extract images from variations if images array is empty
        const finalProducts = orderedProducts.map(product => {
            // If no images from product_images, try to extract from variations
            if (product.images.length === 0 && product.variations) {
                try {
                    const variations = typeof product.variations === 'string' 
                        ? JSON.parse(product.variations) 
                        : product.variations;
                    
                    if (Array.isArray(variations)) {
                        const allImages = [];
                        variations.forEach(variation => {
                            if (variation.image) {
                                allImages.push(variation.image);
                            }
                            if (variation.allImages && Array.isArray(variation.allImages)) {
                                allImages.push(...variation.allImages);
                            }
                        });
                        product.images = [...new Set(allImages)]; // Remove duplicates
                    }
                } catch (e) {
                    console.log('Error parsing variations:', e);
                }
            }
            return product;
        });
        
        res.json({
            success: true,
            data: finalProducts
        });
    } catch (error) {
        console.error('Error fetching website products:', error);
        res.status(500).json({
            success: false,
            message: 'Failed to fetch website products'
        });
    }
});

module.exports = router;
