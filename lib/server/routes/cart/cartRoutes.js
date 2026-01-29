const express = require('express');
const router = express.Router();
const mysql = require('mysql2/promise');

// Database connection
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser", 
  password: "chat1234#db",
  database: "chat_db"
});

// Get or create user cart
router.get('/get-cart/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    
    // Get or create cart
    let [cart] = await pool.execute(
      'SELECT * FROM carts WHERE user_id = ?', 
      [userId]
    );
    
    if (cart.length === 0) {
      // Create new cart
      const [result] = await pool.execute(
        'INSERT INTO carts (user_id) VALUES (?)',
        [userId]
      );
      cart = [{ id: result.insertId, user_id: userId }];
    }
    
    // Get cart items with product details
    const [items] = await pool.execute(`
      SELECT ci.*, p.name, p.description, pi.image_url 
      FROM cart_items ci 
      LEFT JOIN products p ON ci.product_id = p.id 
      LEFT JOIN product_images pi ON ci.product_id = pi.product_id 
      WHERE ci.cart_id = ?
    `, [cart[0].id]);
    
    res.json({
      success: true,
      cart: cart[0],
      items: items
    });
  } catch (error) {
    console.error('Error getting cart:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Add item to cart
router.post('/add-item', async (req, res) => {
  try {
    const { userId, productId, quantity = 1, price, size, color } = req.body;
    
    if (!userId || !productId || !price) {
      return res.status(400).json({ 
        success: false, 
        error: 'userId, productId, and price are required' 
      });
    }
    
    // Get or create cart
    let [cart] = await pool.execute(
      'SELECT * FROM carts WHERE user_id = ?', 
      [userId]
    );
    
    if (cart.length === 0) {
      const [result] = await pool.execute(
        'INSERT INTO carts (user_id) VALUES (?)',
        [userId]
      );
      cart = [{ id: result.insertId }];
    }
    
    // Check if item already exists in cart
    const [existingItem] = await pool.execute(
      'SELECT * FROM cart_items WHERE cart_id = ? AND product_id = ? AND size = ? AND color = ?',
      [cart[0].id, productId, size || null, color || null]
    );
    
    if (existingItem.length > 0) {
      // Update quantity
      await pool.execute(
        'UPDATE cart_items SET quantity = quantity + ? WHERE id = ?',
        [quantity, existingItem[0].id]
      );
    } else {
      // Add new item
      await pool.execute(
        'INSERT INTO cart_items (cart_id, product_id, quantity, price, size, color) VALUES (?, ?, ?, ?, ?, ?)',
        [cart[0].id, productId, quantity, price, size || null, color || null]
      );
    }
    
    res.json({ success: true, message: 'Item added to cart' });
  } catch (error) {
    console.error('Error adding item to cart:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Update cart item quantity
router.put('/update-item/:itemId', async (req, res) => {
  try {
    const { itemId } = req.params;
    const { quantity } = req.body;
    
    if (!quantity || quantity < 1) {
      return res.status(400).json({ 
        success: false, 
        error: 'Valid quantity is required' 
      });
    }
    
    await pool.execute(
      'UPDATE cart_items SET quantity = ? WHERE id = ?',
      [quantity, itemId]
    );
    
    res.json({ success: true, message: 'Item updated' });
  } catch (error) {
    console.error('Error updating cart item:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Remove item from cart
router.delete('/remove-item/:itemId', async (req, res) => {
  try {
    const { itemId } = req.params;
    
    await pool.execute('DELETE FROM cart_items WHERE id = ?', [itemId]);
    
    res.json({ success: true, message: 'Item removed from cart' });
  } catch (error) {
    console.error('Error removing cart item:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Clear cart
router.delete('/clear-cart/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    
    // Get cart ID
    const [cart] = await pool.execute(
      'SELECT id FROM carts WHERE user_id = ?', 
      [userId]
    );
    
    if (cart.length > 0) {
      await pool.execute('DELETE FROM cart_items WHERE cart_id = ?', [cart[0].id]);
    }
    
    res.json({ success: true, message: 'Cart cleared' });
  } catch (error) {
    console.error('Error clearing cart:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get cart count
router.get('/cart-count/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    
    const [cart] = await pool.execute(
      'SELECT id FROM carts WHERE user_id = ?', 
      [userId]
    );
    
    let count = 0;
    if (cart.length > 0) {
      const [items] = await pool.execute(
        'SELECT SUM(quantity) as total FROM cart_items WHERE cart_id = ?',
        [cart[0].id]
      );
      count = items[0].total || 0;
    }
    
    res.json({ success: true, count: count });
  } catch (error) {
    console.error('Error getting cart count:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;
