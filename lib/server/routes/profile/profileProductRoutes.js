// Profile Product Management Routes
// For editing and deleting products from user profile

const express = require("express");
const router = express.Router();
const mysql = require("mysql2/promise");

// Database connection pool
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db",
});

// Middleware to verify user ownership
async function verifyProductOwnership(userId, productId) {
  try {
    const [products] = await pool.execute(
      "SELECT user_id FROM products WHERE id = ? AND user_id = ?",
      [productId, userId]
    );
    return products.length > 0;
  } catch (error) {
    console.error("Error verifying product ownership:", error);
  }
}

// PUT /api/profile/products/:productId/edit - Edit product (update all fields)
router.put('/products/:productId/edit', async (req, res) => {
  try {
    const { 
      userId, 
      description, 
      availableQty, 
      priceSlabs, 
      sizes, 
      variations, 
      stockMode, 
      stockByColorSize, 
      attributes, 
      selectedAttributeValues, 
      alwaysAvailable, 
      dispatchTime, 
      showMadeOnOrderBadge 
    } = req.body;
    const productId = parseInt(req.params.productId);

    if (!userId || !productId) {
      return res.status(400).json({
        success: false,
        message: 'Missing required fields: userId, productId'
      });
    }

    // Verify ownership
    const isOwner = await verifyProductOwnership(userId, productId);
    if (!isOwner) {
      return res.status(403).json({
        success: false,
        message: 'You can only edit your own products'
      });
    }

    // Start transaction
    const connection = await pool.getConnection();
    await connection.beginTransaction();

    try {
      // Update main product fields
      await connection.execute(
        `UPDATE products 
         SET description = ?, 
             available_qty = ?, 
             stock_mode = ?,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = ? AND user_id = ?`,
        [
          description || null, 
          availableQty || 0, 
          stockMode || 'simple',
          productId, 
          userId
        ]
      );

      // Update price slabs
      if (priceSlabs && Array.isArray(priceSlabs)) {
        // Update price slabs in products table
        await connection.execute(
          `UPDATE products 
           SET price_slabs = ? 
           WHERE id = ? AND user_id = ?`,
          [JSON.stringify(priceSlabs), productId, userId]
        );
      }

      // Update sizes
      if (sizes && Array.isArray(sizes)) {
        // Update sizes in products table
        await connection.execute(
          `UPDATE products 
           SET sizes = ? 
           WHERE id = ? AND user_id = ?`,
          [JSON.stringify(sizes), productId, userId]
        );
      }

      // Update variations
      if (variations && Array.isArray(variations)) {
        // Update variations in products table
        await connection.execute(
          `UPDATE products 
           SET variations = ? 
           WHERE id = ? AND user_id = ?`,
          [JSON.stringify(variations), productId, userId]
        );
      }

      // Update attributes in products table
      if (attributes && typeof attributes === 'object') {
        await connection.execute(
          `UPDATE products 
           SET attributes = ?, 
               selected_attribute_values = ?
           WHERE id = ? AND user_id = ?`,
          [JSON.stringify(attributes), JSON.stringify(selectedAttributeValues || {}), productId, userId]
        );
      }

      // ==================== UPDATE ALL RELATED TABLES ====================

      // Parse JSON data from requests
      let attributesJson = {};
      let selectedAttributesJson = {};
      let priceSlabsArray = [];
      let processedVariations = [];
      let processedSizes = [];
      let stockData = {};
      let stock_mode = req.body.stockMode || 'simple'; // Fix: Add stock_mode variable

      try {
        attributesJson = typeof attributes === 'string' ? JSON.parse(attributes) : attributes || {};
      } catch (e) {
        attributesJson = attributes || {};
      }

      try {
        selectedAttributesJson = typeof req.body.selectedAttributeValues === 'string' 
          ? JSON.parse(req.body.selectedAttributeValues) 
          : req.body.selectedAttributeValues || {};
      } catch (e) {
        selectedAttributesJson = req.body.selectedAttributeValues || {};
      }

      try {
        priceSlabsArray = typeof priceSlabs === 'string' ? JSON.parse(priceSlabs) : priceSlabs || [];
      } catch (e) {
        priceSlabsArray = priceSlabs || [];
      }

      try {
        processedVariations = typeof variations === 'string' ? JSON.parse(variations) : variations || [];
      } catch (e) {
        processedVariations = variations || [];
      }

      try {
        processedSizes = typeof sizes === 'string' ? JSON.parse(sizes) : sizes || [];
      } catch (e) {
        processedSizes = sizes || [];
      }

      try {
        stockData = typeof stockByColorSize === 'string' ? JSON.parse(stockByColorSize) : stockByColorSize || {};
      } catch (e) {
        stockData = stockByColorSize || {};
      }

      // Calculate base price from price slabs
      let basePrice = 0;
      if (priceSlabsArray && priceSlabsArray.length > 0) {
        const prices = priceSlabsArray
          .filter(slab => slab.price && !isNaN(slab.price))
          .map(slab => parseFloat(slab.price));
        if (prices.length > 0) {
          basePrice = Math.min(...prices);
        }
      }

      console.log(`🔄 Updating product ${productId} in all related tables...`);

      // ==================== GET EXISTING DATA ====================
      console.log(`📋 Getting existing data from tables...`);
      
      // Get existing sizes from database
      const [existingSizes] = await connection.execute(
        'SELECT DISTINCT size FROM product_sizes WHERE product_id = ?',
        [productId]
      );
      const existingSizeList = existingSizes.map(row => row.size);
      
      // Get existing colors from database
      const [existingColors] = await connection.execute(
        'SELECT DISTINCT color_name FROM product_colors WHERE product_id = ?',
        [productId]
      );
      const existingColorList = existingColors.map(row => row.color_name);
      
      // Get existing attributes from database
      const [existingAttributes] = await connection.execute(
        'SELECT DISTINCT attributes_name FROM tbl_product_attributes WHERE product_id = ?',
        [productId]
      );
      const existingAttributeList = existingAttributes.map(row => row.attributes_name);
      
      // Get existing price slabs from database
      const [existingPriceSlabs] = await connection.execute(
        'SELECT DISTINCT min_qty FROM tbl_product_range_prices WHERE product_id = ?',
        [productId]
      );
      const existingPriceSlabList = existingPriceSlabs.map(row => row.min_qty);
      
      console.log(`📊 Existing - Sizes: ${existingSizeList.length}, Colors: ${existingColorList.length}, Attributes: ${existingAttributeList.length}`);
      
      // ==================== MERGE EXISTING + NEW DATA ====================
      console.log(`🔄 Merging existing and new data...`);
      
      // Merge sizes: existing + new (no duplicates)
      const allSizes = [...new Set([...existingSizeList, ...processedSizes])];
      
      // Merge colors: existing + new (no duplicates)
      const allColorNames = processedVariations.map(v => v.name).filter(name => name);
      const allColors = [...new Set([...existingColorList, ...allColorNames])];
      
      // Merge attributes: existing + new (no duplicates)
      const currentAttributeNames = attributesJson ? Object.keys(attributesJson) : [];
      const allAttributes = [...new Set([...existingAttributeList, ...currentAttributeNames])];
      
      // Merge price slabs: existing + new (no duplicates)
      const currentMinQties = priceSlabsArray ? priceSlabsArray.map(slab => slab.min_qty).filter(qty => qty) : [];
      const allPriceSlabs = [...new Set([...existingPriceSlabList, ...currentMinQties])];
      
      console.log(`📊 Merged - Sizes: ${allSizes.length}, Colors: ${allColors.length}, Attributes: ${allAttributes.length}`);
      
      // Update processed data to include existing ones
      processedSizes = allSizes;
      
      // Update processed variations to include existing colors
      const mergedVariations = [];
      for (const colorName of allColors) {
        const existingVariant = processedVariations.find(v => v.name === colorName);
        if (existingVariant) {
          mergedVariations.push(existingVariant);
        } else {
          // Add existing color with default values
          mergedVariations.push({
            name: colorName,
            price: basePrice || 0,
            stock: 0,
            image: null
          });
        }
      }
      processedVariations = mergedVariations;
      
      // Update attributesJson to include existing ones
      if (attributesJson) {
        for (const attrName of allAttributes) {
          if (!attributesJson[attrName]) {
            attributesJson[attrName] = []; // Add existing attribute with empty values
          }
        }
      }
      
      // Update priceSlabsArray to include existing ones
      if (priceSlabsArray) {
        for (const minQty of allPriceSlabs) {
          const existingSlab = priceSlabsArray.find(slab => slab.min_qty === minQty);
          if (!existingSlab) {
            // Add existing price slab with default values
            priceSlabsArray.push({
              min_qty: minQty,
              price: basePrice || 0
            });
          }
        }
      }

      // ==================== ACTUAL UPDATE ALL TABLES ====================
      console.log(`💾 Updating all tables with merged data...`);

      // 1. UPDATE product_attributes_master and tbl_product_attributes
      if (attributesJson && typeof attributesJson === 'object' && Object.keys(attributesJson).length > 0) {
        console.log(`Found ${Object.keys(attributesJson).length} attributes to update`);

        for (const [attributeName, attributeValues] of Object.entries(attributesJson)) {
          // Check if attribute exists in master for this seller
          const [existingMasterAttr] = await connection.execute(
            `SELECT id FROM product_attributes_master
             WHERE seller_id = ? AND attributes_name = ?`,
            [userId, attributeName]
          );

          let masterAttrId;
          if (existingMasterAttr.length === 0) {
            // Insert new attribute into master
            const [insertResult] = await connection.execute(
              `INSERT INTO product_attributes_master
              (seller_id, attributes_name, status)
              VALUES (?, ?, 1)`,
              [userId, attributeName]
            );
            masterAttrId = insertResult.insertId;
            console.log(`✅ Added to master table: ${attributeName}, ID: ${masterAttrId}`);
          } else {
            masterAttrId = existingMasterAttr[0].id;
            console.log(`✅ Found in master table: ${attributeName}, ID: ${masterAttrId}`);
          }

          // Update tbl_product_attributes using INSERT...ON DUPLICATE KEY UPDATE
          const selectedValue = selectedAttributesJson[attributeName];
          if (selectedValue) {
            await connection.execute(
              `INSERT INTO tbl_product_attributes
              (product_id, seller_id, attributes_id, attributes_name, status, created_at)
              VALUES (?, ?, ?, ?, 1, NOW())
              ON DUPLICATE KEY UPDATE 
              attributes_id = VALUES(attributes_id),
              status = VALUES(status),
              created_at = VALUES(created_at)`,
              [productId, userId, masterAttrId, attributeName]
            );
            console.log(`✅ Updated tbl_product_attributes: ${attributeName} = ${selectedValue}`);
          }
        }
      }

      // 2. UPDATE tbl_product_range_prices
      if (priceSlabsArray && Array.isArray(priceSlabsArray) && priceSlabsArray.length > 0) {
        console.log(`Found ${priceSlabsArray.length} price slabs to update`);

        // Update price slabs using INSERT...ON DUPLICATE KEY UPDATE
        for (const slab of priceSlabsArray) {
          if (slab.min_qty && slab.price) {
            await connection.execute(
              `INSERT INTO tbl_product_range_prices
              (product_id, seller_id, min_qty, price, status, created_at)
              VALUES (?, ?, ?, ?, 1, NOW())
              ON DUPLICATE KEY UPDATE 
              price = VALUES(price),
              status = VALUES(status),
              created_at = VALUES(created_at)`,
              [productId, userId, slab.min_qty, slab.price]
            );
            console.log(`✅ Updated price slab: MOQ=${slab.min_qty}, Price=${slab.price}`);
          }
        }
      }

      // 3. UPDATE product_colors table
      if (processedVariations && processedVariations.length > 0) {
        console.log(`Found ${processedVariations.length} colors to update`);

        // Update colors using INSERT...ON DUPLICATE KEY UPDATE
        for (const variant of processedVariations) {
          if (variant.name) {
            let finalStock = 0;
            
            if (stock_mode === 'color_size' && stockData[variant.name]) {
              const sizesObj = stockData[variant.name] || {};
              finalStock = Object.values(sizesObj).reduce((sum, qty) => sum + (parseInt(qty) || 0), 0);
            } else if (variant.stock) {
              if (typeof variant.stock === 'object') {
                finalStock = Object.values(variant.stock).reduce((sum, qty) => sum + (parseInt(qty) || 0), 0);
              } else {
                finalStock = parseInt(variant.stock) || 0;
              }
            }

            const variantPrice = variant.price || basePrice || 0;

            await connection.execute(
              `INSERT INTO product_colors
              (product_id, color_name, color_code, image_url, price, stock)
              VALUES (?, ?, ?, ?, ?, ?)
              ON DUPLICATE KEY UPDATE 
              color_code = VALUES(color_code),
              image_url = VALUES(image_url),
              price = VALUES(price),
              stock = VALUES(stock)`,
              [
                productId,
                variant.name,
                variant.color_code || null,
                variant.image || null,
                variantPrice,
                finalStock
              ]
            );
            console.log(`✅ Updated product_colors: ${variant.name}, Price: ${variantPrice}, Stock: ${finalStock}`);
          }
        }
      }

      // 4. UPDATE product_sizes table
      if (processedSizes && processedSizes.length > 0) {
        console.log(`Found ${processedSizes.length} sizes to update`);

        // Calculate size-wise stock
        const sizeStockMap = {};
        if (stock_mode === 'color_size' && Object.keys(stockData).length > 0) {
          for (const colorName in stockData) {
            const sizesObj = stockData[colorName];
            for (const size in sizesObj) {
              if (!sizeStockMap[size]) {
                sizeStockMap[size] = 0;
              }
              sizeStockMap[size] += parseInt(sizesObj[size]) || 0;
            }
          }
        }

        // Update sizes using INSERT...ON DUPLICATE KEY UPDATE
        for (const size of processedSizes) {
          const sizeStock = sizeStockMap[size] || 0;
          await connection.execute(
            `INSERT INTO product_sizes
            (product_id, size, price, stock)
            VALUES (?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE 
            price = VALUES(price),
            stock = VALUES(stock)`,
            [productId, size, basePrice || 0, sizeStock]
          );
          console.log(`✅ Updated product_sizes: ${size}, Price: ${basePrice || 0}, Stock: ${sizeStock}`);
        }
      }

      // 5. UPDATE product_variants table
      if (processedVariations.length > 0 && processedSizes.length > 0) {
        console.log(`Updating product_variants table`);

        // Update variants using INSERT...ON DUPLICATE KEY UPDATE
        if (stock_mode === 'color_size' && Object.keys(stockData).length > 0) {
          for (const [colorName, sizesObj] of Object.entries(stockData)) {
            const colorVariant = processedVariations.find(v => v.name === colorName);
            const variantPrice = colorVariant?.price || basePrice || 0;

            for (const [size, qty] of Object.entries(sizesObj)) {
              await connection.execute(
                `INSERT INTO product_variants
                (product_id, color_name, size, stock, price)
                VALUES (?, ?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE 
                stock = VALUES(stock),
                price = VALUES(price)`,
                [productId, colorName, size, parseInt(qty) || 0, variantPrice]
              );
              console.log(`✅ Updated variant: ${colorName}-${size}, Price: ${variantPrice}, Stock: ${qty}`);
            }
          }
        }
      }

      console.log(`✅ All related tables updated for product ${productId}`);

      // Update simple stock if needed
      if (stockMode === 'simple' && availableQty !== undefined) {
        await connection.execute(
          `UPDATE products SET available_qty = ? WHERE id = ?`,
          [availableQty, productId]
        );
      }

      await connection.commit();

      res.json({
        success: true,
        message: 'Product updated successfully'
      });

    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }

  } catch (error) {
    console.error('Error editing product:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update product',
      error: error.message
    });
  }
});

