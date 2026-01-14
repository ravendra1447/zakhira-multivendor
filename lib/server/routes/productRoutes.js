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
 * Save or update a product (draft or publish) - FIXED STOCK ISSUE
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

    // FIXED: If stock_mode is color_size, ensure variations have CORRECT stock data
    if (stock_mode === "color_size" && stock_by_color_size) {
      processedVariations = processedVariations.map((variation) => {
        const colorName = variation.name || variation.color;
        if (stockData[colorName]) {
          // FIX: Calculate total stock from size-wise stock
          const sizeStockObj = stockData[colorName];
          const totalStock = Object.values(sizeStockObj).reduce(
            (sum, qty) => sum + (parseInt(qty) || 0),
            0
          );
          variation.stock = totalStock; // ✅ Integer value, not JSON object
          variation.totalStock = totalStock;
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

    // 2. SAVE TO RELATED TABLES
    // ==========================

    // 2.1. product_colors table - FIXED STOCK ISSUE
    // Clear existing colors
    await connection.execute(
      'DELETE FROM product_colors WHERE product_id = ?',
      [finalProductId]
    );

    // Insert new colors from variations
    for (const variant of processedVariations) {
      if (variant.name) {
        // FIX: Handle stock value (could be integer or JSON object)
        let stockValue = variant.stock || variant.totalStock || 0;
        let finalStock = 0;

        if (typeof stockValue === 'object' && stockValue !== null) {
          // If stock is JSON object like {"L":50,"XXL":50,"M":50}
          finalStock = Object.values(stockValue).reduce((sum, qty) => sum + (parseInt(qty) || 0), 0);
        } else {
          // If stock is already integer or string
          finalStock = parseInt(stockValue) || 0;
        }

        await connection.execute(
          `INSERT INTO product_colors
          (product_id, color_name, image_url, price, stock)
          VALUES (?, ?, ?, ?, ?)`,
          [
            finalProductId,
            variant.name,
            variant.image || null,
            variant.price || 0,
            finalStock  // ✅ Integer value
          ]
        );
      }
    }

    // 2.2. product_sizes table
    // Clear existing sizes
    await connection.execute(
      'DELETE FROM product_sizes WHERE product_id = ?',
      [finalProductId]
    );

    // Insert new sizes
    for (const size of processedSizes) {
      await connection.execute(
        `INSERT INTO product_sizes
        (product_id, size, price, stock)
        VALUES (?, ?, ?, ?)`,
        [finalProductId, size, 0, 0]
      );
    }

    // 2.3. product_images table
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

    // 2.4. product_variants table - FIXED: ALWAYS SAVE VARIANTS
    // Clear existing variants
    await connection.execute(
      'DELETE FROM product_variants WHERE product_id = ?',
      [finalProductId]
    );

    // Save variants if we have both variations and sizes
    if (processedVariations.length > 0 && processedSizes.length > 0) {
      console.log("✅ Saving variants to product_variants table");

      // Method 1: If stock_by_color_size has specific data
      if (stock_mode === 'color_size' && Object.keys(stockData).length > 0) {
        console.log("Using stock_by_color_size for variant stock");

        for (const [colorName, sizesObj] of Object.entries(stockData)) {
          const colorVariant = processedVariations.find(v => v.name === colorName);
          const basePrice = colorVariant?.price || 0;

          for (const [size, qty] of Object.entries(sizesObj)) {
            await connection.execute(
              `INSERT INTO product_variants
              (product_id, color_name, size, stock, price)
              VALUES (?, ?, ?, ?, ?)`,
              [finalProductId, colorName, size, parseInt(qty) || 0, basePrice]
            );
          }
        }
      } else {
        // Method 2: Generate all color-size combinations
        console.log("Generating all color-size combinations");

        for (const variant of processedVariations) {
          const colorName = variant.name;
          if (!colorName) continue;

          // FIX: Calculate stock for variant
          let variantStock = 0;
          if (typeof variant.stock === 'object' && variant.stock !== null) {
            // If stock is JSON object
            variantStock = Object.values(variant.stock).reduce((sum, qty) => sum + (parseInt(qty) || 0), 0);
          } else {
            // If stock is integer
            variantStock = parseInt(variant.stock) || parseInt(variant.totalStock) || 0;
          }

          const variantPrice = variant.price || 0;

          for (const size of processedSizes) {
            await connection.execute(
              `INSERT INTO product_variants
              (product_id, color_name, size, stock, price)
              VALUES (?, ?, ?, ?, ?)`,
              [finalProductId, colorName, size, variantStock, variantPrice]
            );
          }
        }
      }
    } else {
      console.log("❌ NOT saving variants - missing data:");
      if (processedVariations.length === 0) console.log("- No variations");
      if (processedSizes.length === 0) console.log("- No sizes");
    }

    // Commit transaction
    await connection.commit();

    console.log(`✅ Product ${finalProductId} saved successfully to all tables`);

    return res.json({
      success: true,
      message: product_id ? "Product updated successfully" : "Product saved successfully",
      data: { product_id: finalProductId },
    });

  } catch (error) {
    await connection.rollback();
    console.error("❌ Error saving product:", error);
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
      console.log("🔍 Products list query:", query);
      console.log("🔍 Products list params:", params);
      console.log("🔍 Params count:", params.length);
      const placeholderCount = (query.match(/\?/g) || []).length;
      console.log("🔍 Placeholders in query:", placeholderCount);
      
      // Validate params count matches placeholders
      if (params.length !== placeholderCount) {
        console.error("❌ Parameter mismatch! Params:", params.length, "Placeholders:", placeholderCount);
        throw new Error(`Parameter count mismatch: ${params.length} params but ${placeholderCount} placeholders`);
      }
      
      let rows;
      try {
        [rows] = await connection.execute(query, params);
      } catch (queryError) {
        // If error is about marketplace_enabled column, retry without it
        if (queryError.message.includes('marketplace_enabled') && hasMarketplaceColumn) {
          console.log("⚠️ Retrying query without marketplace_enabled filter");
          // Remove marketplace_enabled condition and retry
          query = query.replace(" AND marketplace_enabled = 1", "");
          [rows] = await connection.execute(query, params);
        } else {
          console.error("❌ Query error:", queryError.message);
          console.error("❌ Query:", query);
          console.error("❌ Params:", params);
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

      // Get related data from all tables
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
 * Update an existing product - FIXED STOCK ISSUE
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
      "SELECT images, variations FROM products WHERE id = ? AND user_id = ?",
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

      // If stock_mode is color_size, ensure variations have CORRECT stock data
      if (stock_mode === "color_size" && stock_by_color_size) {
        let stockData = {};
        try {
          stockData = JSON.parse(stock_by_color_size);
        } catch (e) {
          stockData = {};
        }

        // Update variations with correct stock data
        variationsArray = variationsArray.map((variation) => {
          const colorName = variation.name || variation.color;
          if (stockData[colorName]) {
            // FIX: Calculate total stock from size-wise stock
            const sizeStockObj = stockData[colorName];
            const totalStock = Object.values(sizeStockObj).reduce(
              (sum, qty) => sum + (parseInt(qty) || 0),
              0
            );
            variation.stock = totalStock; // ✅ Integer value
            variation.totalStock = totalStock;
          }
          return variation;
        });

        processedVariations = JSON.stringify(variationsArray);
      }
    }

    // Prepare stock_by_color_size for database (JSON column)
    const stockByColorSizeJson = stock_mode === "color_size" && stock_by_color_size
      ? (typeof stock_by_color_size === "string" ? stock_by_color_size : JSON.stringify(stock_by_color_size))
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

    // ALSO UPDATE RELATED TABLES
    // Parse data for related tables
    let sizesArray = [];
    let imagesArray = [];
    let stockData = {};

    try {
      sizesArray = JSON.parse(sizes || "[]");
    } catch (e) {
      sizesArray = [];
    }

    try {
      imagesArray = JSON.parse(images || "[]");
    } catch (e) {
      imagesArray = [];
    }

    if (stock_by_color_size) {
      try {
        stockData = JSON.parse(stock_by_color_size);
      } catch (e) {
        stockData = {};
      }
    }

    // Update product_colors - FIXED STOCK ISSUE
    await connection.execute('DELETE FROM product_colors WHERE product_id = ?', [product_id]);
    for (const variant of variationsArray) {
      if (variant.name) {
        // FIX: Handle stock value
        let stockValue = variant.stock || variant.totalStock || 0;
        let finalStock = 0;

        if (typeof stockValue === 'object' && stockValue !== null) {
          // If stock is JSON object
          finalStock = Object.values(stockValue).reduce((sum, qty) => sum + (parseInt(qty) || 0), 0);
        } else {
          // If stock is integer or string
          finalStock = parseInt(stockValue) || 0;
        }

        await connection.execute(
          `INSERT INTO product_colors (product_id, color_name, image_url, price, stock)
           VALUES (?, ?, ?, ?, ?)`,
          [product_id, variant.name, variant.image || null, variant.price || 0, finalStock]
        );
      }
    }

    // Update product_sizes
    await connection.execute('DELETE FROM product_sizes WHERE product_id = ?', [product_id]);
    for (const size of sizesArray) {
      await connection.execute(
        `INSERT INTO product_sizes (product_id, size, price, stock)
         VALUES (?, ?, ?, ?)`,
        [product_id, size, 0, 0]
      );
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

    // Update product_variants - FIXED: ALWAYS SAVE
    await connection.execute('DELETE FROM product_variants WHERE product_id = ?', [product_id]);

    // Save variants if we have both variations and sizes
    if (variationsArray.length > 0 && sizesArray.length > 0) {
      console.log(`✅ Updating variants for product ${product_id}`);

      // Method 1: If stock_by_color_size has specific data
      if (stock_mode === 'color_size' && Object.keys(stockData).length > 0) {
        console.log("Using stock_by_color_size for variant stock");

        for (const [colorName, sizesObj] of Object.entries(stockData)) {
          const colorVariant = variationsArray.find(v => v.name === colorName);
          const basePrice = colorVariant?.price || 0;

          for (const [size, qty] of Object.entries(sizesObj)) {
            await connection.execute(
              `INSERT INTO product_variants
              (product_id, color_name, size, stock, price)
              VALUES (?, ?, ?, ?, ?)`,
              [product_id, colorName, size, parseInt(qty) || 0, basePrice]
            );
          }
        }
      } else {
        // Method 2: Generate all color-size combinations
        console.log("Generating all color-size combinations");

        for (const variant of variationsArray) {
          const colorName = variant.name;
          if (!colorName) continue;

          // FIX: Calculate stock for variant
          let variantStock = 0;
          if (typeof variant.stock === 'object' && variant.stock !== null) {
            // If stock is JSON object
            variantStock = Object.values(variant.stock).reduce((sum, qty) => sum + (parseInt(qty) || 0), 0);
          } else {
            // If stock is integer
            variantStock = parseInt(variant.stock) || parseInt(variant.totalStock) || 0;
          }

          const variantPrice = variant.price || 0;

          for (const size of sizesArray) {
            await connection.execute(
              `INSERT INTO product_variants
              (product_id, color_name, size, stock, price)
              VALUES (?, ?, ?, ?, ?)`,
              [product_id, colorName, size, variantStock, variantPrice]
            );
          }
        }
      }
    } else {
      console.log(`❌ NOT updating variants for product ${product_id}:`);
      if (variationsArray.length === 0) console.log("- No variations");
      if (sizesArray.length === 0) console.log("- No sizes");
    }

    await connection.commit();

    res.json({
      success: true,
      message: "Product updated successfully",
      data: { product_id: product_id },
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
 * Delete a product
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

    // Delete from all related tables first
    await connection.execute('DELETE FROM product_colors WHERE product_id = ?', [product_id]);
    await connection.execute('DELETE FROM product_sizes WHERE product_id = ?', [product_id]);
    await connection.execute('DELETE FROM product_images WHERE product_id = ?', [product_id]);
    await connection.execute('DELETE FROM product_variants WHERE product_id = ?', [product_id]);
    await connection.execute('DELETE FROM product_reviews WHERE product_id = ?', [product_id]);
    await connection.execute('DELETE FROM recently_viewed WHERE product_id = ?', [product_id]);

    // Delete product
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
      message: "Product deleted successfully",
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