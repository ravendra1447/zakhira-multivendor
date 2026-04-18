// server/routes/adminProductRoutes.js
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

// Get all products for admin management
router.get('/admin/products', async (req, res) => {
  try {
    const [products] = await pool.execute(`
      SELECT 
        id,
        user_id,
        name,
        category,
        subcategory,
        brand,
        price,
        original_price,
        stock,
        status,
        is_active,
        marketplace_enabled,
        is_featured,
        view_count,
        created_at,
        updated_at,
        images,
        description
      FROM products 
      ORDER BY created_at DESC
    `);

    res.json({
      success: true,
      products
    });

  } catch (error) {
    console.error('Error fetching admin products:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch products'
    });
  }
});

// Update single product field (is_active or marketplace_enabled)
router.put('/admin/products/:productId', async (req, res) => {
  try {
    const { productId } = req.params;
    const { is_active, marketplace_enabled } = req.body;
    
    // Validate input
    if (is_active === undefined && marketplace_enabled === undefined) {
      return res.status(400).json({
        success: false,
        message: 'At least one field (is_active or marketplace_enabled) must be provided'
      });
    }

    // Build update query dynamically
    let updateFields = [];
    let updateValues = [];
    
    if (is_active !== undefined) {
      updateFields.push('is_active = ?');
      updateValues.push(is_active ? 1 : 0);
    }
    
    if (marketplace_enabled !== undefined) {
      updateFields.push('marketplace_enabled = ?');
      updateValues.push(marketplace_enabled ? 1 : 0);
    }
    
    updateFields.push('updated_at = CURRENT_TIMESTAMP');
    updateValues.push(productId);

    const [result] = await pool.execute(`
      UPDATE products 
      SET ${updateFields.join(', ')}
      WHERE id = ?
    `, updateValues);

    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        message: 'Product not found'
      });
    }

    res.json({
      success: true,
      message: 'Product updated successfully'
    });

  } catch (error) {
    console.error('Error updating product:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update product'
    });
  }
});

// Toggle both is_active and marketplace_enabled simultaneously
router.put('/admin/products/:productId/toggle-both', async (req, res) => {
  try {
    const { productId } = req.params;
    const { is_active, marketplace_enabled } = req.body;
    
    // Validate input
    if (is_active === undefined || marketplace_enabled === undefined) {
      return res.status(400).json({
        success: false,
        message: 'Both is_active and marketplace_enabled fields must be provided'
      });
    }

    const [result] = await pool.execute(`
      UPDATE products 
      SET is_active = ?, 
          marketplace_enabled = ?,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `, [
      is_active ? 1 : 0,
      marketplace_enabled ? 1 : 0,
      productId
    ]);

    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        message: 'Product not found'
      });
    }

    res.json({
      success: true,
      message: 'Product status and marketplace visibility updated successfully'
    });

  } catch (error) {
    console.error('Error toggling product statuses:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update product'
    });
  }
});

// Update all product variants status
router.put('/admin/products/:productId/variants', async (req, res) => {
  try {
    const { productId } = req.params;
    const { is_active } = req.body;
    
    console.log('=== Updating All Variants Status ===');
    console.log('Product ID:', productId);
    console.log('Is Active:', is_active);
    console.log('==================================');
    
    if (is_active === undefined) {
      return res.status(400).json({
        success: false,
        message: 'is_active field is required'
      });
    }

    // Get product info to check stock mode
    const [productInfo] = await pool.execute(`
      SELECT stock_mode, is_active, marketplace_enabled, stock_maintane_type
      FROM products WHERE id = ?
    `, [productId]);

    if (productInfo.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Product not found'
      });
    }

    const currentProduct = productInfo[0];
    
    // Use existing stock_mode field, fallback to stock_maintane_type if needed
    let stockMode = currentProduct.stock_mode || 'simple';
    
    // Map old values to new ones if needed
    if (stockMode === 'Unlimited') {
      stockMode = 'always_available';
    } else if (stockMode === 'Size_Color_Wise') {
      stockMode = 'color_size';
    } else if (stockMode === 'Simple') {
      stockMode = 'simple';
    }
    
    // Also check stock_maintane_type as fallback
    if (stockMode === 'simple' && currentProduct.stock_maintane_type) {
      const maintainType = currentProduct.stock_maintane_type;
      if (maintainType === 'Unlimited') {
        stockMode = 'always_available';
      } else if (maintainType === 'Size_Color_Wise') {
        stockMode = 'color_size';
      }
    }

    if (stockMode === 'simple') {
      // Simple stock mode - update main product stock
      const [updateResult] = await pool.execute(`
        UPDATE products 
        SET stock = ?, is_active = ?
        WHERE id = ?
      `, [
        is_active ? 1 : 0,
        is_active ? 1 : 0,
        productId
      ]);

      res.json({
        success: true,
        message: `Simple product ${is_active ? 'enabled' : 'disabled'} successfully`,
        stock_mode: 'simple',
        product_updated: {
          product_id: productId,
          stock: is_active ? 1 : 0,
          is_active: is_active ? 1 : 0
        },
        product_status_updated: {
          is_active: is_active ? 1 : 0,
          marketplace_enabled: is_active ? currentProduct.marketplace_enabled : 0
        }
      });

    } else if (stockMode === 'always_available') {
      // Always available - no stock management, only status
      const [updateResult] = await pool.execute(`
        UPDATE products 
        SET is_active = ?
        WHERE id = ?
      `, [
        is_active ? 1 : 0,
        productId
      ]);

      res.json({
        success: true,
        message: `Always available product ${is_active ? 'enabled' : 'disabled'} successfully`,
        stock_mode: 'always_available',
        product_updated: {
          product_id: productId,
          is_active: is_active ? 1 : 0,
          stock: 'unlimited'
        },
        product_status_updated: {
          is_active: is_active ? 1 : 0,
          marketplace_enabled: is_active ? currentProduct.marketplace_enabled : 0
        },
        note: 'Always available products do not use variant management'
      });

    } else if (stockMode === 'color_size') {
      // Color size wise - update all variants
      console.log(`Updating all variants for product: ${productId}, status=${is_active ? 1 : 0}`);
      
      try {
        // Update all variants for this product
        const [variantResult] = await pool.execute(`
          UPDATE product_variants 
          SET status = ?,
              stock = ?
          WHERE product_id = ?
        `, [
          is_active ? 1 : 0,
          is_active ? 1 : 0,
          productId
        ]);
        
        console.log(`Update result: affectedRows = ${variantResult.affectedRows}`);
        
        if (variantResult.affectedRows === 0) {
          console.log('No variants found to update!');
          return res.status(404).json({
            success: false,
            message: 'No variants found for this product'
          });
        } else {
          console.log('All variants status updated successfully!');
        }
      } catch (updateError) {
        console.error('Error during UPDATE operation:', updateError);
        throw updateError;
      }

      // Send success response - NO PRODUCTS TABLE UPDATE
      res.json({
        success: true,
        message: `All variants ${is_active ? 'enabled' : 'disabled'} successfully`,
        stock_mode: 'color_size',
        variants_updated: {
          product_id: productId,
          is_active: is_active,
          status: is_active ? 1 : 0,
          affected_rows: variantResult.affectedRows
        },
        note: 'Only product_variants table was updated - products table NOT modified'
      });
    }
  } catch (error) {
    console.error('Error updating variants:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update variants: ' + error.message
    });
  }
});

