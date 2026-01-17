// server/routes/productRoutes.js
const express = require("express");
const router = express.Router();
const multer = require("multer");
const path = require("path");
const fs = require("fs");
const fsp = require("fs/promises");
const mysql = require("mysql2/promise");

// Database connection pool (use same as server.js)
const pool = mysql.createPool({
  host: "localhost",
  user: "chatuser",
  password: "chat1234#db",
  database: "chat_db",
});

// Multer configuration for product images
const PRODUCT_UPLOAD_DIR = path.join(__dirname, "../uploads/products");
if (!fs.existsSync(PRODUCT_UPLOAD_DIR)) {
  fs.mkdirSync(PRODUCT_UPLOAD_DIR, { recursive: true });
}

// Chunk upload storage
const chunkStorage = multer.memoryStorage();
const uploadChunk = multer({
  storage: chunkStorage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB per chunk
});

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, PRODUCT_UPLOAD_DIR);
  },
  filename: (req, file, cb) => {
    const userId = req.body.user_id || "unknown";
    const timestamp = Date.now();
    const ext = path.extname(file.originalname);
    cb(null, `user_${userId}_product_${timestamp}${ext}`);
  },
});

// Store upload sessions
const uploads = new Map();

const upload = multer({
  storage: storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB
  fileFilter: (req, file, cb) => {
    // Check file extension
    const ext = path.extname(file.originalname).toLowerCase();
    const allowedExts = [".jpg", ".jpeg", ".png", ".gif", ".webp"];

    // Check mimetype (can be image/jpeg, image/png, etc. or application/octet-stream from Flutter)
    const allowedMimeTypes = [
      "image/jpeg",
      "image/jpg",
      "image/png",
      "image/gif",
      "image/webp",
      "application/octet-stream", // Flutter sometimes sends this
    ];

    const isValidExt = allowedExts.includes(ext);
    const mimetype = file.mimetype ? file.mimetype.toLowerCase() : "";
    const isValidMime = allowedMimeTypes.includes(mimetype);

    // Accept if extension is valid (primary check - most reliable)
    if (isValidExt) {
      console.log("File accepted by extension:", {
        originalname: file.originalname,
        ext: ext,
        mimetype: mimetype || "missing",
      });
      return cb(null, true);
    }

    // Also accept if mimetype is valid
    if (isValidMime) {
      console.log("File accepted by mimetype:", {
        originalname: file.originalname,
        mimetype: mimetype,
        ext: ext,
      });
      return cb(null, true);
    }

    // Log for debugging
    console.error("File rejected:", {
      originalname: file.originalname,
      mimetype: mimetype || "missing",
      ext: ext,
      fieldname: file.fieldname,
    });

    cb(new Error("Only image files are allowed (jpg, jpeg, png, gif, webp)"));
  },
});

// Base URL for serving images
const BASE_URL = process.env.BASE_URL || "http://184.168.126.71:3000";

// ==================== ROUTES ====================

/**
 * POST /api/products/save
 * Save or update a product (draft or publish) - WITH ATTRIBUTES IN 3 SEPARATE TABLES
 * FIXES APPLIED:
 * 1. products table mein price column mein price save karo
 * 2. products table mein stock column mein available_qty save karo
 * 3. product_sizes table mein price aur stock save karo (STOCK FIX)
 * 4. product_variants table mein price aur stock save karo (STOCK FIX)
 * 5. product_colors table mein price aur stock save karo (STOCK FIX)
 */
