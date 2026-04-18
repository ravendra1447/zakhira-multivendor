// server/routes/marketplace/productRoutes.js
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

// Get all products for marketplace (only active products and variants)
router.get('/marketplace/products', async (req, res) => {
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
      WHERE is_active = 1 
        AND marketplace_enabled = 1
      ORDER BY created_at DESC
    `);

    // Filter products to only include those with active variants
    const filteredProducts = [];
    
    for (const product of products) {
      const [variants] = await pool.execute(`
        SELECT 
          pv.id,
          pv.product_id,
          pv.color_name,
          pv.color_code,
          pv.size,
          pv.price,
          pv.stock,
          pv.status
        FROM product_variants pv
        WHERE pv.product_id = ? 
          AND pv.status = 1
          AND pv.stock > 0
        ORDER BY pv.color_name, pv.size
      `, [product.id]);

      // Only include products that have active variants
      if (variants.length > 0) {
        // Group variants by color and only include colors with active variants
        const colorGroups = {};
        for (const variant of variants) {
          if (!colorGroups[variant.color_name]) {
            colorGroups[variant.color_name] = {
              color: variant.color_name,
              color_code: variant.color_code,
              variants: []
            };
          }
          colorGroups[variant.color_name].variants.push({
            id: variant.id,
            size: variant.size,
            stock: variant.stock,
            price: variant.price,
            status: variant.status
          });
        }

        // Only include colors that have active variants
        const activeColors = Object.values(colorGroups).filter(color => 
          color.variants.some(v => v.status === 1 && v.stock > 0)
        );

        if (activeColors.length > 0) {
          filteredProducts.push({
            ...product,
            variants: variants,
            color_groups: activeColors,
            available_colors: activeColors.length,
            total_variants: variants.length
          });
        }
      }
    }

    res.json({
      success: true,
      products: filteredProducts,
      total_products: filteredProducts.length
    });

  } catch (error) {
    console.error('Error fetching marketplace products:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch marketplace products'
    });
  }
});

// Get single product details for marketplace (only active variants)
router.get('/marketplace/products/:productId', async (req, res) => {
  try {
    const { productId } = req.params;

    // Get product info (only if active and marketplace enabled)
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
        description,
        stock_mode,
        stock_maintane_type
      FROM products 
      WHERE id = ? 
        AND is_active = 1 
        AND marketplace_enabled = 1
    `, [productId]);

    if (products.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Product not found or not available on marketplace'
      });
    }

    const product = products[0];

    // Get product info to check stock mode
    let stockMode = product.stock_mode || 'simple';
    
    // Map old values to new ones if needed
    if (stockMode === 'Unlimited') {
      stockMode = 'always_available';
    } else if (stockMode === 'Size_Color_Wise') {
      stockMode = 'color_size';
    } else if (stockMode === 'Simple') {
      stockMode = 'simple';
    }
    
    // Also check stock_maintane_type as fallback
    if (stockMode === 'simple' && product.stock_maintane_type) {
      const maintainType = product.stock_maintane_type;
      if (maintainType === 'Unlimited') {
        stockMode = 'always_available';
      } else if (maintainType === 'Size_Color_Wise') {
        stockMode = 'color_size';
      }
    }

    let stockInfo = {};

    if (stockMode === 'simple') {
      // Simple stock mode
      stockInfo = {
        type: 'simple',
        stock: product.stock,
        is_active: product.stock > 0 && product.is_active === 1
      };
      
    } else if (stockMode === 'always_available') {
      // Always available - but still filter variants by status
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
          AND pv.status = 1
        ORDER BY pv.color_name, pv.size
      `, [productId]);

      // Get colors from product_colors table
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

      // Group variants by color (only active colors)
      const colorMap = new Map();
      for (const variant of variants) {
        const colorName = variant.color_name;
        const colorInfo = colors.find(c => c.color_name === colorName);
        
        if (!colorMap.has(colorName)) {
          colorMap.set(colorName, {
            color: colorName,
            color_code: variant.color_code_from_colors || variant.color_code || (colorInfo?.color_code || '#000000'),
            image_url: variant.image_url || (colorInfo?.image_url || null),
            variants: []
          });
        }

        colorMap.get(colorName).variants.push({
          id: variant.id.toString(),
          color: colorName,
          size: variant.size,
          stock: variant.stock || 'unlimited',
          price: variant.price,
          is_active: variant.status == 1,
          color_code: variant.color_code_from_colors || variant.color_code || (colorInfo?.color_code || '#000000'),
          status: variant.status
        });
      }

      // Convert map to array - this will only include colors with active variants
      const colorGroups = Array.from(colorMap.values());

      stockInfo = {
        type: 'always_available',
        stock: 'unlimited',
        is_active: product.is_active === 1,
        color_groups: colorGroups,
        total_variants: variants.length,
        total_colors: colorGroups.length,
        active_variants: variants.length,
        active_colors: colorGroups.length
      };
      
    } else if (stockMode === 'color_size') {
      // Color size wise - get only ACTIVE variants
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
          AND pv.status = 1
          AND pv.stock > 0
        ORDER BY pv.color_name, pv.size
      `, [productId]);

      // Get colors from product_colors table (only active ones)
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

      // Group variants by color (only active colors)
      const colorMap = new Map();
      for (const variant of variants) {
        const colorName = variant.color_name;
        const colorInfo = colors.find(c => c.color_name === colorName);
        
        if (!colorMap.has(colorName)) {
          colorMap.set(colorName, {
            color: colorName,
            color_code: variant.color_code_from_colors || variant.color_code || (colorInfo?.color_code || '#000000'),
            image_url: variant.image_url || (colorInfo?.image_url || null),
            variants: []
          });
        }

        colorMap.get(colorName).variants.push({
          id: variant.id.toString(),
          color: colorName,
          size: variant.size,
          stock: variant.stock,
          price: variant.price,
          is_active: variant.status == 1,
          color_code: variant.color_code_from_colors || variant.color_code || (colorInfo?.color_code || '#000000'),
          status: variant.status
        });
      }

      // Convert map to array - this will only include colors with active variants
      const colorGroups = Array.from(colorMap.values());

      stockInfo = {
        type: 'color_size',
        color_groups: colorGroups,
        total_variants: variants.length,
        total_colors: colorGroups.length,
        active_variants: variants.length,
        active_colors: colorGroups.length
      };
    }

    res.json({
      success: true,
      product: {
        ...product,
        stock_info: stockInfo
      }
    });

  } catch (error) {
    console.error('Error fetching marketplace product details:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch product details'
    });
  }
});