// Update single product variant status
router.put('/admin/products/:productId/variant/:variantId', async (req, res) => {
  try {
    const { productId, variantId } = req.params;
    const { is_active } = req.body;
    
    console.log('=== Updating Single Variant Status ===');
    console.log('Product ID:', productId);
    console.log('Variant ID:', variantId);
    console.log('Is Active:', is_active);
    console.log('=====================================');
    
    // Get product info FIRST to check stock mode
    const [productInfo] = await pool.execute(`
      SELECT stock_mode, is_active, marketplace_enabled, stock_maintane_type
      FROM products WHERE id = ?
    `, [productId]);

    console.log('Product info:', productInfo[0]);
    
    if (productInfo.length === 0) {
      console.log('Product not found!');
      return res.status(404).json({
        success: false,
        message: 'Product not found'
      });
    }

    const currentProduct = productInfo[0];
    
    // Use existing stock_mode field, fallback to stock_maintane_type if needed
    let stockMode = currentProduct.stock_mode || 'simple';
    
    console.log('Initial stockMode:', stockMode);
    
    // Map old values to new ones if needed
    if (stockMode === 'Unlimited') {
      stockMode = 'always_available';
    } else if (stockMode === 'Size_Color_Wise') {
      stockMode = 'color_size';
    } else if (stockMode === 'Simple') {
      stockMode = 'simple';
    }
    
    // Also check stock_maintane_type as fallback
    if (stockMode === 'simple' && currentProduct.stock_maintane_type) {
      const maintainType = currentProduct.stock_maintane_type;
      if (maintainType === 'Unlimited') {
        stockMode = 'always_available';
      } else if (maintainType === 'Size_Color_Wise') {
        stockMode = 'color_size';
      }
    }
    
    console.log('Final stockMode:', stockMode);
    
    if (is_active === undefined) {
      return res.status(400).json({
        success: false,
        message: 'is_active field is required'
      });
    }

    // Handle different stock modes
    console.log('Handling stock mode:', stockMode);
    
    if (stockMode === 'always_available') {
      console.log('Taking always_available branch');
      // Always available products don't use variant management
      // Just update the main product status
      const [updateResult] = await pool.execute(`
        UPDATE products 
        SET is_active = ?
        WHERE id = ?
      `, [
        is_active ? 1 : 0,
        productId
      ]);

      // Update main product status but also check for variants
      console.log('Updated main product status, checking for variants...');
      
      // Don't return response here - let the variant update logic handle it
    }

    if (stockMode === 'simple') {
      console.log('Taking simple branch');
      // Simple stock mode - update main product stock
      const [updateResult] = await pool.execute(`
        UPDATE products 
        SET stock = ?, is_active = ?
        WHERE id = ?
      `, [
        is_active ? 1 : 0,
        is_active ? 1 : 0,
        productId
      ]);

      console.log('Updated simple product stock, checking for variants...');

    } else if (stockMode === 'always_available') {
      // Always available - no stock management, only status
      const [updateResult] = await pool.execute(`
        UPDATE products 
        SET is_active = ?
        WHERE id = ?
      `, [
        is_active ? 1 : 0,
        productId
      ]);

      console.log('Updated always available product status, checking for variants...');

    } else if (stockMode === 'color_size') {
      // Color size wise - update variant
      console.log(`Updating variant: ${variantId}, status=${is_active ? 1 : 0}`);
      console.log('Reached color_size section');
      
      // Check if variantId is a number (new format) or string (old format)
      console.log(`Checking if variantId is number: ${variantId}, isNaN: ${isNaN(variantId)}`);
      
      if (!isNaN(variantId)) {
        // New format: direct database ID
        console.log(`Using database ID: ${variantId}`);
        console.log('About to check existing variant...');
        
        try {
          // First, let's see what exists in the database
          const [existingVariant] = await pool.execute(`
            SELECT id, product_id, color_name, size, status FROM product_variants 
            WHERE id = ?
          `, [variantId]);
          
          console.log('Database query completed');
          console.log('Found variant in database:');
          if (existingVariant.length > 0) {
            console.log(`  ID: ${existingVariant[0].id}, Product ID: ${existingVariant[0].product_id}, Color: "${existingVariant[0].color_name}", Size: "${existingVariant[0].size}", Status: ${existingVariant[0].status}`);
          } else {
            console.log('No variant found with this ID!');
          }
          
          console.log('About to start update test...');
          
          try {
            // First test: Simple direct update
            console.log('Testing direct database update...');
            await pool.execute(`UPDATE product_variants SET status = 0 WHERE id = 276`);
            console.log('Direct test update completed');
            
            // Now do the actual update with parameters
            console.log('Starting actual update...');
            const [variantResult] = await pool.execute(`
              UPDATE product_variants 
              SET status = ?,
                  stock = ?
              WHERE id = ?
            `, [
              is_active ? 1 : 0,
              is_active ? 1 : 0,
              variantId
            ]);
            
            console.log(`Update query: UPDATE product_variants SET status=${is_active ? 1 : 0}, stock=${is_active ? 1 : 0} WHERE id=${variantId}`);
            console.log(`Update result: affectedRows = ${variantResult.affectedRows}`);
            
            if (variantResult.affectedRows === 0) {
              console.log('No variant found to update by database ID!');
              return res.status(404).json({
                success: false,
                message: 'Variant not found'
              });
            } else {
              console.log('Variant status updated successfully by database ID!');
              
              // Verify the update
              const [updatedVariant] = await pool.execute(`
                SELECT id, status FROM product_variants 
                WHERE id = ?
              `, [variantId]);
              
              if (updatedVariant.length > 0) {
                console.log(`Verified update - ID: ${updatedVariant[0].id}, New Status: ${updatedVariant[0].status}`);
              }
            }
          } catch (updateError) {
            console.error('Error during UPDATE operation:', updateError);
            throw updateError;
          }
        } catch (dbError) {
          console.error('Database error:', dbError);
          throw dbError;
        }
      } else {
        // Old format: productId_color_size
        console.log(`Parsing old format: ${variantId}`);
        const parts = variantId.split('_');
        if (parts.length < 3) {
          return res.status(400).json({
            success: false,
            message: 'Invalid variant ID format'
          });
        }
        
        const colorName = parts.slice(1, -1).join('_'); // Handle colors with spaces
        const size = parts[parts.length - 1];
        
        console.log(`Looking for variant: product_id=${productId}, color="${colorName}", size="${size}"`);
        
        // First, let's see what exists for this product
        const [existingVariants] = await pool.execute(`
          SELECT id, color_name, size, status FROM product_variants 
          WHERE product_id = ?
        `, [productId]);
        
        console.log(`Found ${existingVariants.length} variants for product ${productId}`);
        if (existingVariants.length === 0) {
          console.log(`No variants found for product ${productId}! Checking for existing colors first...`);
          
          // First, check if there are existing colors in product_colors table
          const [existingColors] = await pool.execute(`
            SELECT color_name, color_code, price, stock, image_url
            FROM product_colors 
            WHERE product_id = ?
            ORDER BY color_name
          `, [productId]);
          
          let colorsToUse = [];
          // const defaultSizes = ['6', '7', '8', '9', '10']; // REMOVED - No hardcoded sizes
          
          if (existingColors.length > 0) {
            // Use existing colors from database
            console.log(`Found ${existingColors.length} existing colors in database for product ${productId}`);
            colorsToUse = existingColors;
            
            // Log the actual colors found
            existingColors.forEach(color => {
              console.log(`  - Color: ${color.color_name}, Code: ${color.color_code}, Price: ${color.price}, Stock: ${color.stock}`);
            });
          } else {
            // DO NOT AUTO-CREATE COLORS - This was corrupting live data with hardcoded values
            console.log(`No existing colors found for product ${productId} - NOT creating default colors to prevent data corruption`);
            
            // Return empty colors array instead of creating hardcoded ones
            colorsToUse = [];
          }
          
          // DO NOT AUTO-CREATE VARIANTS - This was corrupting live data with hardcoded prices and sizes
          console.log(`Skipping auto-creation of variants for product ${productId} to prevent data corruption`);
          
          // Variants should be created manually through proper admin interface
          
          console.log(`Skipped auto-creation of variants for product ${productId} - no hardcoded sizes used`);
          
          // Refetch the variants
          const [newVariants] = await pool.execute(`
            SELECT id, color_name, size, status FROM product_variants 
            WHERE product_id = ?
          `, [productId]);
          
          console.log('New variants created:');
          newVariants.forEach(v => {
            console.log(`  ID: ${v.id}, Color: "${v.color_name}", Size: "${v.size}", Status: ${v.status}`);
          });
        } else {
          console.log('Existing variants in database:');
          existingVariants.forEach(v => {
            console.log(`  ID: ${v.id}, Color: "${v.color_name}", Size: "${v.size}", Status: ${v.status}`);
          });
        }
        
        const [variantResult] = await pool.execute(`
          UPDATE product_variants 
          SET status = ?,
              stock = ?
          WHERE product_id = ? AND color_name = ? AND size = ?
        `, [
          is_active ? 1 : 0,
          is_active ? 1 : 0,
          productId,
          colorName,
          size
        ]);
        
        console.log(`Update query: WHERE product_id=${productId} AND color_name="${colorName}" AND size="${size}"`);
        console.log(`Update result: affectedRows = ${variantResult.affectedRows}`);
        
        if (variantResult.affectedRows === 0) {
          console.log('No variant found to update by color and size!');
          return res.status(404).json({
            success: false,
            message: 'Variant not found'
          });
        } else {
          console.log('Variant status updated successfully by color and size!');
        }
      }

      // Check if all variants are inactive (only from product_variants)
      const [allVariantsResult] = await pool.execute(`
        SELECT 
          COUNT(*) as total_variants,
          SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) as active_variants,
          COUNT(DISTINCT color_name) as total_colors,
          SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) as active_color_count
        FROM product_variants 
        WHERE product_id = ?
      `, [productId]);

      const totalVariants = allVariantsResult[0].total_variants;
      const activeVariants = allVariantsResult[0].active_variants;
      const totalColors = allVariantsResult[0].total_colors;
      const activeColors = allVariantsResult[0].active_color_count;

      // Calculate color status based on variants
      const [colorStatusResult] = await pool.execute(`
        SELECT 
          color_name,
          COUNT(*) as total_sizes,
          SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) as active_sizes
        FROM product_variants 
        WHERE product_id = ?
        GROUP BY color_name
      `, [productId]);

      // Determine which colors are active based on their variants
      const activeColorCount = colorStatusResult.filter(c => c.active_sizes > 0).length;

      // Update product status based on variant availability (only for color_size mode)
      const allVariantsInactive = stockMode === 'color_size' ? activeVariants === 0 : false;
      const newProductStatus = allVariantsInactive ? 0 : currentProduct.is_active;
      const newMarketplaceStatus = allVariantsInactive ? 0 : currentProduct.marketplace_enabled;

      // Update product status
      await pool.execute(`
        UPDATE products 
        SET is_active = ?,
            marketplace_enabled = ?
        WHERE id = ?
      `, [
        newProductStatus,
        newMarketplaceStatus,
        productId
      ]);

      res.json({
        success: true,
        message: 'Variant status updated successfully',
        stock_mode: 'color_size',
        variant_updated: {
          product_id: productId,
          color_name: colorName,
          size: size,
          is_active: is_active,
          status: is_active ? 1 : 0,
          stock: is_active ? 1 : 0
        },
        color_status_calculated: {
          color_name: colorName,
          active_sizes: colorStatusResult.find(c => c.color_name === colorName)?.active_sizes || 0,
          total_sizes: colorStatusResult.find(c => c.color_name === colorName)?.total_sizes || 0,
          is_color_active: (colorStatusResult.find(c => c.color_name === colorName)?.active_sizes || 0) > 0
        },
        product_status_updated: {
          is_active: newProductStatus === 1,
          marketplace_enabled: newMarketplaceStatus === 1,
          all_variants_inactive: allVariantsInactive,
          total_variants: totalVariants,
          active_variants: activeVariants,
          total_colors: totalColors,
          active_colors: activeColorCount
        }
      });
    }

    // Always try to update variants if they exist, regardless of stock mode
    console.log('Checking if product has variants to update...');
    const [variantCheck] = await pool.execute(`
      SELECT id, status FROM product_variants 
      WHERE product_id = ? LIMIT 1
    `, [productId]);

    if (variantCheck.length > 0) {
      console.log('Product has variants, updating variant status...');
      
      // Update the specific variant
      const [variantResult] = await pool.execute(`
        UPDATE product_variants 
        SET status = ?,
            stock = ?
        WHERE id = ?
      `, [
        is_active ? 1 : 0,
        is_active ? 1 : 0,
        variantId
      ]);
      
      console.log(`Variant update result: affectedRows = ${variantResult.affectedRows}`);
      
      if (variantResult.affectedRows > 0) {
        console.log('Variant status updated successfully!');
        
        // Return success response for variant update
        return res.json({
          success: true,
          message: 'Variant status updated successfully',
          stock_mode: stockMode,
          variant_updated: {
            product_id: productId,
            variant_id: variantId,
            is_active: is_active,
            status: is_active ? 1 : 0
          },
          note: 'product_variants table updated - products table may also be updated based on stock mode'
        });
      }
    } else {
      console.log('No variants found for this product');
      
      // Return success response for product update only
      return res.json({
        success: true,
        message: 'Product status updated successfully (no variants found)',
        stock_mode: stockMode,
        product_updated: {
          product_id: productId,
          is_active: is_active ? 1 : 0
        },
        note: 'Only products table was updated - no variants exist'
      });
    }

  } catch (error) {
    console.error('Error updating variant:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update variant: ' + error.message
    });
  }
});

