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

// Get current shipping rate
router.get('/current-rate', async (req, res) => {
  try {
    const [rates] = await pool.execute(
      'SELECT rate FROM shipping_rates WHERE is_active = TRUE ORDER BY id LIMIT 1'
    );
    
    if (rates.length > 0) {
      res.json({
        success: true,
        rate: rates[0].rate
      });
    } else {
      res.json({
        success: true,
        rate: 250.00 // Default fallback
      });
    }
  } catch (error) {
    console.error('Error fetching shipping rate:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch shipping rate'
    });
  }
});

// Get all shipping rates (for admin)
router.get('/all-rates', async (req, res) => {
  try {
    const [rates] = await pool.execute(
      'SELECT * FROM shipping_rates ORDER BY created_at DESC'
    );
    
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

// Update shipping rate
router.put('/update-rate', async (req, res) => {
  try {
    const { rate, name, description } = req.body;
    
    if (!rate || isNaN(rate)) {
      return res.status(400).json({
        success: false,
        message: 'Valid rate is required'
      });
    }
    
    // Update the first active shipping rate
    const [result] = await pool.execute(
      'UPDATE shipping_rates SET rate = ?, name = ?, description = ?, updated_at = CURRENT_TIMESTAMP WHERE is_active = TRUE ORDER BY id LIMIT 1',
      [parseFloat(rate), name || 'Standard Delivery', description || 'Standard delivery charge for all orders']
    );
    
    if (result.affectedRows > 0) {
      res.json({
        success: true,
        message: 'Shipping rate updated successfully'
      });
    } else {
      // If no active rate exists, create one
      await pool.execute(
        'INSERT INTO shipping_rates (name, description, rate, is_active) VALUES (?, ?, ?, TRUE)',
        [name || 'Standard Delivery', description || 'Standard delivery charge for all orders', parseFloat(rate)]
      );
      
      res.json({
        success: true,
        message: 'Shipping rate created successfully'
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

// Create new shipping rate
router.post('/create-rate', async (req, res) => {
  try {
    const { name, description, rate, min_order_amount, max_order_amount } = req.body;
    
    if (!name || !rate || isNaN(rate)) {
      return res.status(400).json({
        success: false,
        message: 'Name and valid rate are required'
      });
    }
    
    const [result] = await pool.execute(
      'INSERT INTO shipping_rates (name, description, rate, min_order_amount, max_order_amount, is_active) VALUES (?, ?, ?, ?, ?, TRUE)',
      [name, description, parseFloat(rate), parseFloat(min_order_amount || 0), max_order_amount ? parseFloat(max_order_amount) : null]
    );
    
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

// Toggle shipping rate active status
router.put('/toggle-rate/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const [result] = await pool.execute(
      'UPDATE shipping_rates SET is_active = NOT is_active, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
      [parseInt(id)]
    );
    
    if (result.affectedRows > 0) {
      res.json({
        success: true,
        message: 'Shipping rate status updated successfully'
      });
    } else {
      res.status(404).json({
        success: false,
        message: 'Shipping rate not found'
      });
    }
  } catch (error) {
    console.error('Error toggling shipping rate:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to toggle shipping rate'
    });
  }
});

module.exports = router;