// Soft delete single product
router.delete('/products/:productId', async (req, res) => {
  try {
    const { productId } = req.params;
    const { userId } = req.body;

    if (!userId || !productId) {
      return res.status(400).json({
        success: false,
        message: 'User ID and Product ID are required'
      });
    }

    // Verify ownership
    const isOwner = await verifyProductOwnership(userId, productId);
    if (!isOwner) {
      return res.status(403).json({
        success: false,
        message: 'You can only delete your own products'
      });
    }

        // Delete from all related tables first
    const connection = await pool.getConnection();
    await connection.beginTransaction();
    
    try {
      console.log(`🗑️ Deleting product ${productId} from all related tables...`);
      
      // 1. Delete from product_images
      await connection.execute(
        'DELETE FROM product_images WHERE product_id = ?',
        [productId]
      );
      
      // 2. Delete from product_variants
      await connection.execute(
        'DELETE FROM product_variants WHERE product_id = ?',
        [productId]
      );
      
      // 3. Delete from product_sizes
      await connection.execute(
        'DELETE FROM product_sizes WHERE product_id = ?',
        [productId]
      );
      
      // 4. Delete from product_colors
      await connection.execute(
        'DELETE FROM product_colors WHERE product_id = ?',
        [productId]
      );
      
      // 5. Delete from tbl_product_range_prices
      await connection.execute(
        'DELETE FROM tbl_product_range_prices WHERE product_id = ?',
        [productId]
      );
      
      // 6. Delete from tbl_product_attributes
      await connection.execute(
        'DELETE FROM tbl_product_attributes WHERE product_id = ?',
        [productId]
      );
      
      // 7. Soft delete from products table
      const [result] = await connection.execute(
        `UPDATE products 
         SET is_active = 0, 
             marketplace_enabled = 0, 
             updated_at = CURRENT_TIMESTAMP
         WHERE id = ? AND user_id = ?`,
        [productId, userId]
      );
      
      await connection.commit();
      console.log(`✅ Product ${productId} deleted from all related tables`);
      
      if (result.affectedRows === 0) {
        return res.status(404).json({
          success: false,
          message: 'Product not found'
        });
      }
      
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }

    res.json({
      success: true,
      message: 'Product deleted successfully'
    });

  } catch (error) {
    console.error('Error deleting product:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete product'
    });
  }
});