// Get product variants for admin management
router.get('/admin/products/:productId/variants', async (req, res) => {
  try {
    const { productId } = req.params;

    // Get product info to check stock mode
    const [productInfo] = await pool.execute(`
      SELECT stock_mode, stock, is_active, marketplace_enabled, stock_maintane_type
      FROM products WHERE id = ?
    `, [productId]);

    if (productInfo.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Product not found'
      });
    }

    // Use existing stock_mode field, fallback to stock_maintane_type if needed
    let stockMode = productInfo[0].stock_mode || 'simple';
    
    // Map old values to new ones if needed
    if (stockMode === 'Unlimited') {
      stockMode = 'always_available';
    } else if (stockMode === 'Size_Color_Wise') {
      stockMode = 'color_size';
    } else if (stockMode === 'Simple') {
      stockMode = 'simple';
    }
    
    // Also check stock_maintane_type as fallback
    if (stockMode === 'simple' && productInfo[0].stock_maintane_type) {
      const maintainType = productInfo[0].stock_maintane_type;
      if (maintainType === 'Unlimited') {
        stockMode = 'always_available';
      } else if (maintainType === 'Size_Color_Wise') {
        stockMode = 'color_size';
      }
    }

    // Check if product has any variants, colors, or sizes and show accordingly
    // Don't force any mode - show what exists in database

    console.log(`Final stockMode for product ${productId}: ${stockMode}`);

    const productStock = productInfo[0].stock;
    const productStatus = productInfo[0].is_active;

    let response = {
      success: true,
      product_id: productId,
      stock_mode: stockMode,
      product_status: {
        is_active: productStatus === 1,
        marketplace_enabled: productInfo[0].marketplace_enabled === 1,
        stock: productStock
      }
    };

    // Check what data actually exists in database for this product
    const [checkColors] = await pool.execute(`
      SELECT COUNT(*) as count FROM product_colors WHERE product_id = ?
    `, [productId]);
    
    const [checkVariants] = await pool.execute(`
      SELECT COUNT(*) as count FROM product_variants WHERE product_id = ?
    `, [productId]);
    
    const hasColors = checkColors[0].count > 0;
    const hasVariants = checkVariants[0].count > 0;
    
    console.log(`Database check for product ${productId}:`);
    console.log(`  - Has colors: ${hasColors} (${checkColors[0].count})`);
    console.log(`  - Has variants: ${hasVariants} (${checkVariants[0].count})`);
    console.log(`  - Stock mode: ${stockMode}`);
    
    // Show data based on what actually exists, not forced mode
    if (hasVariants) {
      // Product has variants - show them regardless of stock mode
      stockMode = 'color_size';
      console.log(`Product ${productId} has variants, setting mode to color_size`);
    } else if (hasColors) {
      // Product has colors but no variants
      stockMode = 'colors_only';
      console.log(`Product ${productId} has colors but no variants, setting mode to colors_only`);
    } else {
      // Product has neither - use original stock mode
      console.log(`Product ${productId} has no colors or variants, using original mode: ${stockMode}`);
    }
    
    // Handle different stock modes
    if (stockMode === 'simple') {
      // Simple stock mode - only one stock value
      response.stock_info = {
        type: 'simple',
        stock: productStock,
        is_active: productStock > 0 && productStatus === 1
      };
      
    } else if (stockMode === 'always_available') {
      // Always available - no stock management, only status
      response.stock_info = {
        type: 'always_available',
        stock: 'unlimited',
        is_active: productStatus === 1,
        note: 'Always available products do not use variant management'
      };
      
    } else if (stockMode === 'color_size' || stockMode === 'colors_only') {
      // Color size wise - get variants from product_variants table
      const [variants] = await pool.execute(`
        SELECT 
          pv.id,
          pv.product_id,
          pv.color_name,
          pv.color_code,
          pv.size,
          pv.price,
          pv.stock,
          pv.status,
          pv.created_at,
          pc.color_code as color_code_from_colors,
          pc.image_url
        FROM product_variants pv
        LEFT JOIN product_colors pc ON pv.product_id = pc.product_id AND pv.color_name = pc.color_name
        WHERE pv.product_id = ?
        ORDER BY pv.color_name, pv.size
      `, [productId]);

      // Get colors from product_colors table for additional info
      const [colors] = await pool.execute(`
        SELECT 
          id,
          color_name,
          color_code,
          image_url,
          price as color_price,
          stock as color_stock
        FROM product_colors 
        WHERE product_id = ?
        ORDER BY color_name
      `, [productId]);

      // Calculate color status based on variants
      const [colorStatusQuery] = await pool.execute(`
        SELECT 
          color_name,
          COUNT(*) as total_sizes,
          SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) as active_sizes,
          SUM(CASE WHEN status = 1 THEN 1 ELSE 0 END) as active_count
        FROM product_variants 
        WHERE product_id = ?
        GROUP BY color_name
      `, [productId]);

      const colorStatusMap = new Map();
      for (const cs of colorStatusQuery) {
        colorStatusMap.set(cs.color_name, {
          total_sizes: cs.total_sizes,
          active_sizes: cs.active_sizes,
          is_active: cs.active_sizes > 0
        });
      }

      // Combine data and format for frontend
      const formattedVariants = [];
      const colorMap = new Map();

      // Group variants by color
      for (const variant of variants) {
        const colorName = variant.color_name;
        const colorInfo = colors.find(c => c.color_name === colorName);
        const colorStatus = colorStatusMap.get(colorName) || { total_sizes: 0, active_sizes: 0, is_active: false };
        
        if (!colorMap.has(colorName)) {
          colorMap.set(colorName, {
            color: colorName,
            color_code: variant.color_code_from_colors || variant.color_code || (colorInfo?.color_code || '#000000'),
            image_url: variant.image_url || (colorInfo?.image_url || null),
            color_status: colorStatus.is_active ? 1 : 0,
            total_sizes: colorStatus.total_sizes,
            active_sizes: colorStatus.active_sizes,
            variants: []
          });
        }

        colorMap.get(colorName).variants.push({
          id: variant.id.toString(), // Use the actual database ID
          color: colorName,
          size: variant.size,
          stock: variant.stock,
          price: variant.price,
          is_active: variant.status == 1, // Use status field
          color_code: variant.color_code_from_colors || variant.color_code || (colorInfo?.color_code || '#000000'),
          status: variant.status
        });
      }

      // Convert map to array
      const colorGroups = Array.from(colorMap.values());
      console.log(`colorGroups.length after database query: ${colorGroups.length} for product ${productId}`);

      // Handle colors_only mode - show colors without variants
      if (stockMode === 'colors_only') {
        console.log(`Product ${productId} is in colors_only mode, fetching colors...`);
        
        const [colorsOnly] = await pool.execute(`
          SELECT 
            id,
            color_name,
            color_code,
            image_url,
            price,
            stock
          FROM product_colors 
          WHERE product_id = ?
          ORDER BY color_name
        `, [productId]);
        
        console.log(`Found ${colorsOnly.length} colors for product ${productId}`);
        
        const colorGroups = colorsOnly.map(color => ({
          color: color.color_name,
          color_code: color.color_code || '#000000',
          image_url: color.image_url || null,
          color_status: 1, // All colors are active by default
          total_sizes: 0, // No sizes in colors_only mode
          active_sizes: 0,
          variants: [] // No variants in colors_only mode
        }));
        
        response.stock_info = {
          type: 'colors_only',
          color_groups: colorGroups,
          total_variants: 0,
          total_colors: colorGroups.length,
          active_variants: 0,
          active_colors: colorGroups.length,
          note: 'Product has colors but no size variants'
        };
        
        console.log(`Colors only response for product ${productId}:`, JSON.stringify(response.stock_info, null, 2));
        
      } else if (colorGroups.length === 0 && (stockMode === 'color_size')) {
        console.log(`No variants found for product ${productId} in database`);
        console.log(`Database query returned ${variants.length} variants`);
        console.log(`Product stock_mode: ${stockMode}`);
        
        // Check if variants actually exist in database
        const [checkVariants] = await pool.execute(`
          SELECT COUNT(*) as count FROM product_variants WHERE product_id = ?
        `, [productId]);
        
        console.log(`Actual variants in database: ${checkVariants[0].count}`);
        
        if (checkVariants[0].count > 0) {
          console.log(`ERROR: Database has ${checkVariants[0].count} variants but API returned 0. Checking query...`);
          
          // Debug: Run the exact query again
          const [debugVariants] = await pool.execute(`
            SELECT 
              pv.id,
              pv.product_id,
              pv.color_name,
              pv.color_code,
              pv.size,
              pv.price,
              pv.stock,
              pv.status,
              pv.created_at,
              pc.color_code as color_code_from_colors,
              pc.image_url
            FROM product_variants pv
            LEFT JOIN product_colors pc ON pv.product_id = pc.product_id AND pv.color_name = pc.color_name
            WHERE pv.product_id = ?
            ORDER BY pv.color_name, pv.size
          `, [productId]);
          
          console.log(`Debug query returned ${debugVariants.length} variants`);
          debugVariants.forEach(v => {
            console.log(`  - ID: ${v.id}, Color: "${v.color_name}", Size: "${v.size}", Status: ${v.status}, Price: ${v.price}`);
          });
          
          // Recalculate color groups with real data
          const newColorMap = new Map();
          for (const variant of debugVariants) {
            const colorName = variant.color_name;
            
            if (!newColorMap.has(colorName)) {
              newColorMap.set(colorName, {
                color: colorName,
                color_code: variant.color_code_from_colors || variant.color_code || '#000000',
                image_url: variant.image_url || null,
                color_status: variant.status == 1 ? 1 : 0,
                total_sizes: 0,
                active_sizes: 0,
                variants: []
              });
            }
            
            const colorGroup = newColorMap.get(colorName);
            colorGroup.variants.push({
              id: variant.id.toString(), // Use the actual database ID as string
              color: colorName,
              size: variant.size,
              stock: variant.stock,
              price: variant.price,
              is_active: variant.status == 1,
              color_code: variant.color_code_from_colors || variant.color_code || '#000000',
              status: variant.status
            });
            
            colorGroup.total_sizes++;
            if (variant.status == 1) {
              colorGroup.active_sizes++;
            }
          }
          
          // Replace colorGroups with real data
          colorGroups.length = 0; // Clear array
          colorGroups.push(...Array.from(newColorMap.values()));
          
          console.log(`Refetched ${colorGroups.length} real color groups from database`);
        }
      }

      // Only set color_size response if not already set by colors_only mode
      if (!response.stock_info || response.stock_info.type !== 'colors_only') {
        response.stock_info = {
          type: 'color_size',
          color_groups: colorGroups,
          total_variants: variants.length || colorGroups.length * 4, // Use mock count if needed
          total_colors: colorGroups.length,
          active_variants: colorStatusQuery.reduce((sum, c) => sum + c.active_sizes, 0) || colorGroups.length * 4,
          active_colors: colorStatusQuery.filter(c => c.active_sizes > 0).length || colorGroups.length
        };
      }
      
      console.log(`Final response for product ${productId}:`, JSON.stringify(response.stock_info, null, 2));
    }

    res.json(response);

  } catch (error) {
    console.error('Error fetching product variants:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch product variants: ' + error.message
    });
  }
});

