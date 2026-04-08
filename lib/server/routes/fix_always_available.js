const fs = require('fs');
const path = require('path');

// Read the current file
const filePath = path.join(__dirname, 'adminProductRoutes.js');
const content = fs.readFileSync(filePath, 'utf8');

// Find the specific location in single variant endpoint (around line 210)
const targetSection = `// Also check stock_maintane_type as fallback
    if (stockMode === 'simple' && currentProduct.stock_maintane_type) {
      const maintainType = currentProduct.stock_maintane_type;
      if (maintainType === 'Unlimited') {
        stockMode = 'always_available';
      } else if (maintainType === 'Size_Color_Wise') {
        stockMode = 'color_size';
      }
    }

    // Handle different stock modes
    if (stockMode === 'simple') {`;

const replacementSection = `// Also check stock_maintane_type as fallback
    if (stockMode === 'simple' && currentProduct.stock_maintane_type) {
      const maintainType = currentProduct.stock_maintane_type;
      if (maintainType === 'Unlimited') {
        stockMode = 'always_available';
      } else if (maintainType === 'Size_Color_Wise') {
        stockMode = 'color_size';
      }
    }

    // Handle different stock modes
    if (stockMode === 'always_available') {
      // Always available products don't use variant management
      // Just update the main product status
      const [updateResult] = await pool.execute(\`
        UPDATE products 
        SET is_active = ?
        WHERE id = ?
      \`, [
        is_active ? 1 : 0,
        productId
      ]);

      return res.json({
        success: true,
        message: 'Always available product status updated successfully',
        stock_mode: 'always_available',
        product_updated: {
          product_id: productId,
          is_active: is_active ? 1 : 0,
          stock: 'unlimited'
        },
        product_status_updated: {
          is_active: is_active ? 1 : 0,
          marketplace_enabled: is_active ? (currentProduct.marketplace_enabled || 0) : 0
        },
        note: 'Always available products do not use variant management'
      });
    }

    if (stockMode === 'simple') {`;

// Replace the section
const updatedContent = content.replace(targetSection, replacementSection);

// Write back to file
fs.writeFileSync(filePath, updatedContent);

console.log('✅ Fixed always_available mode in adminProductRoutes.js');
