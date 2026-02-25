const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// Configure multer for profile image uploads
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadPath = path.join(__dirname, '../../../uploads/profile_images');
    if (!fs.existsSync(uploadPath)) {
      fs.mkdirSync(uploadPath, { recursive: true });
    }
    cb(null, uploadPath);
  },
  filename: (req, file, cb) => {
    const userId = req.body.user_id || "unknown";
    const timestamp = Date.now();
    const ext = path.extname(file.originalname);
    cb(null, `user_${userId}_profile_${timestamp}${ext}`);
  }
});

const upload = multer({
  storage: storage,
  limits: {
    fileSize: 10 * 1024 * 1024 // 10MB limit
  },
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed'), false);
    }
  }
});

// Base URL for serving images
const BASE_URL = process.env.BASE_URL || "https://bangkokmart.in";

// Edit profile image
router.post('/edit_image', upload.single('image'), async (req, res) => {
  try {
    const { user_id, image_id, new_image_url } = req.body;
    
    console.log('🔍 EDIT PROFILE IMAGE REQUEST:', {
      user_id,
      image_id,
      new_image_url
    });
    
    if (!user_id || !image_id) {
      return res.status(400).json({
        success: false,
        message: 'User ID and Image ID are required'
      });
    }

    let imageUrl;
    if (req.file) {
      // New image uploaded
      imageUrl = `${BASE_URL}/uploads/profile_images/${req.file.filename}`;
    } else if (new_image_url) {
      // Using existing image URL
      imageUrl = new_image_url;
    } else {
      return res.status(400).json({
        success: false,
        message: 'No image provided'
      });
    }

    // Update users table
    const updateQuery = `
      UPDATE users 
      SET profile_image = ?, updated_at = NOW()
      WHERE id = ?
    `;
    
    const [result] = await req.db.execute(updateQuery, [imageUrl, user_id]);

    if (result.affectedRows > 0) {
      console.log('✅ Profile image updated successfully:', {
        user_id,
        image_id,
        new_image_url: imageUrl
      });
      
      res.json({
        success: true,
        message: 'Profile image updated successfully',
        data: {
          image_url: imageUrl,
          image_id: image_id
        }
      });
    } else {
      res.status(404).json({
        success: false,
        message: 'Profile not found or no changes made'
      });
    }

  } catch (error) {
    console.error('❌ Error updating profile image:', error);
    res.status(500).json({
      success: false,
      message: 'Server error: ' + error.message
    });
  }
});

// Delete profile image
router.post('/delete_image', async (req, res) => {
  try {
    const { user_id, image_id } = req.body;
    
    console.log('🔍 DELETE PROFILE IMAGE REQUEST:', {
      user_id,
      image_id
    });
    
    if (!user_id || !image_id) {
      return res.status(400).json({
        success: false,
        message: 'User ID and Image ID are required'
      });
    }

    // Get current image URL from users table
    const selectQuery = `
      SELECT profile_image FROM users 
      WHERE id = ?
    `;
    
    const [rows] = await req.db.execute(selectQuery, [user_id]);
    
    if (rows.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const currentImageUrl = rows[0].profile_image;

    // Update users table to remove image
    const updateQuery = `
      UPDATE users 
      SET profile_image = NULL, updated_at = NOW()
      WHERE id = ?
    `;
    
    const [result] = await req.db.execute(updateQuery, [user_id]);

    if (result.affectedRows > 0) {
      // Delete physical file if it exists and is not a default/external URL
      if (currentImageUrl && 
          currentImageUrl.startsWith('/uploads/') && 
          !currentImageUrl.includes('default')) {
        try {
          const filePath = path.join(__dirname, '../../..', currentImageUrl);
          if (fs.existsSync(filePath)) {
            fs.unlinkSync(filePath);
            console.log('✅ Deleted profile image file:', filePath);
          }
        } catch (fileError) {
          console.error('❌ Error deleting profile image file:', fileError);
        }
      }

      console.log('✅ Profile image deleted successfully:', {
        user_id,
        image_id,
        deleted_image_url: currentImageUrl
      });
      
      res.json({
        success: true,
        message: 'Profile image deleted successfully',
        data: {
          image_id: image_id
        }
      });
    } else {
      res.status(404).json({
        success: false,
        message: 'No changes made'
      });
    }

  } catch (error) {
    console.error('❌ Error deleting profile image:', error);
    res.status(500).json({
      success: false,
      message: 'Server error: ' + error.message
    });
  }
});

module.exports = router;