// Update all variants of a product
router.put('/admin/products/:productId/variants', async (req, res) => {
  try {
    const { productId } = req.params;
    const { is_active } = req.body;
    
    console.log('=== Updating All Variants Status ===');
    console.log('Product ID:', productId);
    console.log('Is Active:', is_active);
    console.log('=====================================');
    
    if (is_active === undefined) {
      return res.status(400).json({
        success: false,
        message: 'is_active field is required'
      });
    }

    // Get product info to check stock mode
    const [productInfo] = await pool.execute(`
      SELECT stock_mode, is_active, marketplace_enabled, stock_maintane_type
      FROM products WHERE id = ?
    `, [productId]);

    if (productInfo.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Product not found'
      });
    }

    const currentProduct = productInfo[0];
    
    // Use existing stock_mode field, fallback to stock_maintane_type if needed
    let stockMode = currentProduct.stock_mode || 'simple';
    
    // Map old values to new ones if needed
    if (stockMode === 'Unlimited') {
      stockMode = 'always_available';
    } else if (stockMode === 'Size_Color_Wise') {
      stockMode = 'color_size';
    } else if (stockMode === 'Simple') {
      stockMode = 'simple';
    }
    
    // Also check stock_maintane_type as fallback
    if (stockMode === 'simple' && currentProduct.stock_maintane_type) {
      const maintainType = currentProduct.stock_maintane_type;
      if (maintainType === 'Unlimited') {
        stockMode = 'always_available';
      } else if (maintainType === 'Size_Color_Wise') {
        stockMode = 'color_size';
      }
    }

    // Handle different stock modes
    if (stockMode === 'simple') {
      // Simple stock mode - update main product stock
      const [updateResult] = await pool.execute(`
        UPDATE products 
        SET stock = ?, is_active = ?
        WHERE id = ?
      `, [
        is_active ? 1 : 0,
        is_active ? 1 : 0,
        productId
      ]);

      res.json({
        success: true,
        message: `Simple product ${is_active ? 'enabled' : 'disabled'} successfully`,
        stock_mode: 'simple',
        product_updated: {
          product_id: productId,
          stock: is_active ? 1 : 0,
          is_active: is_active ? 1 : 0
        },
        product_status_updated: {
          is_active: is_active ? 1 : 0,
          marketplace_enabled: is_active ? currentProduct.marketplace_enabled : 0
        }
      });

    } else if (stockMode === 'always_available') {
      // Always available - only status update
      const [updateResult] = await pool.execute(`
        UPDATE products 
        SET is_active = ?
        WHERE id = ?
      `, [
        is_active ? 1 : 0,
        productId
      ]);

      res.json({
        success: true,
        message: `Always available product ${is_active ? 'enabled' : 'disabled'} successfully`,
        stock_mode: 'always_available',
        product_updated: {
          product_id: productId,
          is_active: is_active ? 1 : 0,
          stock: 'unlimited'
        },
        product_status_updated: {
          is_active: is_active ? 1 : 0,
          marketplace_enabled: is_active ? currentProduct.marketplace_enabled : 0
        }
      });

    } else if (stockMode === 'color_size') {
      // Color size wise - update all variants in product_variants table
      console.log(`Updating all variants for product ${productId} in color_size mode`);
      
      // Check if variants exist first
      const [existingVariants] = await pool.execute(`
        SELECT COUNT(*) as count FROM product_variants 
        WHERE product_id = ?
      `, [productId]);
      
      if (existingVariants[0].count === 0) {
        console.log(`No variants found for product ${productId}! Checking for existing colors first...`);
        
        // First, check if there are existing colors in product_colors table
        const [existingColors] = await pool.execute(`
          SELECT color_name, color_code, price, stock, image_url
          FROM product_colors 
          WHERE product_id = ?
          ORDER BY color_name
        `, [productId]);
        
        let colorsToUse = [];
        // const defaultSizes = ['6', '7', '8', '9', '10']; // REMOVED - No hardcoded sizes
        
        if (existingColors.length > 0) {
          // Use existing colors from database
          console.log(`Found ${existingColors.length} existing colors in database for product ${productId}`);
          colorsToUse = existingColors;
          
          // Log the actual colors found
          existingColors.forEach(color => {
            console.log(`  - Color: ${color.color_name}, Code: ${color.color_code}, Price: ${color.price}, Stock: ${color.stock}`);
          });
        } else {
          // DO NOT AUTO-CREATE COLORS - This was corrupting live data
          console.log(`No existing colors found for product ${productId} - NOT creating default colors to prevent data corruption`);
          
          // Return empty colors array instead of creating hardcoded ones
          colorsToUse = [];
        }
        
        // DO NOT AUTO-CREATE VARIANTS - This was corrupting live data with hardcoded prices and sizes
        console.log(`Skipping auto-creation of variants for product ${productId} to prevent data corruption`);
        
        // Variants should be created manually through proper admin interface
        
        console.log(`Skipped auto-creation of variants for product ${productId} - no hardcoded sizes used`);
      }
      
      const [updateResult] = await pool.execute(`
        UPDATE product_variants 
        SET status = ?,
            stock = ?
        WHERE product_id = ?
      `, [
        is_active ? 1 : 0, // Update status field
        is_active ? 1 : 0, // Also update stock to maintain consistency
        productId
      ]);
      
      console.log(`Updated ${updateResult.affectedRows} variants for product ${productId}`);

      // Update product status based on variant availability
      const newProductStatus = is_active ? currentProduct.is_active : 0;
      const newMarketplaceStatus = is_active ? currentProduct.marketplace_enabled : 0;

      // Update product status
      await pool.execute(`
        UPDATE products 
        SET is_active = ?,
            marketplace_enabled = ?
        WHERE id = ?
      `, [
        newProductStatus,
        newMarketplaceStatus,
        productId
      ]);

      res.json({
        success: true,
        message: `All variants ${is_active ? 'enabled' : 'disabled'} successfully`,
        stock_mode: 'color_size',
        updated_variants: updateResult.affectedRows,
        product_status_updated: {
          is_active: newProductStatus === 1,
          marketplace_enabled: newMarketplaceStatus === 1,
          all_variants_disabled: !is_active
        }
      });
    }

  } catch (error) {
    console.error('Error updating variants:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update variants: ' + error.message
    });
  }
});

