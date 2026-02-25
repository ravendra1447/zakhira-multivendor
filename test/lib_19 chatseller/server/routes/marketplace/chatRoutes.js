const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const encryption = require(path.join(__dirname, '..', '..', 'utils', 'encryption'));

// Middleware to pass pool to request
router.use((req, res, next) => {
  req.pool = req.app.get('pool');
  next();
});

// Configure multer for image uploads
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    const uploadDir = 'uploads/chat/';
    // Create directory if it doesn't exist
    const fs = require('fs');
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, file.fieldname + '-' + uniqueSuffix + path.extname(file.originalname));
  }
});

const upload = multer({ 
  storage: storage,
  limits: {
    fileSize: 5 * 1024 * 1024 // 5MB limit
  },
  fileFilter: function (req, file, cb) {
    if (file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed!'), false);
    }
  }
});

// Create or get chat room for product
router.post('/chat_marketplace/create-or-get-room', async (req, res) => {
  const { productId, buyerId, sellerId } = req.body;

  try {
    // Check if chat room already exists
    const [existingRoom] = await req.pool.execute(
      'SELECT * FROM chat_rooms WHERE product_id = ? AND buyer_id = ? AND seller_id = ?',
      [productId, buyerId, sellerId]
    );

    if (existingRoom.length > 0) {
      res.json({ success: true, chatRoom: existingRoom[0] });
      return;
    }

    // Create new chat room
    const [result] = await req.pool.execute(
      'INSERT INTO chat_rooms (product_id, buyer_id, seller_id) VALUES (?, ?, ?)',
      [productId, buyerId, sellerId]
    );

    const chatRoomId = result.insertId;

    // Add participants
    await req.pool.execute(
      'INSERT INTO chat_participants (chat_room_id, user_id) VALUES (?, ?), (?, ?)',
      [chatRoomId, buyerId, chatRoomId, sellerId]
    );

    // Get created room
    const [newRoom] = await req.pool.execute(
      'SELECT * FROM chat_rooms WHERE id = ?',
      [chatRoomId]
    );

    res.json({ success: true, chatRoom: newRoom[0] });

  } catch (error) {
    console.error('Error creating/getting chat room:', error);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

// Get user's chat rooms
router.get('/chat_marketplace/user-rooms/:userId', async (req, res) => {
  const { userId } = req.params;

  try {
    const [rooms] = await req.pool.execute(`
      SELECT cr.*, p.name as product_name, p.images as product_images,
             u_buyer.name as buyer_name, u_seller.name as seller_name,
             (SELECT COUNT(*) FROM chat_messages cm WHERE cm.chat_room_id = cr.id AND cm.sender_id != ? AND cm.is_read = FALSE) as unread_count,
             (SELECT cm.message_content FROM chat_messages cm WHERE cm.chat_room_id = cr.id ORDER BY cm.created_at DESC LIMIT 1) as last_message,
             (SELECT cm.created_at FROM chat_messages cm WHERE cm.chat_room_id = cr.id ORDER BY cm.created_at DESC LIMIT 1) as last_message_time
      FROM chat_rooms cr
      JOIN products p ON cr.product_id = p.id
      JOIN users u_buyer ON cr.buyer_id = u_buyer.id
      JOIN users u_seller ON cr.seller_id = u_seller.id
      WHERE cr.buyer_id = ? OR cr.seller_id = ?
      ORDER BY cr.updated_at DESC
    `, [userId, userId, userId]);

    res.json({ success: true, rooms });

  } catch (error) {
    console.error('Error getting user rooms:', error);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

// Get seller by product ID
router.get('/chat_marketplace/seller-by-product/:productId', async (req, res) => {
  const { productId } = req.params;

  try {
    const [product] = await req.pool.execute(
      'SELECT user_id as sellerId FROM products WHERE id = ? AND status = "publish" AND marketplace_enabled = 1',
      [productId]
    );

    if (product.length === 0) {
      res.status(404).json({ success: false, message: 'Product not found or not available in marketplace' });
      return;
    }

    res.json({ success: true, sellerId: product[0].sellerId });

  } catch (error) {
    console.error('Error getting seller by product:', error);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

// Upload chat image
router.post('/chat_marketplace/upload-image', upload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No image file provided' });
    }

    const imageUrl = `/uploads/chat/${req.file.filename}`;
    
    res.json({ 
      success: true, 
      imageUrl: imageUrl,
      fileName: req.file.filename
    });

  } catch (error) {
    console.error('Error uploading chat image:', error);
    res.status(500).json({ success: false, message: 'Failed to upload image' });
  }
});

// Get chat messages
router.get('/chat_marketplace/messages/:chatRoomId', async (req, res) => {
  const { chatRoomId } = req.params;
  const { limit = 50, offset = 0 } = req.query;

  try {
    const [messages] = await req.pool.execute(`
      SELECT m.*, u.name as sender_name, '' as sender_avatar
      FROM chat_messages m
      JOIN users u ON m.sender_id = u.user_id
      WHERE m.chat_room_id = ?
      ORDER BY m.created_at DESC
      LIMIT ? OFFSET ?
    `, [chatRoomId, parseInt(limit), parseInt(offset)]);

    // Decrypt messages before sending
    const decryptedMessages = messages.map(message => {
      try {
        const decryptedContent = encryption.decryptAndDecompress(
          message.encrypted_content, 
          message.encryption_key
        );
        
        return {
          ...message,
          message_content: decryptedContent,
          encrypted_content: undefined, // Don't send encrypted content to client
          encryption_key: undefined // Don't send encryption key to client
        };
      } catch (error) {
        console.error('Error decrypting message:', error);
        return {
          ...message,
          message_content: '[Decryption Error]',
          encrypted_content: undefined,
          encryption_key: undefined
        };
      }
    });

    res.json({ success: true, messages: decryptedMessages.reverse() });

  } catch (error) {
    console.error('Error getting chat messages:', error);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

// Mark messages as read
router.post('/chat_marketplace/mark-read', async (req, res) => {
  const { chatRoomId, userId, messageId } = req.body;

  try {
    const now = new Date();
    
    // Update messages as read with read time
    await req.pool.execute(
      'UPDATE chat_messages SET is_read = TRUE, read_time = ? WHERE chat_room_id = ? AND sender_id != ? AND id <= ?',
      [now, chatRoomId, userId, messageId]
    );

    // Update last read for user and mark as active
    await req.pool.execute(
      'INSERT INTO chat_participants (chat_room_id, user_id, last_read_message_id, last_active_at) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE last_read_message_id = ?, last_active_at = ?',
      [chatRoomId, userId, messageId, now, messageId, now]
    );

    // Get updated unread count
    const [unreadCount] = await req.pool.execute(
      'SELECT COUNT(*) as count FROM chat_messages WHERE chat_room_id = ? AND sender_id != ? AND is_read = FALSE',
      [chatRoomId, userId]
    );

    res.json({ 
      success: true, 
      readTime: now,
      unreadCount: unreadCount[0].count
    });

  } catch (error) {
    console.error('Error marking messages as read:', error);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

// Get single chat room by ID
router.get('/chat_marketplace/room/:chatRoomId', async (req, res) => {
  const { chatRoomId } = req.params;
  const { userId } = req.query;
  
  if (!userId) {
    return res.status(400).json({ success: false, message: 'userId parameter is required' });
  }
  
  try {
    const [room] = await req.pool.execute(`
      SELECT cr.*, p.name as product_name, p.images as product_images,
             u_buyer.name as buyer_name, u_seller.name as seller_name,
             (SELECT COUNT(*) FROM chat_messages cm WHERE cm.chat_room_id = cr.id AND cm.sender_id != ? AND cm.is_read = FALSE) as unread_count,
             (SELECT cm.message_content FROM chat_messages cm WHERE cm.chat_room_id = cr.id ORDER BY cm.created_at DESC LIMIT 1) as last_message,
             (SELECT cm.created_at FROM chat_messages cm WHERE cm.chat_room_id = cr.id ORDER BY cm.created_at DESC LIMIT 1) as last_message_time
      FROM chat_rooms cr
      LEFT JOIN products p ON cr.product_id = p.id
      LEFT JOIN users u_buyer ON cr.buyer_id = u_buyer.user_id
      LEFT JOIN users u_seller ON cr.seller_id = u_seller.user_id
      WHERE cr.id = ?
    `, [userId, chatRoomId]);

    if (room.length > 0) {
      res.json({ success: true, chatRoom: room[0] });
    } else {
      res.status(404).json({ success: false, message: 'Chat room not found' });
    }
  } catch (error) {
    console.error('Error getting chat room:', error);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
});

module.exports = router;