router.post("/save", async (req, res) => {
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    const {
      user_id,
      name,
      category,
      subcategory,
      available_qty,
      description,
      status,
      price_slabs,
      attributes,
      selected_attribute_values,
      variations,
      sizes,
      images,
      product_id, // For update
      stock_mode, // 'simple' or 'color_size'
      stock_by_color_size, // {color: {size: qty}}
      marketplace_enabled, // 0 or 1
      price, // Regular price
      original_price, // Original price (if any)
    } = req.body;

    // Validation
    if (!user_id || !name || !status) {
      await connection.rollback();
      return res.status(400).json({
        success: false,
        message: "Missing required fields: user_id, name, status",
      });
    }

    if (!["draft", "publish"].includes(status)) {
      await connection.rollback();
      return res.status(400).json({
        success: false,
        message: "Status must be 'draft' or 'publish'",
      });
    }

    // Parse JSON data
    let processedVariations = [];
    try {
      processedVariations = JSON.parse(variations || "[]");
    } catch (e) {
      processedVariations = [];
    }

    let processedSizes = [];
    try {
      processedSizes = JSON.parse(sizes || "[]");
    } catch (e) {
      processedSizes = [];
    }

    let processedImages = [];
    try {
      processedImages = JSON.parse(images || "[]");
    } catch (e) {
      processedImages = [];
    }

    let stockData = {};
    if (stock_by_color_size) {
      try {
        stockData = JSON.parse(stock_by_color_size);
      } catch (e) {
        stockData = {};
      }
    }

    // Parse attributes and price slabs for 3 tables
    let attributesJson = {};
    let selectedAttributesJson = {};
    let priceSlabsArray = [];

    try {
      attributesJson = JSON.parse(attributes || "{}");
    } catch (e) {
      attributesJson = {};
    }

    try {
      selectedAttributesJson = JSON.parse(selected_attribute_values || "{}");
    } catch (e) {
      selectedAttributesJson = {};
    }

    try {
      priceSlabsArray = JSON.parse(price_slabs || "[]");
    } catch (e) {
      priceSlabsArray = [];
    }

    // FIX 1: Calculate base price from price slabs (lowest price)
    let basePrice = 0;
    if (priceSlabsArray && priceSlabsArray.length > 0) {
      // Find the lowest price from price slabs
      const prices = priceSlabsArray
        .filter(slab => slab.price && !isNaN(slab.price))
        .map(slab => parseFloat(slab.price));

      if (prices.length > 0) {
        basePrice = Math.min(...prices);
      }
    }

    // If direct price is provided, use that (higher priority)
    if (price && !isNaN(price)) {
      basePrice = parseFloat(price);
    }

    // FIX 2: Calculate total stock from available_qty
    let totalStock = 0;
    if (available_qty && !isNaN(available_qty)) {
      totalStock = parseInt(available_qty);
    } else if (stock_mode === "color_size" && Object.keys(stockData).length > 0) {
      // Calculate total stock from stock_by_color_size
      for (const colorName in stockData) {
        if (stockData.hasOwnProperty(colorName)) {
          const sizesObj = stockData[colorName];
          for (const size in sizesObj) {
            if (sizesObj.hasOwnProperty(size)) {
              totalStock += parseInt(sizesObj[size]) || 0;
            }
          }
        }
      }
    } else if (processedVariations.length > 0) {
      // Calculate total stock from variations
      for (const variant of processedVariations) {
        if (variant.stock) {
          if (typeof variant.stock === 'object') {
            // If stock is object (size-wise), sum all sizes
            Object.values(variant.stock).forEach(qty => {
              totalStock += parseInt(qty) || 0;
            });
          } else {
            totalStock += parseInt(variant.stock) || 0;
          }
        }
      }
    }

    // FIXED: If stock_mode is color_size, ensure variations have CORRECT stock data
    if (stock_mode === "color_size" && stock_by_color_size) {
      processedVariations = processedVariations.map((variation) => {
        const colorName = variation.name || variation.color;
        if (stockData[colorName]) {
          // FIX: Calculate total stock from size-wise stock
          const sizeStockObj = stockData[colorName];
          const variantStock = Object.values(sizeStockObj).reduce(
            (sum, qty) => sum + (parseInt(qty) || 0),
            0
          );
          variation.stock = variantStock;
          variation.totalStock = variantStock;
        }
        return variation;
      });
    }

    // Prepare stock_by_color_size for database (JSON column)
    const stockByColorSizeJson = stock_mode === "color_size" && stock_by_color_size
      ? (typeof stock_by_color_size === "string" ? stock_by_color_size : JSON.stringify(stockData))
      : null;

    let finalProductId = product_id;

    // 1. SAVE TO PRODUCTS TABLE
    if (product_id) {
      // Update existing product
      // Check if marketplace_enabled column exists
      let hasMarketplaceColumn = false;
      try {
        const [columns] = await connection.execute(
          "SHOW COLUMNS FROM products LIKE 'marketplace_enabled'"
        );
        hasMarketplaceColumn = columns.length > 0;
      } catch (e) {
        // Column doesn't exist, skip it
      }

      // Check if stock column exists
      let hasStockColumn = false;
      try {
        const [columns] = await connection.execute(
          "SHOW COLUMNS FROM products LIKE 'stock'"
        );
        hasStockColumn = columns.length > 0;
      } catch (e) {
        // Column doesn't exist
      }

      // Check if price column exists
      let hasPriceColumn = false;
      try {
        const [columns] = await connection.execute(
          "SHOW COLUMNS FROM products LIKE 'price'"
        );
        hasPriceColumn = columns.length > 0;
      } catch (e) {
        // Column doesn't exist
      }

      // Check if original_price column exists
      let hasOriginalPriceColumn = false;
      try {
        const [columns] = await connection.execute(
          "SHOW COLUMNS FROM products LIKE 'original_price'"
        );
        hasOriginalPriceColumn = columns.length > 0;
      } catch (e) {
        // Column doesn't exist
      }

      let updateQuery = `UPDATE products SET
          name = ?,
          category = ?,
          subcategory = ?,
          available_qty = ?,
          description = ?,
          status = ?,
          price_slabs = ?,
          attributes = ?,
          selected_attribute_values = ?,
          variations = ?,
          sizes = ?,
          images = ?,
          stock_mode = ?,
          stock_by_color_size = ?`;

      const updateParams = [
        name,
        category || null,
        subcategory || null,
        available_qty || "0",
        description || null,
        status,
        price_slabs || "[]",
        attributes || "{}",
        selected_attribute_values || "{}",
        JSON.stringify(processedVariations),
        JSON.stringify(processedSizes),
        JSON.stringify(processedImages),
        stock_mode || "simple",
        stockByColorSizeJson,
      ];

      // FIX: Add stock to update if column exists
      if (hasStockColumn) {
        updateQuery += `, stock = ?`;
        updateParams.push(totalStock);
      }

      // FIX: Add price to update if column exists
      if (hasPriceColumn && basePrice > 0) {
        updateQuery += `, price = ?`;
        updateParams.push(basePrice);
      }

      // FIX: Add original_price to update if column exists
      if (hasOriginalPriceColumn && original_price) {
        updateQuery += `, original_price = ?`;
        updateParams.push(original_price);
      }

      if (hasMarketplaceColumn) {
        updateQuery += `, marketplace_enabled = ?`;
        updateParams.push(marketplace_enabled !== undefined ? (marketplace_enabled ? 1 : 0) : 0);
      }

      updateQuery += `, updated_at = NOW()
        WHERE id = ? AND user_id = ?`;
      updateParams.push(product_id, user_id);

      const [result] = await connection.execute(updateQuery, updateParams);

      if (result.affectedRows === 0) {
        await connection.rollback();
        return res.status(404).json({
          success: false,
          message: "Product not found or unauthorized",
        });
      }
    } else {
      // Insert new product
      // Check if marketplace_enabled column exists
      let hasMarketplaceColumn = false;
      try {
        const [columns] = await connection.execute(
          "SHOW COLUMNS FROM products LIKE 'marketplace_enabled'"
        );
        hasMarketplaceColumn = columns.length > 0;
      } catch (e) {
        // Column doesn't exist, skip it
      }

      // Check if stock column exists
      let hasStockColumn = false;
      try {
        const [columns] = await connection.execute(
          "SHOW COLUMNS FROM products LIKE 'stock'"
        );
        hasStockColumn = columns.length > 0;
      } catch (e) {
        // Column doesn't exist
      }

      // Check if price column exists
      let hasPriceColumn = false;
      try {
        const [columns] = await connection.execute(
          "SHOW COLUMNS FROM products LIKE 'price'"
        );
        hasPriceColumn = columns.length > 0;
      } catch (e) {
        // Column doesn't exist
      }

      // Check if original_price column exists
      let hasOriginalPriceColumn = false;
      try {
        const [columns] = await connection.execute(
          "SHOW COLUMNS FROM products LIKE 'original_price'"
        );
        hasOriginalPriceColumn = columns.length > 0;
      } catch (e) {
        // Column doesn't exist
      }

      let insertQuery = `INSERT INTO products (
          user_id, name, category, subcategory, available_qty, description, status,
          price_slabs, attributes, selected_attribute_values,
          variations, sizes, images, stock_mode, stock_by_color_size`;

      let valuesPlaceholders = `?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?`;

      const insertParams = [
        user_id,
        name,
        category || null,
        subcategory || null,
        available_qty || "0",
        description || null,
        status,
        price_slabs || "[]",
        attributes || "{}",
        selected_attribute_values || "{}",
        JSON.stringify(processedVariations),
        JSON.stringify(processedSizes),
        JSON.stringify(processedImages),
        stock_mode || "simple",
        stockByColorSizeJson,
      ];

      // FIX: Add stock to insert if column exists
      if (hasStockColumn) {
        insertQuery += `, stock`;
        valuesPlaceholders += `, ?`;
        insertParams.push(totalStock);
      }

      // FIX: Add price to insert if column exists
      if (hasPriceColumn) {
        insertQuery += `, price`;
        valuesPlaceholders += `, ?`;
        insertParams.push(basePrice || 0);
      }

      // FIX: Add original_price to insert if column exists
      if (hasOriginalPriceColumn) {
        insertQuery += `, original_price`;
        valuesPlaceholders += `, ?`;
        insertParams.push(original_price || basePrice || 0);
      }

      if (hasMarketplaceColumn) {
        insertQuery += `, marketplace_enabled`;
        valuesPlaceholders += `, ?`;
        insertParams.push(marketplace_enabled !== undefined ? (marketplace_enabled ? 1 : 0) : 0);
      }

      insertQuery += `, created_at, updated_at
        ) VALUES (${valuesPlaceholders}, NOW(), NOW())`;

      const [result] = await connection.execute(insertQuery, insertParams);
      finalProductId = result.insertId;
    }

    // ==================== STEP 2: SAVE TO 3 ATTRIBUTES TABLES ====================

    console.log(`?? Saving attributes for product ${finalProductId} to 3 tables...`);

    // STEP 2.1: Save to product_attributes_master table
    if (attributesJson && typeof attributesJson === 'object' && Object.keys(attributesJson).length > 0) {
      console.log(`Found ${Object.keys(attributesJson).length} attributes in JSON`);

      for (const [attributeName, attributeValues] of Object.entries(attributesJson)) {
        // Check if this attribute already exists in master for this seller
        const [existingMasterAttr] = await connection.execute(
          `SELECT id FROM product_attributes_master
           WHERE seller_id = ? AND attributes_name = ?`,
          [user_id, attributeName]
        );

        let masterAttrId;

        if (existingMasterAttr.length === 0) {
          // Insert new attribute into master
          const [insertResult] = await connection.execute(
            `INSERT INTO product_attributes_master
            (seller_id, attributes_name, status)
            VALUES (?, ?, 1)`,
            [user_id, attributeName]
          );
          masterAttrId = insertResult.insertId;
          console.log(`? Added to master table: ${attributeName}, ID: ${masterAttrId}, Seller: ${user_id}`);
        } else {
          masterAttrId = existingMasterAttr[0].id;
          console.log(`? Found in master table: ${attributeName}, ID: ${masterAttrId}`);
        }

        // STEP 2.2: Save to tbl_product_attributes table
        const selectedValue = selectedAttributesJson[attributeName];

        if (selectedValue) {
          // Delete existing entry for this product and attribute
          await connection.execute(
            `DELETE FROM tbl_product_attributes
             WHERE product_id = ? AND seller_id = ? AND attributes_name = ?`,
            [finalProductId, user_id, attributeName]
          );

          // Insert new entry
          await connection.execute(
            `INSERT INTO tbl_product_attributes
            (product_id, seller_id, attributes_id, attributes_name, status, created_at)
            VALUES (?, ?, ?, ?, 1, NOW())`,
            [finalProductId, user_id, masterAttrId, attributeName]
          );

          console.log(`? Saved to tbl_product_attributes: ${attributeName} = ${selectedValue}, Product: ${finalProductId}`);
        } else {
          console.log(`?? Attribute ${attributeName} not selected for product ${finalProductId}`);
        }
      }
    } else {
      console.log(`?? No attributes found in attributesJson for product ${finalProductId}`);
    }

    // STEP 2.3: Save price slabs to tbl_product_range_prices table
    if (priceSlabsArray && Array.isArray(priceSlabsArray) && priceSlabsArray.length > 0) {
      console.log(`Found ${priceSlabsArray.length} price slabs in JSON`);

      // Delete existing price slabs for this product
      await connection.execute(
        `DELETE FROM tbl_product_range_prices
         WHERE product_id = ? AND seller_id = ?`,
        [finalProductId, user_id]
      );

      // Insert new price slabs
      for (const slab of priceSlabsArray) {
        if (slab.moq || slab.min_qty) {
          const minQty = slab.moq || slab.min_qty || 1;
          const price = slab.price || 0;

          await connection.execute(
            `INSERT INTO tbl_product_range_prices
            (product_id, seller_id, min_qty, price, status, created_at)
            VALUES (?, ?, ?, ?, 1, NOW())`,
            [finalProductId, user_id, minQty, price]
          );
          console.log(`? Saved price slab: MOQ=${minQty}, Price=${price}, Product: ${finalProductId}`);
        }
      }
    } else {
      console.log(`?? No price slabs found for product ${finalProductId}`);
    }

    // ==================== STEP 3: SAVE TO OTHER RELATED TABLES ====================

    // 3.1. product_colors table - FIX: Price aur Stock save karo
    // Clear existing colors
    await connection.execute(
      'DELETE FROM product_colors WHERE product_id = ?',
      [finalProductId]
    );

    // Insert new colors from variations
    for (const variant of processedVariations) {
      if (variant.name) {
        // FIX: Handle stock value - ALWAYS save stock
        let finalStock = 0;

        if (stock_mode === "color_size" && stockData[variant.name]) {
          // If stock_by_color_size has data for this color, calculate total
          const sizesObj = stockData[variant.name] || {};
          finalStock = Object.values(sizesObj).reduce((sum, qty) => sum + (parseInt(qty) || 0), 0);
        } else if (variant.stock) {
          // Otherwise use variant stock
          if (typeof variant.stock === 'object' && variant.stock !== null) {
            // If stock is JSON object like {"L":50,"XXL":50,"M":50}
            finalStock = Object.values(variant.stock).reduce((sum, qty) => sum + (parseInt(qty) || 0), 0);
          } else {
            // If stock is already integer or string
            finalStock = parseInt(variant.stock) || parseInt(variant.totalStock) || 0;
          }
        }

        // FIX: Get price from variant or use base price
        const variantPrice = variant.price || basePrice || 0;

        await connection.execute(
          `INSERT INTO product_colors
          (product_id, color_name, image_url, price, stock)
          VALUES (?, ?, ?, ?, ?)`,
          [
            finalProductId,
            variant.name,
            variant.image || null,
            variantPrice,
            finalStock
          ]
        );
        console.log(`? Saved to product_colors: ${variant.name}, Price: ${variantPrice}, Stock: ${finalStock}`);
      }
    }

    // 3.2. product_sizes table - FIX: Price aur Stock save karo (STOCK FIX)
    // Clear existing sizes
    await connection.execute(
      'DELETE FROM product_sizes WHERE product_id = ?',
      [finalProductId]
    );

    // FIX: Calculate size-wise stock
    const sizeStockMap = {};
    if (stock_mode === 'color_size' && Object.keys(stockData).length > 0) {
      // Calculate total stock per size from stock_by_color_size
      for (const colorName in stockData) {
        if (stockData.hasOwnProperty(colorName)) {
          const sizesObj = stockData[colorName];
          for (const size in sizesObj) {
            if (sizesObj.hasOwnProperty(size)) {
              if (!sizeStockMap[size]) {
                sizeStockMap[size] = 0;
              }
              sizeStockMap[size] += parseInt(sizesObj[size]) || 0;
            }
          }
        }
      }
    } else if (processedVariations.length > 0) {
      // Calculate from variations if no stock_by_color_size
      for (const variant of processedVariations) {
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

    // Insert new sizes
    for (const size of processedSizes) {
      // FIX: Get stock for this size
      const sizeStock = sizeStockMap[size] || 0;

      // FIX: Use base price for size
      await connection.execute(
        `INSERT INTO product_sizes
        (product_id, size, price, stock)
        VALUES (?, ?, ?, ?)`,
        [finalProductId, size, basePrice || 0, sizeStock]
      );
      console.log(`? Saved to product_sizes: ${size}, Price: ${basePrice || 0}, Stock: ${sizeStock}`);
    }

    // 3.3. product_images table
    // Clear existing images
    await connection.execute(
      'DELETE FROM product_images WHERE product_id = ?',
      [finalProductId]
    );

    // Insert new images
    for (const imageUrl of processedImages) {
      await connection.execute(
        `INSERT INTO product_images (product_id, image_url)
        VALUES (?, ?)`,
        [finalProductId, imageUrl]
      );
    }

    // 3.4. product_variants table - FIX: Price aur Stock save karo (STOCK FIX)
    // Clear existing variants
    await connection.execute(
      'DELETE FROM product_variants WHERE product_id = ?',
      [finalProductId]
    );

    // Save variants if we have both variations and sizes
    if (processedVariations.length > 0 && processedSizes.length > 0) {
      console.log("? Saving variants to product_variants table");

      // Method 1: If stock_by_color_size has specific data
      if (stock_mode === 'color_size' && Object.keys(stockData).length > 0) {
        console.log("Using stock_by_color_size for variant stock");

        for (const [colorName, sizesObj] of Object.entries(stockData)) {
          const colorVariant = processedVariations.find(v => v.name === colorName);
          // FIX: Get price from variant or use base price
          const variantPrice = colorVariant?.price || basePrice || 0;

          for (const [size, qty] of Object.entries(sizesObj)) {
            await connection.execute(
              `INSERT INTO product_variants
              (product_id, color_name, size, stock, price)
              VALUES (?, ?, ?, ?, ?)`,
              [finalProductId, colorName, size, parseInt(qty) || 0, variantPrice]
            );
            console.log(`? Saved variant: ${colorName}-${size}, Price: ${variantPrice}, Stock: ${qty}`);
          }
        }
      } else if (processedVariations.length > 0 && processedSizes.length > 0) {
        // Method 2: Generate all color-size combinations from variations data
        console.log("Generating all color-size combinations from variations");

        for (const variant of processedVariations) {
          const colorName = variant.name;
          if (!colorName) continue;

          // FIX: Get price from variant or use base price
          const variantPrice = variant.price || basePrice || 0;

          // Check if variant has size-wise stock
          if (variant.stock && typeof variant.stock === 'object') {
            // If stock is JSON object like {"L":10, "M":20}
            for (const size in variant.stock) {
              if (processedSizes.includes(size)) {
                const sizeStock = parseInt(variant.stock[size]) || 0;
                await connection.execute(
                  `INSERT INTO product_variants
                  (product_id, color_name, size, stock, price)
                  VALUES (?, ?, ?, ?, ?)`,
                  [finalProductId, colorName, size, sizeStock, variantPrice]
                );
                console.log(`? Saved variant from object: ${colorName}-${size}, Price: ${variantPrice}, Stock: ${sizeStock}`);
              }
            }
          } else {
            // If stock is single value, distribute evenly or use 0
            const variantStock = parseInt(variant.stock) || parseInt(variant.totalStock) || 0;
            const stockPerSize = Math.floor(variantStock / processedSizes.length) || 0;

            for (const size of processedSizes) {
              await connection.execute(
                `INSERT INTO product_variants
                (product_id, color_name, size, stock, price)
                VALUES (?, ?, ?, ?, ?)`,
                [finalProductId, colorName, size, stockPerSize, variantPrice]
              );
              console.log(`? Saved variant from total: ${colorName}-${size}, Price: ${variantPrice}, Stock: ${stockPerSize}`);
            }
          }
        }
      }
    } else {
      console.log("? NOT saving variants - missing data:");
      if (processedVariations.length === 0) console.log("- No variations");
      if (processedSizes.length === 0) console.log("- No sizes");
    }

    // Commit transaction
    await connection.commit();

    console.log(`? Product ${finalProductId} saved successfully to ALL tables including 3 attributes tables`);
    console.log(`? Stock saved in products table: ${totalStock}`);
    console.log(`? Price saved in products table: ${basePrice}`);

    return res.json({
      success: true,
      message: product_id ? "Product updated successfully" : "Product saved successfully",
      data: {
        product_id: finalProductId,
        attributes_saved: true,
        price_slabs_saved: true,
        saved_to_3_tables: true,
        stock: totalStock,
        price: basePrice
      },
    });

  } catch (error) {
    await connection.rollback();
    console.error("? Error saving product:", error);
    res.status(500).json({
      success: false,
      message: "Internal server error",
      error: error.message,
    });
  } finally {
    connection.release();
  }
});

/**
 * POST /api/products/upload-image
 * Upload a single product image (simple upload - for small images)
 */
router.post("/upload-image", upload.single("image"), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        message: "No image file provided",
      });
    }

    const userId = req.body.user_id || "unknown";
    const imageUrl = `${BASE_URL}/uploads/products/${req.file.filename}`;

    res.json({
      success: true,
      image_url: imageUrl,
    });
  } catch (error) {
    console.error("Error uploading image:", error);
    res.status(500).json({
      success: false,
      message: "Error uploading image",
      error: error.message,
    });
  }
});