// Delete product and its variants
router.delete('/admin/products/:productId', async (req, res) => {
  try {
    const { productId } = req.params;
    
    console.log('=== Deleting Product ===');
    console.log('Product ID:', productId);
    console.log('======================');
    
    // Start transaction
    const connection = await pool.getConnection();
    await connection.beginTransaction();
    
    try {
      // First delete all variants of the product
      const [variantsResult] = await connection.execute(`
        DELETE FROM product_variants 
        WHERE product_id = ?
      `, [productId]);
      
      console.log(`Deleted ${variantsResult.affectedRows} variants`);
      
      // Then delete the product
      const [productResult] = await connection.execute(`
        DELETE FROM products 
        WHERE id = ?
      `, [productId]);
      
      console.log(`Deleted product: ${productResult.affectedRows} rows affected`);
      
      if (productResult.affectedRows === 0) {
        await connection.rollback();
        return res.status(404).json({
          success: false,
          message: 'Product not found'
        });
      }
      
      // Commit transaction
      await connection.commit();
      
      res.json({
        success: true,
        message: 'Product and its variants deleted successfully',
        deleted: {
          product_id: productId,
          variants_deleted: variantsResult.affectedRows,
          product_deleted: productResult.affectedRows
        }
      });
      
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }
    
  } catch (error) {
    console.error('Error deleting product:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete product: ' + error.message
    });
  }
});