// Soft delete multiple products
router.delete('/products/bulk', async (req, res) => {
  try {
    const { userId, productIds } = req.body;

    if (!userId || !productIds || !Array.isArray(productIds) || productIds.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'User ID and Product IDs array are required'
      });
    }

    // Create placeholders for IN clause
    const placeholders = productIds.map(() => '?').join(',');
    
    // Verify ownership for all products
    const [ownershipCheck] = await pool.execute(
      `SELECT id FROM products 
       WHERE id IN (${placeholders}) AND user_id = ?`,
      [...productIds, userId]
    );

    if (ownershipCheck.length !== productIds.length) {
      return res.status(403).json({
        success: false,
        message: 'You can only delete your own products'
      });
    }

    // Soft delete all products
    const [result] = await pool.execute(
      `UPDATE products 
       SET is_active = 0, 
           marketplace_enabled = 0, 
           updated_at = CURRENT_TIMESTAMP
       WHERE id IN (${placeholders}) AND user_id = ?`,
      [...productIds, userId]
    );

    res.json({
      success: true,
      message: `${result.affectedRows} products deleted successfully`
    });

  } catch (error) {
    console.error('Error bulk deleting products:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete products'
    });
  }
});

// Hard delete single product (permanent deletion)
router.delete('/products/:productId/hard', async (req, res) => {
  try {
    const { productId } = req.params;
    const { userId } = req.body;

    if (!userId || !productId) {
      return res.status(400).json({
        success: false,
        message: 'User ID and Product ID are required'
      });
    }

    // Verify ownership
    const isOwner = await verifyProductOwnership(userId, productId);
    if (!isOwner) {
      return res.status(403).json({
        success: false,
        message: 'You can only delete your own products'
      });
    }

    // Hard delete - remove from database completely
    const [result] = await pool.execute(
      "DELETE FROM products WHERE id = ? AND user_id = ?",
      [productId, userId]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        message: 'Product not found'
      });
    }

    res.json({
      success: true,
      message: 'Product permanently deleted'
    });

  } catch (error) {
    console.error('Error hard deleting product:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete product'
    });
  }
});