/**
 * POST /api/products/upload-image/init
 * Initialize chunk upload session
 */
router.post("/upload-image/init", async (req, res) => {
  try {
    const { user_id, original_name, total_size } = req.body;

    if (!user_id || !original_name || !total_size) {
      return res.status(400).json({
        success: false,
        message: "Missing required fields: user_id, original_name, total_size",
      });
    }

    const uploadId = `product_${user_id}_${Date.now()}_${Math.random()
      .toString(36)
      .substr(2, 9)}`;
    const timestamp = Date.now();
    const ext = path.extname(original_name);
    const fileName = `user_${user_id}_product_${timestamp}${ext}`;
    const tempPath = path.join(PRODUCT_UPLOAD_DIR, `${uploadId}.tmp`);

    uploads.set(uploadId, {
      userId: user_id,
      fileName: fileName,
      tempPath: tempPath,
      totalSize: parseInt(total_size),
      received: 0,
      createdAt: Date.now(),
    });

    res.json({
      success: true,
      upload_id: uploadId,
    });
  } catch (error) {
    console.error("Error initializing upload:", error);
    res.status(500).json({
      success: false,
      message: "Error initializing upload",
      error: error.message,
    });
  }
});

/**
 * POST /api/products/upload-image/chunk
 * Upload a chunk of image
 */
