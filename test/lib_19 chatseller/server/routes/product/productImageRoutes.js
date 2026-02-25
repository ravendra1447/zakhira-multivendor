const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// Configure multer for product image uploads
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadPath = path.join(__dirname, '../../../uploads/products');
    if (!fs.existsSync(uploadPath)) {
      fs.mkdirSync(uploadPath, { recursive: true });
    }
    cb(null, uploadPath);
  },
  filename: (req, file, cb) => {
    const userId = req.body.user_id || "unknown";
    const timestamp = Date.now();
    const ext = path.extname(file.originalname);
    cb(null, `user_${userId}_product_${timestamp}${ext}`);
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

// Edit product image
router.post('/edit_image', upload.single('image'), async (req, res) => {
  try {
    const { user_id, product_id } = req.body;
    
    console.log('🔍 EDIT IMAGE REQUEST:', {
      user_id,
      product_id
    });
    
    if (!user_id || !product_id) {
      return res.status(400).json({
        success: false,
        message: 'User ID and Product ID are required'
      });
    }

    let imageUrl;
    if (req.file) {
      // New image uploaded
      imageUrl = `${BASE_URL}/uploads/products/${req.file.filename}`;
    } else if (req.body.new_image_url) {
      // Using existing image URL
      imageUrl = req.body.new_image_url;
    } else {
      return res.status(400).json({
        success: false,
        message: 'No image provided'
      });
    }

    // Get current product data (like productRoutes.js)
    const [productData] = await req.db.execute(
      'SELECT * FROM products WHERE id = ? AND user_id = ?',
      [product_id, user_id]
    );
    
    if (productData.length === 0) {
      console.log('❌ User does not own this product');
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to edit this product'
      });
    }

    const product = productData[0];
    let variationsArray = [];
    let imagesArray = [];
    
    try {
      variationsArray = JSON.parse(product.variations || '[]');
      imagesArray = JSON.parse(product.images || '[]');
      console.log('🔍 Current variations:', JSON.stringify(variationsArray, null, 2));
      console.log('🔍 Current images:', JSON.stringify(imagesArray, null, 2));
    } catch (e) {
      console.log('❌ Error parsing product data:', e);
      variationsArray = [];
      imagesArray = [];
    }

    // Add new image to images array (like productRoutes.js pattern)
    imagesArray.push(imageUrl);
    
    // Update first variation's main image if exists
    if (variationsArray.length > 0) {
      variationsArray[0].image = imageUrl;
      if (!variationsArray[0].allImages) {
        variationsArray[0].allImages = [];
      }
      variationsArray[0].allImages.push(imageUrl);
      console.log('🔍 Updated first variation with new image');
    }

    // Update products table
    const updateQuery = `
      UPDATE products 
      SET images = ?, variations = ?, updated_at = NOW()
      WHERE id = ? AND user_id = ?
    `;
    
    const [result] = await req.db.execute(updateQuery, [
      JSON.stringify(imagesArray), 
      JSON.stringify(variationsArray), 
      product_id, 
      user_id
    ]);
    
    console.log('🔍 Database update result:', result.affectedRows);

    if (result.affectedRows > 0) {
      // Resave to ALL related tables (like productRoutes.js)
      // 1. Resave to product_colors table
      await req.db.execute('DELETE FROM product_colors WHERE product_id = ?', [product_id]);
      for (const variant of variationsArray) {
        if (variant.name) {
          let finalStock = 0;
          if (typeof variant.stock === 'object' && variant.stock !== null) {
            finalStock = Object.values(variant.stock).reduce((sum, qty) => sum + (parseInt(qty) || 0), 0);
          } else {
            finalStock = parseInt(variant.stock) || parseInt(variant.totalStock) || 0;
          }
          
          const variantPrice = variant.price || product.price || 0;
          
          await req.db.execute(
            `INSERT INTO product_colors
            (product_id, color_name, image_url, price, stock)
            VALUES (?, ?, ?, ?, ?)`,
            [
              product_id,
              variant.name,
              variant.image || null,
              variantPrice,
              finalStock
            ]
          );
          console.log(`✅ Resaved to product_colors: ${variant.name}`);
        }
      }
      
      // 2. Resave to product_sizes table
      await req.db.execute('DELETE FROM product_sizes WHERE product_id = ?', [product_id]);
      const sizeStockMap = {};
      if (variationsArray.length > 0) {
        for (const variant of variationsArray) {
          if (variant.stock && typeof variant.stock === 'object') {
            for (const size in variant.stock) {
              if (!sizeStockMap[size]) {
                sizeStockMap[size] = 0;
              }
              sizeStockMap[size] += parseInt(variant.stock[size]) || 0;
            }
          }
        }
      }
      
      // Get sizes from product data
      let sizesArray = [];
      try {
        sizesArray = JSON.parse(product.sizes || '[]');
      } catch (e) {
        sizesArray = [];
      }
      
      for (const size of sizesArray) {
        const sizeStock = sizeStockMap[size] || 0;
        await req.db.execute(
          `INSERT INTO product_sizes
          (product_id, size, price, stock)
          VALUES (?, ?, ?, ?)`,
          [product_id, size, product.price || 0, sizeStock]
        );
        console.log(`✅ Resaved to product_sizes: ${size}`);
      }
      
      // 3. Resave to product_images table
      await req.db.execute('DELETE FROM product_images WHERE product_id = ?', [product_id]);
      for (const imageUrl of imagesArray) {
        await req.db.execute(
          `INSERT INTO product_images (product_id, image_url)
          VALUES (?, ?)`,
          [product_id, imageUrl]
        );
      }
      
      // 4. Resave to product_variants table
      await req.db.execute('DELETE FROM product_variants WHERE product_id = ?', [product_id]);
      if (variationsArray.length > 0 && sizesArray.length > 0) {
        for (const variant of variationsArray) {
          const colorName = variant.name;
          if (colorName && variant.stock && typeof variant.stock === 'object') {
            for (const size in variant.stock) {
              if (sizesArray.includes(size)) {
                const sizeStock = parseInt(variant.stock[size]) || 0;
                const variantPrice = variant.price || product.price || 0;
                
                await req.db.execute(
                  `INSERT INTO product_variants
                  (product_id, color_name, size, stock, price)
                  VALUES (?, ?, ?, ?, ?)`,
                  [product_id, colorName, size, sizeStock, variantPrice]
                );
                console.log(`✅ Resaved variant: ${colorName}-${size}`);
              }
            }
          }
        }
      }
      
      console.log('✅ Product image updated successfully:', {
        product_id,
        new_image_url: imageUrl
      });
      
      res.json({
        success: true,
        message: 'Product image updated successfully',
        data: {
          image_url: imageUrl,
          product_id: product_id,
          images: imagesArray,
          variations: variationsArray
        }
      });
    } else {
      res.status(500).json({
        success: false,
        message: 'Failed to update product image'
      });
    }

  } catch (error) {
    console.error('❌ Error updating product image:', error);
    res.status(500).json({
      success: false,
      message: 'Server error: ' + error.message
    });
  }
});