// Hard delete multiple products (permanent deletion)
router.delete('/products/bulk/hard', async (req, res) => {
  try {
    const { userId, productIds } = req.body;

    if (!userId || !productIds || !Array.isArray(productIds) || productIds.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'User ID and Product IDs array are required'
      });
    }

    // Create placeholders for IN clause
    const placeholders = productIds.map(() => '?').join(',');
    
    // Verify ownership for all products
    const [ownershipCheck] = await pool.execute(
      `SELECT id FROM products 
       WHERE id IN (${placeholders}) AND user_id = ?`,
      [...productIds, userId]
    );

    if (ownershipCheck.length !== productIds.length) {
      return res.status(403).json({
        success: false,
        message: 'You can only delete your own products'
      });
    }

    // Hard delete all products
    const [result] = await pool.execute(
      `DELETE FROM products 
       WHERE id IN (${placeholders}) AND user_id = ?`,
      [...productIds, userId]
    );

    res.json({
      success: true,
      message: `${result.affectedRows} products permanently deleted`
    });

  } catch (error) {
    console.error('Error bulk hard deleting products:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete products'
    });
  }
});

// GET /api/profile/products/:productId/edit-data
// Get product with all attributes for editing
router.get('/products/:productId/edit-data', async (req, res) => {
  try {
    const { productId } = req.params;
    const userId = req.query.userId;

    if (!userId || !productId) {
      return res.status(400).json({
        success: false,
        message: 'userId and productId are required'
      });
    }

    // Verify ownership
    const isOwner = await verifyProductOwnership(userId, parseInt(productId));
    if (!isOwner) {
      return res.status(403).json({
        success: false,
        message: 'You can only view your own products'
      });
    }

    const connection = await pool.getConnection();

    try {
      // Get main product data
      const [products] = await connection.execute(
        "SELECT * FROM products WHERE id = ? AND user_id = ?",
        [productId, userId]
      );

      if (products.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Product not found",
        });
      }

      const product = products[0];

      // Get all possible values for each attribute from master table first
      const [masterAttributes] = await connection.execute(
        `SELECT DISTINCT pam.attributes_name
         FROM product_attributes_master pam 
         WHERE pam.status = 1 
         ORDER BY pam.attributes_name`
      );

      // Build master attributes map with default values
      const masterAttrMap = {};
      for (const master of masterAttributes) {
        const attrName = master.attributes_name;
        if (attrName) {
          // Since attributes_values column doesn't exist, create default values based on attribute name
          masterAttrMap[attrName] = _getDefaultValuesForAttribute(attrName);
        }
      }

      // Helper function to get default values for common attributes
      function _getDefaultValuesForAttribute(attrName) {
        const lowerAttrName = attrName.toLowerCase();
        
        if (lowerAttrName.includes('brand') || lowerAttrName.includes('company')) {
          return ['Nike', 'Adidas', 'Puma', 'Reebok', 'Under Armour', 'New Balance'];
        } else if (lowerAttrName.includes('material') || lowerAttrName.includes('fabric')) {
          return ['Cotton', 'Polyester', 'Wool', 'Silk', 'Linen', 'Nylon', 'Spandex'];
        } else if (lowerAttrName.includes('size') || lowerAttrName.includes('dimension')) {
          return ['XS', 'S', 'M', 'L', 'XL', 'XXL', '3XL', '4XL'];
        } else if (lowerAttrName.includes('color') || lowerAttrName.includes('shade')) {
          return ['Red', 'Blue', 'Green', 'Black', 'White', 'Yellow', 'Pink', 'Purple', 'Orange', 'Brown', 'Gray'];
        } else if (lowerAttrName.includes('style') || lowerAttrName.includes('type')) {
          return ['Casual', 'Formal', 'Sports', 'Traditional', 'Modern', 'Classic'];
        } else if (lowerAttrName.includes('gender')) {
          return ['Men', 'Women', 'Unisex', 'Kids', 'Boys', 'Girls'];
        } else {
          // Default generic values
          return ['Option 1', 'Option 2', 'Option 3', 'Option 4', 'Option 5'];
        }
      }

      // Get attributes from tbl_product_attributes
      const [attributes] = await connection.execute(
        `SELECT pa.attributes_name, pa.attributes_id, pam.attributes_name as master_name
         FROM tbl_product_attributes pa
         LEFT JOIN product_attributes_master pam ON pa.attributes_id = pam.id
         WHERE pa.product_id = ? AND pa.seller_id = ? AND pa.status = 1`,
        [productId, userId]
      );

      // Parse existing JSON fields from product first
      let parsedAttributes = {};
      let parsedSelectedAttributeValues = {};

      try {
        parsedAttributes = product.attributes ? JSON.parse(product.attributes) : {};
      } catch (e) {
        console.log('Error parsing product attributes:', e);
        parsedAttributes = {};
      }

      try {
        parsedSelectedAttributeValues = product.selected_attribute_values ? JSON.parse(product.selected_attribute_values) : {};
      } catch (e) {
        console.log('Error parsing selected attribute values:', e);
        parsedSelectedAttributeValues = {};
      }

      // Build final attributes structure - prioritize master attributes first
      const finalAttributes = { ...masterAttrMap, ...parsedAttributes };
      const finalSelectedAttributeValues = { ...parsedSelectedAttributeValues };

      // If selectedAttributeValues is empty, populate from attributes
      if (Object.keys(finalSelectedAttributeValues).length === 0 && Object.keys(finalAttributes).length > 0) {
        console.log('DEBUG: selectedAttributeValues is empty, populating from attributes');
        for (const [attrName, valueList] of Object.entries(finalAttributes)) {
          if (Array.isArray(valueList) && valueList.length > 0) {
            finalSelectedAttributeValues[attrName] = valueList[0]; // Use first value as default
            console.log(`DEBUG: Set default value for ${attrName}: ${valueList[0]}`);
          }
        }
      }

      // Add database attributes if they don't exist in JSON
      for (const attr of attributes) {
        const attrName = attr.attributes_name || attr.master_name;
        if (attrName && !finalSelectedAttributeValues[attrName]) {
          // Use master values if available, otherwise use current value
          if (masterAttrMap[attrName]) {
            finalAttributes[attrName] = masterAttrMap[attrName];
          } else {
            finalAttributes[attrName] = [attrName];
          }
          finalSelectedAttributeValues[attrName] = attrName;
        }
      }

      // Debug logging
      console.log('DEBUG: Master attributes from DB (with default values):', masterAttrMap);
      console.log('DEBUG: Product attributes from JSON:', parsedAttributes);
      console.log('DEBUG: Final attributes:', finalAttributes);
      console.log('DEBUG: Final selectedAttributeValues:', finalSelectedAttributeValues);

      // Add parsed attributes to product response
      product.attributes = finalAttributes;
      product.selectedAttributeValues = finalSelectedAttributeValues;

      res.json({
        success: true,
        data: product,
      });
    } finally {
      connection.release();
    }
  } catch (error) {
    console.error("Error getting product for edit:", error);
    res.status(500).json({
      success: false,
      message: "Error fetching product",
      error: error.message,
    });
  }
});

// Test endpoint to verify server restart
router.get('/test', (req, res) => {
  res.json({
    success: true,
    message: 'Profile product routes are working!',
    timestamp: new Date().toISOString()
  });
});

module.exports = router;
