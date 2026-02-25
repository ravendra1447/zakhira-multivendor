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


// Get user address from users table
router.get('/user/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    
    const [users] = await pool.execute(
      `SELECT user_id, name, phone_number, address_street, address_city, address_state, address_pincode 
       FROM users WHERE user_id = ?`,
      [userId]
    );
    
    if (users.length > 0) {
      const user = users[0];
      const address = {
        id: user.user_id,
        user_id: user.user_id,
        name: user.name || '',
        phone: user.phone_number || '',
        street: user.address_street || '',
        city: user.address_city || '',
        state: user.address_state || '',
        pincode: user.address_pincode || '',
        is_default: 1
      };
      
      res.json({
        success: true,
        addresses: [address]
      });
    } else {
      res.json({
        success: true,
        addresses: []
      });
    }
  } catch (error) {
    console.error('Error fetching user address:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch address'
    });
  }
});

// Update user address in users table
router.post('/create', async (req, res) => {
  try {
    const {
      user_id,
      name,
      phone,
      street,
      city,
      state,
      pincode,
      is_default
    } = req.body;

    // Update user's address in users table
    await pool.execute(
      `UPDATE users SET 
       name = ?, 
       phone_number = ?, 
       address_street = ?, 
       address_city = ?, 
       address_state = ?, 
       address_pincode = ?, 
       updated_at = NOW() 
       WHERE user_id = ?`,
      [name, phone, street, city, state, pincode, user_id]
    );

    res.json({
      success: true,
      message: 'Address updated successfully',
      addressId: user_id
    });
  } catch (error) {
    console.error('Error updating address:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update address'
    });
  }
});

// Update user address (same as create for users table)
router.put('/update/:addressId', async (req, res) => {
  try {
    const { addressId } = req.params;
    const {
      name,
      phone,
      street,
      city,
      state,
      pincode,
      is_default
    } = req.body;

    // Update user's address in users table
    await pool.execute(
      `UPDATE users SET 
       name = ?, 
       phone_number = ?, 
       address_street = ?, 
       address_city = ?, 
       address_state = ?, 
       address_pincode = ?, 
       updated_at = NOW() 
       WHERE user_id = ?`,
      [name, phone, street, city, state, pincode, addressId]
    );

    res.json({
      success: true,
      message: 'Address updated successfully'
    });
  } catch (error) {
    console.error('Error updating address:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update address'
    });
  }
});

// Delete address (not applicable for users table)
router.delete('/delete/:addressId', async (req, res) => {
  try {
    const { addressId } = req.params;

    res.json({
      success: false,
      message: 'Deleting address is not supported for users table'
    });
  } catch (error) {
    console.error('Error deleting address:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete address'
    });
  }
});

module.exports = router;