// Delete product image
router.post('/delete_image', async (req, res) => {
  try {
    const { user_id, product_id } = req.body;
    
    console.log('🔍 DELETE IMAGE REQUEST:', {
      user_id,
      product_id
    });
    
    if (!user_id || !product_id) {
      return res.status(400).json({
        success: false,
        message: 'User ID and Product ID are required'
      });
    }

    // Get current product data (like productRoutes.js)
    const [productData] = await req.db.execute(
      'SELECT * FROM products WHERE id = ? AND user_id = ?',
      [product_id, user_id]
    );
    
    console.log('🔍 Product verification rows:', productData.length);
    
    if (productData.length === 0) {
      console.log('❌ User does not own this product');
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to delete this product image'
      });
    }

    const product = productData[0];
    let variationsArray = [];
    let imagesArray = [];
    
    try {
      variationsArray = JSON.parse(product.variations || '[]');
      imagesArray = JSON.parse(product.images || '[]');
      console.log('🔍 Current variations before delete:', JSON.stringify(variationsArray, null, 2));
      console.log('🔍 Current images before delete:', JSON.stringify(imagesArray, null, 2));
    } catch (e) {
      variationsArray = [];
      imagesArray = [];
      console.log('❌ Error parsing product data:', e);
    }

    // Remove last image from arrays (like productRoutes.js pattern)
    let deletedImageUrl = null;
    if (imagesArray.length > 0) {
      deletedImageUrl = imagesArray.pop(); // Remove last image
      console.log('✅ Deleted image URL:', deletedImageUrl);
    }

    // Update first variation if exists
    if (variationsArray.length > 0 && variationsArray[0].allImages) {
      if (variationsArray[0].allImages.length > 0) {
        variationsArray[0].allImages.pop();
        console.log('✅ Removed image from first variation');
        
        // Update main image if needed
        if (variationsArray[0].allImages.length > 0) {
          variationsArray[0].image = variationsArray[0].allImages[0];
          console.log('✅ Updated main image to next available');
        } else {
          variationsArray[0].image = null;
          console.log('✅ No more images, set main image to null');
        }
      }
    }

    // Update products table
    const updateQuery = `
      UPDATE products 
      SET images = ?, variations = ?, updated_at = NOW()
      WHERE id = ? AND user_id = ?
    `;
    
    const [result] = await req.db.execute(updateQuery, [
      JSON.stringify(imagesArray), 
      JSON.stringify(variationsArray), 
      product_id, 
      user_id
    ]);
    
    console.log('🔍 Database update result:', result.affectedRows);

    if (result.affectedRows > 0) {
      // Delete physical file if it exists and is a local upload
      if (deletedImageUrl && deletedImageUrl.includes('/uploads/')) {
        try {
          const filePath = path.join(__dirname, '../../..', deletedImageUrl.replace(BASE_URL, ''));
          if (fs.existsSync(filePath)) {
            fs.unlinkSync(filePath);
            console.log('✅ Deleted product image file:', filePath);
          } else {
            console.log('⚠️ File not found for deletion:', filePath);
          }
        } catch (fileError) {
          console.error('❌ Error deleting product image file:', fileError);
        }
      }
      
      // Resave to ALL related tables after deletion (like productRoutes.js)
      // 1. Resave to product_colors table
      await req.db.execute('DELETE FROM product_colors WHERE product_id = ?', [product_id]);
      for (const variant of variationsArray) {
        if (variant.name) {
          let finalStock = 0;
          if (typeof variant.stock === 'object' && variant.stock !== null) {
            finalStock = Object.values(variant.stock).reduce((sum, qty) => sum + (parseInt(qty) || 0), 0);
          } else {
            finalStock = parseInt(variant.stock) || parseInt(variant.totalStock) || 0;
          }
          
          const variantPrice = variant.price || product.price || 0;
          
          await req.db.execute(
            `INSERT INTO product_colors
            (product_id, color_name, image_url, price, stock)
            VALUES (?, ?, ?, ?, ?)`,
            [
              product_id,
              variant.name,
              variant.image || null,
              variantPrice,
              finalStock
            ]
          );
          console.log(`✅ Resaved to product_colors: ${variant.name}`);
        }
      }
      
      // 2. Resave to product_sizes table
      await req.db.execute('DELETE FROM product_sizes WHERE product_id = ?', [product_id]);
      const sizeStockMap = {};
      if (variationsArray.length > 0) {
        for (const variant of variationsArray) {
          if (variant.stock && typeof variant.stock === 'object') {
            for (const size in variant.stock) {
              if (!sizeStockMap[size]) {
                sizeStockMap[size] = 0;
              }
              sizeStockMap[size] += parseInt(variant.stock[size]) || 0;
            }
          }
        }
      }
      
      // Get sizes from product data
      let sizesArray = [];
      try {
        sizesArray = JSON.parse(product.sizes || '[]');
      } catch (e) {
        sizesArray = [];
      }
      
      for (const size of sizesArray) {
        const sizeStock = sizeStockMap[size] || 0;
        await req.db.execute(
          `INSERT INTO product_sizes
          (product_id, size, price, stock)
          VALUES (?, ?, ?, ?)`,
          [product_id, size, product.price || 0, sizeStock]
        );
        console.log(`✅ Resaved to product_sizes: ${size}`);
      }
      
      // 3. Resave to product_images table
      await req.db.execute('DELETE FROM product_images WHERE product_id = ?', [product_id]);
      for (const imageUrl of imagesArray) {
        await req.db.execute(
          `INSERT INTO product_images (product_id, image_url)
          VALUES (?, ?)`,
          [product_id, imageUrl]
        );
      }
      
      // 4. Resave to product_variants table
      await req.db.execute('DELETE FROM product_variants WHERE product_id = ?', [product_id]);
      if (variationsArray.length > 0 && sizesArray.length > 0) {
        for (const variant of variationsArray) {
          const colorName = variant.name;
          if (colorName && variant.stock && typeof variant.stock === 'object') {
            for (const size in variant.stock) {
              if (sizesArray.includes(size)) {
                const sizeStock = parseInt(variant.stock[size]) || 0;
                const variantPrice = variant.price || product.price || 0;
                
                await req.db.execute(
                  `INSERT INTO product_variants
                  (product_id, color_name, size, stock, price)
                  VALUES (?, ?, ?, ?, ?)`,
                  [product_id, colorName, size, sizeStock, variantPrice]
                );
                console.log(`✅ Resaved variant: ${colorName}-${size}`);
              }
            }
          }
        }
      }

      console.log('✅ Product image deleted successfully:', {
        product_id,
        deleted_image_url: deletedImageUrl
      });
      
      res.json({
        success: true,
        message: 'Product image deleted successfully',
        data: {
          product_id: product_id,
          images: imagesArray,
          variations: variationsArray
        }
      });
    } else {
      res.status(500).json({
        success: false,
        message: 'Failed to delete product image'
      });
    }

  } catch (error) {
    console.error('❌ Error deleting product image:', error);
    res.status(500).json({
      success: false,
      message: 'Server error: ' + error.message
    });
  }
});

module.exports = router;