router.post(
  "/upload-image/chunk",
  uploadChunk.single("chunk"),
  async (req, res) => {
    try {
      const { upload_id } = req.body;

      if (!upload_id) {
        return res.status(400).json({
          success: false,
          message: "Missing upload_id",
        });
      }

      const session = uploads.get(upload_id);
      if (!session) {
        return res.status(400).json({
          success: false,
          message: "Invalid upload_id",
        });
      }

      if (!req.file?.buffer) {
        return res.status(400).json({
          success: false,
          message: "No chunk data provided",
        });
      }

      await fsp.appendFile(session.tempPath, req.file.buffer);
      session.received += req.file.buffer.length;

      res.json({
        success: true,
        received: session.received,
        total: session.totalSize,
      });
    } catch (error) {
      console.error("Error uploading chunk:", error);
      res.status(500).json({
        success: false,
        message: "Error uploading chunk",
        error: error.message,
      });
    }
  }
);

/**
 * POST /api/products/upload-image/finalize
 * Finalize chunk upload and return image URL
 */
router.post("/upload-image/finalize", async (req, res) => {
  try {
    const { upload_id } = req.body;

    if (!upload_id) {
      return res.status(400).json({
        success: false,
        message: "Missing upload_id",
      });
    }

    const session = uploads.get(upload_id);
    if (!session) {
      return res.status(400).json({
        success: false,
        message: "Invalid upload_id",
      });
    }

    // Check if all chunks received
    if (session.received !== session.totalSize) {
      return res.status(400).json({
        success: false,
        message: `Incomplete upload. Received: ${session.received}, Expected: ${session.totalSize}`,
      });
    }

    // Move temp file to final location
    const finalPath = path.join(PRODUCT_UPLOAD_DIR, session.fileName);
    await fsp.rename(session.tempPath, finalPath);

    // Clean up session
    uploads.delete(upload_id);

    const imageUrl = `${BASE_URL}/uploads/products/${session.fileName}`;

    res.json({
      success: true,
      image_url: imageUrl,
    });
  } catch (error) {
    console.error("Error finalizing upload:", error);
    // Clean up on error
    const session = uploads.get(req.body.upload_id);
    if (session) {
      try {
        await fsp.unlink(session.tempPath);
      } catch (e) {
        // Ignore cleanup errors
      }
      uploads.delete(req.body.upload_id);
    }
    res.status(500).json({
      success: false,
      message: "Error finalizing upload",
      error: error.message,
    });
  }
});

/**
 * POST /api/products/list
 * Get all products for a user (or all users if marketplace=true)
 */