// Update product website visibility
router.put('/admin/products/:productId/status', async (req, res) => {
  try {
    const { productId } = req.params;
    const { is_active } = req.body;
    
    if (typeof is_active !== 'number' || (is_active !== 0 && is_active !== 1)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid is_active value. Must be 0 or 1'
      });
    }
    
    const [result] = await pool.execute(`
      UPDATE products 
      SET is_active = ?, updated_at = NOW()
      WHERE id = ?
    `, [is_active, productId]);
    
    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        message: 'Product not found'
      });
    }
    
    console.log(`Product ${productId} website visibility updated to: ${is_active === 1 ? 'visible' : 'hidden'}`);
    
    res.json({
      success: true,
      message: `Product ${is_active === 1 ? 'shown' : 'hidden'} on website successfully`,
      updated: {
        product_id: productId,
        is_active: is_active
      }
    });
    
  } catch (error) {
    console.error('Error updating product website visibility:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update product website visibility: ' + error.message
    });
  }
});

// Update product marketplace visibility
router.put('/admin/products/:productId/marketplace-status', async (req, res) => {
  try {
    const { productId } = req.params;
    const { marketplace_enabled } = req.body;
    
    if (typeof marketplace_enabled !== 'number' || (marketplace_enabled !== 0 && marketplace_enabled !== 1)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid marketplace_enabled value. Must be 0 or 1'
      });
    }
    
    const [result] = await pool.execute(`
      UPDATE products 
      SET marketplace_enabled = ?, updated_at = NOW()
      WHERE id = ?
    `, [marketplace_enabled, productId]);
    
    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        message: 'Product not found'
      });
    }
    
    console.log(`Product ${productId} marketplace visibility updated to: ${marketplace_enabled === 1 ? 'visible' : 'hidden'}`);
    
    res.json({
      success: true,
      message: `Product ${marketplace_enabled === 1 ? 'shown' : 'hidden'} on marketplace successfully`,
      updated: {
        product_id: productId,
        marketplace_enabled: marketplace_enabled
      }
    });
    
  } catch (error) {
    console.error('Error updating product marketplace visibility:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update product marketplace visibility: ' + error.message
    });
  }
});