// Get available colors for a product (only active colors)
router.get('/marketplace/products/:productId/colors', async (req, res) => {
  try {
    const { productId } = req.params;

    // Get only colors that have active variants
    const [colors] = await pool.execute(`
      SELECT DISTINCT
        pv.color_name,
        pv.color_code,
        pc.image_url,
        COUNT(pv.id) as variant_count,
        SUM(CASE WHEN pv.status = 1 AND pv.stock > 0 THEN 1 ELSE 0 END) as active_variant_count
      FROM product_variants pv
      LEFT JOIN product_colors pc ON pv.product_id = pc.product_id AND pv.color_name = pc.color_name
      WHERE pv.product_id = ?
        AND pv.status = 1
      GROUP BY pv.color_name, pv.color_code, pc.image_url
      HAVING active_variant_count > 0
      ORDER BY pv.color_name
    `, [productId]);

    res.json({
      success: true,
      colors: colors.map(color => ({
        color: color.color_name,
        color_code: color.color_code,
        image_url: color.image_url,
        variant_count: color.variant_count,
        active_variant_count: color.active_variant_count
      }))
    });

  } catch (error) {
    console.error('Error fetching product colors:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch product colors'
    });
  }
});

// Get available sizes for a product color (only active sizes)
router.get('/marketplace/products/:productId/colors/:colorName/sizes', async (req, res) => {
  try {
    const { productId, colorName } = req.params;

    // Get only active sizes for a specific color
    const [sizes] = await pool.execute(`
      SELECT 
        pv.size,
        pv.price,
        pv.stock,
        pv.status
      FROM product_variants pv
      WHERE pv.product_id = ?
        AND pv.color_name = ?
        AND pv.status = 1
        AND pv.stock > 0
      ORDER BY pv.size
    `, [productId, colorName]);

    res.json({
      success: true,
      color: colorName,
      sizes: sizes.map(size => ({
        size: size.size,
        price: size.price,
        stock: size.stock,
        is_active: size.status === 1
      }))
    });

  } catch (error) {
    console.error('Error fetching product sizes:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch product sizes'
    });
  }
});

module.exports = router;