router.post("/list", async (req, res) => {
  try {
    const { user_id, status, limit = 20, offset = 0, marketplace } = req.body;

    // If marketplace=true, get all users' products
    const isMarketplace = marketplace === true || marketplace === 'true';

    if (!isMarketplace && !user_id) {
      return res.status(400).json({
        success: false,
        message: "user_id is required (or set marketplace=true)",
      });
    }

    const connection = await pool.getConnection();

    try {
      // Check if marketplace_enabled column exists
      let hasMarketplaceColumn = false;
      try {
        const [columns] = await connection.execute(
          "SHOW COLUMNS FROM products LIKE 'marketplace_enabled'"
        );
        hasMarketplaceColumn = columns.length > 0;
      } catch (e) {
        console.log("Could not check for marketplace_enabled column:", e.message);
      }

      // Ensure limit and offset are proper integers
      let limitInt = 20;
      let offsetInt = 0;

      if (limit != null && limit !== undefined) {
        const parsed = parseInt(String(limit), 10);
        limitInt = isNaN(parsed) ? 20 : Math.max(0, parsed);
      }

      if (offset != null && offset !== undefined) {
        const parsed = parseInt(String(offset), 10);
        offsetInt = isNaN(parsed) ? 0 : Math.max(0, parsed);
      }

      let query;
      const params = [];

      if (isMarketplace) {
        // Get all products for marketplace (all users)
        query = "SELECT * FROM products WHERE 1=1";

        if (status) {
          query += " AND status = ?";
          params.push(String(status));
        }

        // Only show products with marketplace enabled (if column exists)
        if (hasMarketplaceColumn) {
          query += " AND marketplace_enabled = 1";
        }

        // Use LIMIT and OFFSET directly in query (safe since we control the values)
        query += ` ORDER BY updated_at DESC LIMIT ${parseInt(String(limitInt), 10)} OFFSET ${parseInt(String(offsetInt), 10)}`;
      } else {
        // Get products for specific user
        query = "SELECT * FROM products WHERE user_id = ?";
        params.push(parseInt(String(user_id), 10));

        if (status) {
          query += " AND status = ?";
          params.push(String(status));
        }

        // Use LIMIT and OFFSET directly in query (safe since we control the values)
        query += ` ORDER BY updated_at DESC LIMIT ${parseInt(String(limitInt), 10)} OFFSET ${parseInt(String(offsetInt), 10)}`;
      }

      // Debug: Log query and params
      console.log("?? Products list query:", query);
      console.log("?? Products list params:", params);
      console.log("?? Params count:", params.length);
      const placeholderCount = (query.match(/\?/g) || []).length;
      console.log("?? Placeholders in query:", placeholderCount);

      // Validate params count matches placeholders
      if (params.length !== placeholderCount) {
        console.error("? Parameter mismatch! Params:", params.length, "Placeholders:", placeholderCount);
        throw new Error(`Parameter count mismatch: ${params.length} params but ${placeholderCount} placeholders`);
      }

      let rows;
      try {
        [rows] = await connection.execute(query, params);
      } catch (queryError) {
        // If error is about marketplace_enabled column, retry without it
        if (queryError.message.includes('marketplace_enabled') && hasMarketplaceColumn) {
          console.log("?? Retrying query without marketplace_enabled filter");
          // Remove marketplace_enabled condition and retry
          query = query.replace(" AND marketplace_enabled = 1", "");
          [rows] = await connection.execute(query, params);
        } else {
          console.error("? Query error:", queryError.message);
          console.error("? Query:", query);
          console.error("? Params:", params);
          throw queryError;
        }
      }

      // Get total count
      let countQuery;
      const countParams = [];

      if (isMarketplace) {
        countQuery = "SELECT COUNT(*) as total FROM products WHERE 1=1";
        if (status) {
          countQuery += " AND status = ?";
          countParams.push(status);
        }
        if (hasMarketplaceColumn) {
          countQuery += " AND marketplace_enabled = 1";
        }
      } else {
        countQuery = "SELECT COUNT(*) as total FROM products WHERE user_id = ?";
        countParams.push(user_id);
        if (status) {
          countQuery += " AND status = ?";
          countParams.push(status);
        }
      }

      const [countResult] = await connection.execute(countQuery, countParams);
      const total = countResult[0].total;

      res.json({
        success: true,
        data: rows,
        total: total,
      });
    } finally {
      connection.release();
    }
  } catch (error) {
    console.error("Error getting products:", error);
    res.status(500).json({
      success: false,
      message: "Error fetching products",
      error: error.message,
    });
  }
});

/**
 * POST /api/products/get
 * Get a single product by ID
 */
router.post("/get", async (req, res) => {
  try {
    const { user_id, product_id } = req.body;

    if (!user_id || !product_id) {
      return res.status(400).json({
        success: false,
        message: "user_id and product_id are required",
      });
    }

    const connection = await pool.getConnection();

    try {
      const [rows] = await connection.execute(
        "SELECT * FROM products WHERE id = ? AND user_id = ?",
        [product_id, user_id]
      );

      if (rows.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Product not found",
        });
      }

      res.json({
        success: true,
        data: rows[0],
      });
    } finally {
      connection.release();
    }
  } catch (error) {
    console.error("Error getting product:", error);
    res.status(500).json({
      success: false,
      message: "Error fetching product",
      error: error.message,
    });
  }
});

/**
 * POST /api/products/get-full
 * Get product with all related data from all tables
 */
router.post("/get-full", async (req, res) => {
  try {
    const { product_id } = req.body;

    if (!product_id) {
      return res.status(400).json({
        success: false,
        message: "product_id is required",
      });
    }

    const connection = await pool.getConnection();

    try {
      // Get product from products table
      const [products] = await connection.execute(
        "SELECT * FROM products WHERE id = ?",
        [product_id]
      );

      if (products.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Product not found",
        });
      }

      const product = products[0];

      // Get data from 3 attributes tables
      const [masterAttributes] = await connection.execute(
        `SELECT pam.* FROM product_attributes_master pam
         JOIN tbl_product_attributes tpa ON pam.id = tpa.attributes_id
         WHERE tpa.product_id = ?`,
        [product_id]
      );

      const [productAttributes] = await connection.execute(
        "SELECT * FROM tbl_product_attributes WHERE product_id = ?",
        [product_id]
      );

      const [priceSlabs] = await connection.execute(
        "SELECT * FROM tbl_product_range_prices WHERE product_id = ? ORDER BY min_qty",
        [product_id]
      );

      // Get other related data from all tables
      const [colors] = await connection.execute(
        "SELECT * FROM product_colors WHERE product_id = ?",
        [product_id]
      );

      const [sizes] = await connection.execute(
        "SELECT * FROM product_sizes WHERE product_id = ?",
        [product_id]
      );

      const [images] = await connection.execute(
        "SELECT * FROM product_images WHERE product_id = ? ORDER BY id",
        [product_id]
      );

      const [variants] = await connection.execute(
        "SELECT * FROM product_variants WHERE product_id = ?",
        [product_id]
      );

      const [reviews] = await connection.execute(
        "SELECT * FROM product_reviews WHERE product_id = ? ORDER BY created_at DESC",
        [product_id]
      );

      // Parse JSON fields
      try {
        product.variations = JSON.parse(product.variations || "[]");
      } catch (e) {
        product.variations = [];
      }

      try {
        product.sizes = JSON.parse(product.sizes || "[]");
      } catch (e) {
        product.sizes = [];
      }

      try {
        product.images = JSON.parse(product.images || "[]");
      } catch (e) {
        product.images = [];
      }

      try {
        product.attributes = JSON.parse(product.attributes || "{}");
      } catch (e) {
        product.attributes = {};
      }

      try {
        product.selected_attribute_values = JSON.parse(product.selected_attribute_values || "{}");
      } catch (e) {
        product.selected_attribute_values = {};
      }

      try {
        product.price_slabs = JSON.parse(product.price_slabs || "[]");
      } catch (e) {
        product.price_slabs = [];
      }

      try {
        product.stock_by_color_size = product.stock_by_color_size
          ? JSON.parse(product.stock_by_color_size)
          : {};
      } catch (e) {
        product.stock_by_color_size = {};
      }

      res.json({
        success: true,
        data: {
          product: product,
          master_attributes: masterAttributes,
          product_attributes: productAttributes,
          price_slabs: priceSlabs,
          colors: colors,
          sizes: sizes,
          images: images,
          variants: variants,
          reviews: reviews
        }
      });

    } finally {
      connection.release();
    }
  } catch (error) {
    console.error("Error getting full product:", error);
    res.status(500).json({
      success: false,
      message: "Error fetching product details",
      error: error.message,
    });
  }
});