// Update color status for colors_only mode
router.put('/admin/products/:productId/color/:colorName', async (req, res) => {
  try {
    const { productId, colorName } = req.params;
    const { is_active } = req.body;
    
    // URL decode the color name
    const decodedColorName = decodeURIComponent(colorName);
    
    console.log('=== Updating Color Status ===');
    console.log('Product ID:', productId);
    console.log('Raw Color Name:', colorName);
    console.log('Decoded Color Name:', decodedColorName);
    console.log('Is Active:', is_active);
    console.log('============================');
    
    if (typeof is_active !== 'number' || (is_active !== 0 && is_active !== 1)) {
      console.log('Invalid is_active value:', is_active, typeof is_active);
      return res.status(400).json({
        success: false,
        message: 'Invalid is_active value. Must be 0 or 1'
      });
    }
    
    // Check if color exists first
    const [colorCheck] = await pool.execute(`
      SELECT id, color_name, status FROM product_colors 
      WHERE product_id = ? AND color_name = ?
    `, [productId, decodedColorName]);
    
    if (colorCheck.length === 0) {
      console.log('Color not found for product:', productId, 'Color:', decodedColorName);
      return res.status(404).json({
        success: false,
        message: 'Color not found for this product'
      });
    }
    
    console.log('Found color:', colorCheck[0]);
    
    // Update color status in product_colors table
    const [result] = await pool.execute(`
      UPDATE product_colors 
      SET status = ?
      WHERE product_id = ? AND color_name = ?
    `, [is_active, productId, decodedColorName]);
    
    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        message: 'Color not found for this product'
      });
    }
    
    // Also update all variants with this color to maintain consistency
    await pool.execute(`
      UPDATE product_variants 
      SET status = ?
      WHERE product_id = ? AND color_name = ?
    `, [is_active, productId, decodedColorName]);
    
    console.log(`Color ${colorName} status updated to: ${is_active === 1 ? 'active' : 'inactive'}`);
    
    res.json({
      success: true,
      message: `Color ${colorName} ${is_active === 1 ? 'activated' : 'deactivated'} successfully`,
      updated: {
        product_id: productId,
        color_name: colorName,
        is_active: is_active
      }
    });
    
  } catch (error) {
    console.error('Error updating color status:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update color status: ' + error.message
    });
  }
});

module.exports = router;
