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

// Get shipping rate for specific product and user
router.get('/calculate-rate', async (req, res) => {
  try {
    const { product_id, user_id, order_amount, city, state, pincode } = req.query;
    
    let query = `
      SELECT sr.*, p.name as product_name, p.price as product_price, 
             u.name as user_name, u.email as user_email, u.user_type
      FROM shipping_rates sr
      LEFT JOIN products p ON sr.product_id = p.id
      LEFT JOIN users u ON sr.user_id = u.id
      WHERE sr.is_active = TRUE
    `;
    
    const conditions = [];
    const params = [];
    
    // Add conditions based on provided parameters
    if (product_id) {
      conditions.push('(sr.product_id IS NULL OR sr.product_id = ?)');
      params.push(product_id);
    }
    
    if (user_id) {
      conditions.push('(sr.user_id IS NULL OR sr.user_id = ?)');
      params.push(user_id);
    }
    
    if (order_amount) {
      conditions.push('(sr.min_order_amount IS NULL OR sr.min_order_amount <= ?)');
      conditions.push('(sr.max_order_amount IS NULL OR sr.max_order_amount >= ?)');
      params.push(order_amount, order_amount);
    }
    
    if (city) {
      conditions.push('(sr.city IS NULL OR sr.city = ?)');
      params.push(city);
    }
    
    if (state) {
      conditions.push('(sr.state IS NULL OR sr.state = ?)');
      params.push(state);
    }
    
    if (pincode) {
      conditions.push('(sr.pincode IS NULL OR sr.pincode = ?)');
      params.push(pincode);
    }
    
    if (conditions.length > 0) {
      query += ' AND ' + conditions.join(' AND ');
    }
    
    query += ' ORDER BY sr.priority DESC, sr.rate ASC LIMIT 1';
    
    const [rates] = await pool.execute(query, params);
    
    if (rates.length > 0) {
      const rate = rates[0];
      let finalRate = rate.rate;
      
      // Apply percentage-based rates
      if (rate.rate_type === 'percentage' && order_amount) {
        finalRate = (parseFloat(order_amount) * rate.rate) / 100;
      }
      
      res.json({
        success: true,
        shipping_rate: parseFloat(finalRate).toFixed(2),
        rate_details: {
          name: rate.name,
          description: rate.description,
          rate_type: rate.rate_type,
          base_rate: rate.rate,
          product_name: rate.product_name,
          product_price: rate.product_price,
          user_name: rate.user_name,
          user_email: rate.user_email,
          user_type: rate.user_type
        }
      });
    } else {
      // Fallback to default rate
      res.json({
        success: true,
        shipping_rate: 250.00,
        rate_details: {
          name: 'Standard Delivery',
          description: 'Default delivery charge'
        }
      });
    }
  } catch (error) {
    console.error('Error calculating shipping rate:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to calculate shipping rate'
    });
  }
});

// Get all shipping rates with product and user details
router.get('/all-rates-with-details', async (req, res) => {
  try {
    const [rates] = await pool.execute(`
      SELECT sr.*, 
             p.name as product_name, p.price as product_price, p.image_url as product_image,
             u.name as user_name, u.email as user_email, u.phone as user_phone
      FROM shipping_rates sr
      LEFT JOIN products p ON sr.product_id = p.id
      LEFT JOIN users u ON sr.user_id = u.id
      ORDER BY sr.priority DESC, sr.created_at DESC
    `);
    
    res.json({
      success: true,
      rates: rates
    });
  } catch (error) {
    console.error('Error fetching shipping rates:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch shipping rates'
    });
  }
});

// Create or update shipping rate with product/user linkage
router.post('/create-rate', async (req, res) => {
  try {
    const { 
      name, description, rate, rate_type, 
      product_id, category_id, user_id, user_type,
      min_order_amount, max_order_amount,
      city, state, pincode, priority 
    } = req.body;
    
    if (!name || rate === undefined) {
      return res.status(400).json({
        success: false,
        message: 'Name and rate are required'
      });
    }
    
    const [result] = await pool.execute(`
      INSERT INTO shipping_rates (
        name, description, rate, rate_type, 
        product_id, category_id, user_id, user_type,
        min_order_amount, max_order_amount,
        city, state, pincode, priority, is_active
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, TRUE)
    `, [
      name, description, parseFloat(rate), rate_type || 'fixed',
      product_id || null, category_id || null, user_id || null, user_type || 'all',
      min_order_amount ? parseFloat(min_order_amount) : 0.00,
      max_order_amount ? parseFloat(max_order_amount) : null,
      city || null, state || null, pincode || null,
      priority || 0
    ]);
    
    res.json({
      success: true,
      message: 'Shipping rate created successfully',
      rateId: result.insertId
    });
  } catch (error) {
    console.error('Error creating shipping rate:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create shipping rate'
    });
  }
});

// Get products for dropdown in admin interface
router.get('/products-list', async (req, res) => {
  try {
    const [products] = await pool.execute(`
      SELECT id, name, price, image_url 
      FROM products 
      WHERE is_active = TRUE 
      ORDER BY name ASC
      LIMIT 100
    `);
    
    res.json({
      success: true,
      products: products
    });
  } catch (error) {
    console.error('Error fetching products:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch products'
    });
  }
});

// Get users for dropdown in admin interface
router.get('/users-list', async (req, res) => {
  try {
    const [users] = await pool.execute(`
      SELECT id, name, email, phone, user_type 
      FROM users 
      ORDER BY name ASC
      LIMIT 100
    `);
    
    res.json({
      success: true,
      users: users
    });
  } catch (error) {
    console.error('Error fetching users:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch users'
    });
  }
});

// Update shipping rate
router.put('/update-rate/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { 
      name, description, rate, rate_type, 
      product_id, category_id, user_id, user_type,
      min_order_amount, max_order_amount,
      city, state, pincode, priority, is_active 
    } = req.body;
    
    const [result] = await pool.execute(`
      UPDATE shipping_rates SET
        name = ?, description = ?, rate = ?, rate_type = ?,
        product_id = ?, category_id = ?, user_id = ?, user_type = ?,
        min_order_amount = ?, max_order_amount = ?,
        city = ?, state = ?, pincode = ?, priority = ?, is_active = ?,
        updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `, [
      name, description, parseFloat(rate), rate_type || 'fixed',
      product_id || null, category_id || null, user_id || null, user_type || 'all',
      min_order_amount ? parseFloat(min_order_amount) : 0.00,
      max_order_amount ? parseFloat(max_order_amount) : null,
      city || null, state || null, pincode || null,
      priority || 0, is_active !== undefined ? is_active : true,
      parseInt(id)
    ]);
    
    if (result.affectedRows > 0) {
      res.json({
        success: true,
        message: 'Shipping rate updated successfully'
      });
    } else {
      res.status(404).json({
        success: false,
        message: 'Shipping rate not found'
      });
    }
  } catch (error) {
    console.error('Error updating shipping rate:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update shipping rate'
    });
  }
});

// Delete shipping rate
router.delete('/delete-rate/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const [result] = await pool.execute(
      'DELETE FROM shipping_rates WHERE id = ?',
      [parseInt(id)]
    );
    
    if (result.affectedRows > 0) {
      res.json({
        success: true,
        message: 'Shipping rate deleted successfully'
      });
    } else {
      res.status(404).json({
        success: false,
        message: 'Shipping rate not found'
      });
    }
  } catch (error) {
    console.error('Error deleting shipping rate:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete shipping rate'
    });
  }
});

module.exports = router;