/**
 * POST /api/products/update
 * Update an existing product - WITH ATTRIBUTES IN 3 TABLES
 * FIXES APPLIED:
 * 1. products table mein price column update karo
 * 2. products table mein stock column update karo
 * 3. product_sizes table mein price aur stock update karo (STOCK FIX)
 * 4. product_variants table mein price aur stock update karo (STOCK FIX)
 * 5. product_colors table mein price aur stock update karo (STOCK FIX)
 */
router.post("/update", async (req, res) => {
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    const {
      user_id,
      product_id,
      name,
      category,
      subcategory,
      available_qty,
      description,
      status,
      price_slabs,
      attributes,
      selected_attribute_values,
      variations,
      sizes,
      new_images,
      stock_mode,
      stock_by_color_size,
      marketplace_enabled,
      price,
      original_price,
    } = req.body;

    if (!user_id || !product_id) {
      await connection.rollback();
      return res.status(400).json({
        success: false,
        message: "user_id and product_id are required",
      });
    }

    // Get existing product to merge images
    const [existing] = await connection.execute(
      "SELECT images, variations, sizes FROM products WHERE id = ? AND user_id = ?",
      [product_id, user_id]
    );

    if (existing.length === 0) {
      await connection.rollback();
      return res.status(404).json({
        success: false,
        message: "Product not found or unauthorized",
      });
    }

    let images = existing[0].images || "[]";
    if (new_images) {
      const existingImages = JSON.parse(images);
      const newImagesArray = JSON.parse(new_images);
      images = JSON.stringify([...existingImages, ...newImagesArray]);
    }

    // Process variations if provided
    let processedVariations = variations;
    let variationsArray = [];

    if (variations !== undefined) {
      if (typeof processedVariations === "string") {
        try {
          processedVariations = JSON.parse(processedVariations);
          variationsArray = JSON.parse(variations);
        } catch (e) {
          processedVariations = [];
          variationsArray = [];
        }
      } else {
        variationsArray = Array.isArray(variations) ? variations : [];
      }
    } else {
      // Use existing variations
      try {
        variationsArray = JSON.parse(existing[0].variations || "[]");
      } catch (e) {
        variationsArray = [];
      }
    }

    // Process sizes if provided
    let sizesArray = [];
    if (sizes !== undefined) {
      try {
        sizesArray = JSON.parse(sizes || "[]");
      } catch (e) {
        sizesArray = [];
      }
    } else {
      // Use existing sizes
      try {
        sizesArray = JSON.parse(existing[0].sizes || "[]");
      } catch (e) {
        sizesArray = [];
      }
    }

    // Parse stock data
    let stockData = {};
    if (stock_by_color_size) {
      try {
        stockData = JSON.parse(stock_by_color_size);
      } catch (e) {
        stockData = {};
      }
    }

    // If stock_mode is color_size, ensure variations have CORRECT stock data
    if (stock_mode === "color_size" && stock_by_color_size) {
      variationsArray = variationsArray.map((variation) => {
        const colorName = variation.name || variation.color;
        if (stockData[colorName]) {
          // FIX: Calculate total stock from size-wise stock
          const sizeStockObj = stockData[colorName];
          const totalStock = Object.values(sizeStockObj).reduce(
            (sum, qty) => sum + (parseInt(qty) || 0),
            0
          );
          variation.stock = totalStock;
          variation.totalStock = totalStock;
        }
        return variation;
      });

      processedVariations = JSON.stringify(variationsArray);
    }

    // Parse price slabs for calculating base price
    let priceSlabsArray = [];
    try {
      priceSlabsArray = JSON.parse(price_slabs || "[]");
    } catch (e) {
      priceSlabsArray = [];
    }

    // FIX 1: Calculate base price from price slabs (lowest price)
    let basePrice = 0;
    if (priceSlabsArray && priceSlabsArray.length > 0) {
      const prices = priceSlabsArray
        .filter(slab => slab.price && !isNaN(slab.price))
        .map(slab => parseFloat(slab.price));

      if (prices.length > 0) {
        basePrice = Math.min(...prices);
      }
    }

    // If direct price is provided, use that (higher priority)
    if (price && !isNaN(price)) {
      basePrice = parseFloat(price);
    }

    // FIX 2: Calculate total stock
    let totalStock = 0;
    if (available_qty && !isNaN(available_qty)) {
      totalStock = parseInt(available_qty);
    } else if (stock_mode === "color_size" && Object.keys(stockData).length > 0) {
      for (const colorName in stockData) {
        if (stockData.hasOwnProperty(colorName)) {
          const sizesObj = stockData[colorName];
          for (const size in sizesObj) {
            if (sizesObj.hasOwnProperty(size)) {
              totalStock += parseInt(sizesObj[size]) || 0;
            }
          }
        }
      }
    } else if (variationsArray.length > 0) {
      for (const variant of variationsArray) {
        if (variant.stock) {
          if (typeof variant.stock === 'object') {
            Object.values(variant.stock).forEach(qty => {
              totalStock += parseInt(qty) || 0;
            });
          } else {
            totalStock += parseInt(variant.stock) || 0;
          }
        }
      }
    }

    // Prepare stock_by_color_size for database (JSON column)
    const stockByColorSizeJson = stock_mode === "color_size" && stock_by_color_size
      ? (typeof stock_by_color_size === "string" ? stock_by_color_size : JSON.stringify(stockData))
      : null;

    // Check if marketplace_enabled column exists
    let hasMarketplaceColumn = false;
    try {
      const [columns] = await connection.execute(
        "SHOW COLUMNS FROM products LIKE 'marketplace_enabled'"
      );
      hasMarketplaceColumn = columns.length > 0;
    } catch (e) {
      // Column doesn't exist, skip it
    }

    // Check if stock column exists
    let hasStockColumn = false;
    try {
      const [columns] = await connection.execute(
        "SHOW COLUMNS FROM products LIKE 'stock'"
      );
      hasStockColumn = columns.length > 0;
    } catch (e) {
      // Column doesn't exist
    }

    // Check if price column exists
    let hasPriceColumn = false;
    try {
      const [columns] = await connection.execute(
        "SHOW COLUMNS FROM products LIKE 'price'"
      );
      hasPriceColumn = columns.length > 0;
    } catch (e) {
      // Column doesn't exist
    }

    // Check if original_price column exists
    let hasOriginalPriceColumn = false;
    try {
      const [columns] = await connection.execute(
        "SHOW COLUMNS FROM products LIKE 'original_price'"
      );
      hasOriginalPriceColumn = columns.length > 0;
    } catch (e) {
      // Column doesn't exist
    }

    let updateQuery = `UPDATE products SET
        name = COALESCE(?, name),
        category = COALESCE(?, category),
        subcategory = COALESCE(?, subcategory),
        available_qty = COALESCE(?, available_qty),
        description = COALESCE(?, description),
        status = COALESCE(?, status),
        price_slabs = COALESCE(?, price_slabs),
        attributes = COALESCE(?, attributes),
        selected_attribute_values = COALESCE(?, selected_attribute_values),
        variations = COALESCE(?, variations),
        sizes = COALESCE(?, sizes),
        images = ?,
        stock_mode = COALESCE(?, stock_mode),
        stock_by_color_size = COALESCE(?, stock_by_color_size)`;

    const updateParams = [
      name,
      category,
      subcategory,
      available_qty,
      description,
      status,
      price_slabs,
      attributes,
      selected_attribute_values,
      processedVariations,
      sizes,
      images,
      stock_mode,
      stockByColorSizeJson,
    ];

    // FIX: Add stock to update if column exists
    if (hasStockColumn) {
      updateQuery += `, stock = ?`;
      updateParams.push(totalStock);
    }

    // FIX: Add price to update if column exists
    if (hasPriceColumn) {
      updateQuery += `, price = ?`;
      updateParams.push(basePrice || 0);
    }

    // FIX: Add original_price to update if column exists
    if (hasOriginalPriceColumn && original_price !== undefined) {
      updateQuery += `, original_price = ?`;
      updateParams.push(original_price || basePrice || 0);
    }

    if (hasMarketplaceColumn && marketplace_enabled !== undefined) {
      updateQuery += `, marketplace_enabled = COALESCE(?, marketplace_enabled)`;
      updateParams.push(marketplace_enabled ? 1 : 0);
    }

    updateQuery += `, updated_at = NOW()
      WHERE id = ? AND user_id = ?`;
    updateParams.push(product_id, user_id);

    const [result] = await connection.execute(updateQuery, updateParams);

    if (result.affectedRows === 0) {
      await connection.rollback();
      return res.status(404).json({
        success: false,
        message: "Product not found or unauthorized",
      });
    }

    // ==================== UPDATE ATTRIBUTES IN 3 TABLES ====================

    // Parse attributes
    let attributesJson = {};
    let selectedAttributesJson = {};

    try {
      attributesJson = JSON.parse(attributes || "{}");
    } catch (e) {
      attributesJson = {};
    }

    try {
      selectedAttributesJson = JSON.parse(selected_attribute_values || "{}");
    } catch (e) {
      selectedAttributesJson = {};
    }

    console.log(`?? Updating attributes for product ${product_id} in 3 tables...`);

    // Update product_attributes_master and tbl_product_attributes
    if (attributesJson && typeof attributesJson === 'object' && Object.keys(attributesJson).length > 0) {
      for (const [attributeName, attributeValues] of Object.entries(attributesJson)) {
        // Check if this attribute already exists in master for this seller
        const [existingMasterAttr] = await connection.execute(
          `SELECT id FROM product_attributes_master
           WHERE seller_id = ? AND attributes_name = ?`,
          [user_id, attributeName]
        );

        let masterAttrId;

        if (existingMasterAttr.length === 0) {
          // Insert new attribute into master
          const [insertResult] = await connection.execute(
            `INSERT INTO product_attributes_master
            (seller_id, attributes_name, status)
            VALUES (?, ?, 1)`,
            [user_id, attributeName]
          );
          masterAttrId = insertResult.insertId;
          console.log(`? Updated master table: ${attributeName}, ID: ${masterAttrId}`);
        } else {
          masterAttrId = existingMasterAttr[0].id;
        }

        // Update tbl_product_attributes
        const selectedValue = selectedAttributesJson[attributeName];

        if (selectedValue) {
          // Delete existing entry
          await connection.execute(
            `DELETE FROM tbl_product_attributes
             WHERE product_id = ? AND seller_id = ? AND attributes_name = ?`,
            [product_id, user_id, attributeName]
          );

          // Insert new entry
          await connection.execute(
            `INSERT INTO tbl_product_attributes
            (product_id, seller_id, attributes_id, attributes_name, status, created_at)
            VALUES (?, ?, ?, ?, 1, NOW())`,
            [product_id, user_id, masterAttrId, attributeName]
          );
        }
      }
    }

    // Update tbl_product_range_prices
    if (priceSlabsArray && Array.isArray(priceSlabsArray) && priceSlabsArray.length > 0) {
      // Delete existing price slabs
      await connection.execute(
        `DELETE FROM tbl_product_range_prices
         WHERE product_id = ? AND seller_id = ?`,
        [product_id, user_id]
      );

      // Insert new price slabs
      for (const slab of priceSlabsArray) {
        if (slab.moq || slab.min_qty) {
          const minQty = slab.moq || slab.min_qty || 1;
          const price = slab.price || 0;

          await connection.execute(
            `INSERT INTO tbl_product_range_prices
            (product_id, seller_id, min_qty, price, status, created_at)
            VALUES (?, ?, ?, ?, 1, NOW())`,
            [product_id, user_id, minQty, price]
          );
        }
      }
    }

    // ALSO UPDATE OTHER RELATED TABLES
    let imagesArray = [];
    try {
      imagesArray = JSON.parse(images || "[]");
    } catch (e) {
      imagesArray = [];
    }

    // Update product_colors - FIX: Price aur Stock save karo
    await connection.execute('DELETE FROM product_colors WHERE product_id = ?', [product_id]);
    for (const variant of variationsArray) {
      if (variant.name) {
        // FIX: Handle stock value - ALWAYS save stock
        let finalStock = 0;

        if (stock_mode === "color_size" && stockData[variant.name]) {
          // If stock_by_color_size has data for this color, calculate total
          const sizesObj = stockData[variant.name] || {};
          finalStock = Object.values(sizesObj).reduce((sum, qty) => sum + (parseInt(qty) || 0), 0);
        } else if (variant.stock) {
          // Otherwise use variant stock
          if (typeof variant.stock === 'object' && variant.stock !== null) {
            // If stock is JSON object
            finalStock = Object.values(variant.stock).reduce((sum, qty) => sum + (parseInt(qty) || 0), 0);
          } else {
            // If stock is integer or string
            finalStock = parseInt(variant.stock) || parseInt(variant.totalStock) || 0;
          }
        }

        // FIX: Get price from variant or use base price
        const variantPrice = variant.price || basePrice || 0;

        await connection.execute(
          `INSERT INTO product_colors (product_id, color_name, image_url, price, stock)
           VALUES (?, ?, ?, ?, ?)`,
          [product_id, variant.name, variant.image || null, variantPrice, finalStock]
        );
        console.log(`? Updated product_colors: ${variant.name}, Price: ${variantPrice}, Stock: ${finalStock}`);
      }
    }

    // Update product_sizes - FIX: Price aur Stock save karo (STOCK FIX)
    await connection.execute('DELETE FROM product_sizes WHERE product_id = ?', [product_id]);

    // Calculate size-wise stock
    const sizeStockMap = {};
    if (stock_mode === 'color_size' && Object.keys(stockData).length > 0) {
      for (const colorName in stockData) {
        if (stockData.hasOwnProperty(colorName)) {
          const sizesObj = stockData[colorName];
          for (const size in sizesObj) {
            if (sizesObj.hasOwnProperty(size)) {
              if (!sizeStockMap[size]) {
                sizeStockMap[size] = 0;
              }
              sizeStockMap[size] += parseInt(sizesObj[size]) || 0;
            }
          }
        }
      }
    } else if (variationsArray.length > 0) {
      // Calculate from variations if no stock_by_color_size
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

    for (const size of sizesArray) {
      // FIX: Get stock for this size
      const sizeStock = sizeStockMap[size] || 0;

      // FIX: Use base price for size
      await connection.execute(
        `INSERT INTO product_sizes (product_id, size, price, stock)
         VALUES (?, ?, ?, ?)`,
        [product_id, size, basePrice || 0, sizeStock]
      );
      console.log(`? Updated product_sizes: ${size}, Price: ${basePrice || 0}, Stock: ${sizeStock}`);
    }

    // Update product_images
    await connection.execute('DELETE FROM product_images WHERE product_id = ?', [product_id]);
    for (const imageUrl of imagesArray) {
      await connection.execute(
        `INSERT INTO product_images (product_id, image_url)
         VALUES (?, ?)`,
        [product_id, imageUrl]
      );
    }

    // Update product_variants - FIX: Price aur Stock save karo (STOCK FIX)
    await connection.execute('DELETE FROM product_variants WHERE product_id = ?', [product_id]);

    // Save variants if we have both variations and sizes
    if (variationsArray.length > 0 && sizesArray.length > 0) {
      console.log(`? Updating variants for product ${product_id}`);

      // Method 1: If stock_by_color_size has specific data
      if (stock_mode === 'color_size' && Object.keys(stockData).length > 0) {
        console.log("Using stock_by_color_size for variant stock");

        for (const [colorName, sizesObj] of Object.entries(stockData)) {
          const colorVariant = variationsArray.find(v => v.name === colorName);
          // FIX: Get price from variant or use base price
          const variantPrice = colorVariant?.price || basePrice || 0;

          for (const [size, qty] of Object.entries(sizesObj)) {
            await connection.execute(
              `INSERT INTO product_variants
              (product_id, color_name, size, stock, price)
              VALUES (?, ?, ?, ?, ?)`,
              [product_id, colorName, size, parseInt(qty) || 0, variantPrice]
            );
            console.log(`? Updated variant: ${colorName}-${size}, Price: ${variantPrice}, Stock: ${qty}`);
          }
        }
      } else if (variationsArray.length > 0 && sizesArray.length > 0) {
        // Method 2: Generate all color-size combinations from variations data
        console.log("Generating all color-size combinations from variations");

        for (const variant of variationsArray) {
          const colorName = variant.name;
          if (!colorName) continue;

          // FIX: Get price from variant or use base price
          const variantPrice = variant.price || basePrice || 0;

          // Check if variant has size-wise stock
          if (variant.stock && typeof variant.stock === 'object') {
            // If stock is JSON object like {"L":10, "M":20}
            for (const size in variant.stock) {
              if (sizesArray.includes(size)) {
                const sizeStock = parseInt(variant.stock[size]) || 0;
                await connection.execute(
                  `INSERT INTO product_variants
                  (product_id, color_name, size, stock, price)
                  VALUES (?, ?, ?, ?, ?)`,
                  [product_id, colorName, size, sizeStock, variantPrice]
                );
                console.log(`? Updated variant from object: ${colorName}-${size}, Price: ${variantPrice}, Stock: ${sizeStock}`);
              }
            }
          } else {
            // If stock is single value, distribute evenly or use 0
            const variantStock = parseInt(variant.stock) || parseInt(variant.totalStock) || 0;
            const stockPerSize = Math.floor(variantStock / sizesArray.length) || 0;

            for (const size of sizesArray) {
              await connection.execute(
                `INSERT INTO product_variants
                (product_id, color_name, size, stock, price)
                VALUES (?, ?, ?, ?, ?)`,
                [product_id, colorName, size, stockPerSize, variantPrice]
              );
              console.log(`? Updated variant from total: ${colorName}-${size}, Price: ${variantPrice}, Stock: ${stockPerSize}`);
            }
          }
        }
      }
    } else {
      console.log(`? NOT updating variants for product ${product_id}:`);
      if (variationsArray.length === 0) console.log("- No variations");
      if (sizesArray.length === 0) console.log("- No sizes");
    }

    await connection.commit();

    console.log(`? Product ${product_id} updated successfully in all tables`);
    console.log(`? Stock updated in products table: ${totalStock}`);
    console.log(`? Price updated in products table: ${basePrice}`);

    res.json({
      success: true,
      message: "Product updated successfully in all tables including 3 attributes tables",
      data: {
        product_id: product_id,
        stock: totalStock,
        price: basePrice
      },
    });
  } catch (error) {
    await connection.rollback();
    console.error("Error updating product:", error);
    res.status(500).json({
      success: false,
      message: "Error updating product",
      error: error.message,
    });
  } finally {
    connection.release();
  }
});

/**
 * POST /api/products/delete
 * Delete a product - WITH ATTRIBUTES FROM 3 TABLES
 */
router.post("/delete", async (req, res) => {
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();

    const { user_id, product_id } = req.body;

    if (!user_id || !product_id) {
      await connection.rollback();
      return res.status(400).json({
        success: false,
        message: "user_id and product_id are required",
      });
    }

    // Get product images before deleting
    const [product] = await connection.execute(
      "SELECT images FROM products WHERE id = ? AND user_id = ?",
      [product_id, user_id]
    );

    if (product.length === 0) {
      await connection.rollback();
      return res.status(404).json({
        success: false,
        message: "Product not found or unauthorized",
      });
    }

    // Delete from ALL related tables first
    // 1. Delete from 3 attributes tables
    await connection.execute('DELETE FROM tbl_product_attributes WHERE product_id = ? AND seller_id = ?', [product_id, user_id]);
    await connection.execute('DELETE FROM tbl_product_range_prices WHERE product_id = ? AND seller_id = ?', [product_id, user_id]);
    // Note: Don't delete from product_attributes_master as it's shared with other products

    // 2. Delete from other tables
    await connection.execute('DELETE FROM product_colors WHERE product_id = ?', [product_id]);
    await connection.execute('DELETE FROM product_sizes WHERE product_id = ?', [product_id]);
    await connection.execute('DELETE FROM product_images WHERE product_id = ?', [product_id]);
    await connection.execute('DELETE FROM product_variants WHERE product_id = ?', [product_id]);
    await connection.execute('DELETE FROM product_reviews WHERE product_id = ?', [product_id]);
    await connection.execute('DELETE FROM recently_viewed WHERE product_id = ?', [product_id]);

    // 3. Delete product itself
    const [result] = await connection.execute(
      "DELETE FROM products WHERE id = ? AND user_id = ?",
      [product_id, user_id]
    );

    if (result.affectedRows === 0) {
      await connection.rollback();
      return res.status(404).json({
        success: false,
        message: "Product not found or unauthorized",
      });
    }

    // Optionally delete image files
    try {
      const images = JSON.parse(product[0].images || "[]");
      for (const imageUrl of images) {
        const filename = path.basename(imageUrl);
        const filePath = path.join(PRODUCT_UPLOAD_DIR, filename);
        if (fs.existsSync(filePath)) {
          fs.unlinkSync(filePath);
        }
      }
    } catch (e) {
      console.error("Error deleting image files:", e);
      // Continue even if image deletion fails
    }

    await connection.commit();

    res.json({
      success: true,
      message: "Product deleted successfully from all tables including 3 attributes tables",
    });
  } catch (error) {
    await connection.rollback();
    console.error("Error deleting product:", error);
    res.status(500).json({
      success: false,
      message: "Error deleting product",
      error: error.message,
    });
  } finally {
    connection.release();
  }
});

module.exports = router;