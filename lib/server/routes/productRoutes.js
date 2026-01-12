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
 * Save or update a product (draft or publish)
 */
router.post("/save", async (req, res) => {
  try {
    const {
      user_id,
      name,
      category,
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
    } = req.body;

    // Validation
    if (!user_id || !name || !status) {
      return res.status(400).json({
        success: false,
        message: "Missing required fields: user_id, name, status",
      });
    }

    if (!["draft", "publish"].includes(status)) {
      return res.status(400).json({
        success: false,
        message: "Status must be 'draft' or 'publish'",
      });
    }

    // Process variations to ensure stock data is included
    let processedVariations = variations || "[]";
    if (typeof processedVariations === "string") {
      try {
        processedVariations = JSON.parse(processedVariations);
      } catch (e) {
        processedVariations = [];
      }
    }

    // If stock_mode is color_size, ensure variations have stock data
    if (stock_mode === "color_size" && stock_by_color_size) {
      const stockData = typeof stock_by_color_size === "string" 
        ? JSON.parse(stock_by_color_size) 
        : stock_by_color_size;
      
      // Update variations with stock data
      processedVariations = processedVariations.map((variation) => {
        const colorName = variation.name || variation.color;
        if (stockData[colorName]) {
          variation.stock = stockData[colorName];
          // Calculate total stock for this color
          const totalStock = Object.values(stockData[colorName]).reduce(
            (sum, qty) => sum + (parseInt(qty) || 0),
            0
          );
          variation.totalStock = totalStock;
        }
        return variation;
      });
    }

    // Prepare stock_by_color_size for database (JSON column)
    const stockByColorSizeJson = stock_mode === "color_size" && stock_by_color_size
      ? (typeof stock_by_color_size === "string" ? stock_by_color_size : JSON.stringify(stock_by_color_size))
      : null;

    const connection = await pool.getConnection();

    try {
      if (product_id) {
        // Update existing product
        const [result] = await connection.execute(
          `UPDATE products SET
            name = ?,
            category = ?,
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
            stock_by_color_size = ?,
            updated_at = NOW()
          WHERE id = ? AND user_id = ?`,
          [
            name,
            category || null,
            available_qty || "0",
            description || null,
            status,
            price_slabs || "[]",
            attributes || "{}",
            selected_attribute_values || "{}",
            JSON.stringify(processedVariations),
            sizes || "[]",
            images || "[]",
            stock_mode || "simple",
            stockByColorSizeJson,
            product_id,
            user_id,
          ]
        );

        if (result.affectedRows === 0) {
          return res.status(404).json({
            success: false,
            message: "Product not found or unauthorized",
          });
        }

        return res.json({
          success: true,
          message: "Product updated successfully",
          data: { product_id: product_id },
        });
      } else {
        // Insert new product
        const [result] = await connection.execute(
          `INSERT INTO products (
            user_id, name, category, available_qty, description, status,
            price_slabs, attributes, selected_attribute_values,
            variations, sizes, images, stock_mode, stock_by_color_size,
            created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())`,
          [
            user_id,
            name,
            category || null,
            available_qty || "0",
            description || null,
            status,
            price_slabs || "[]",
            attributes || "{}",
            selected_attribute_values || "{}",
            JSON.stringify(processedVariations),
            sizes || "[]",
            images || "[]",
            stock_mode || "simple",
            stockByColorSizeJson,
          ]
        );

        return res.json({
          success: true,
          message: "Product saved successfully",
          data: { product_id: result.insertId },
        });
      }
    } finally {
      connection.release();
    }
  } catch (error) {
    console.error("Error saving product:", error);
    res.status(500).json({
      success: false,
      message: "Internal server error",
      error: error.message,
    });
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
 * Get all products for a user
 */
router.post("/list", async (req, res) => {
  try {
    const { user_id, status, limit = 20, offset = 0 } = req.body;

    if (!user_id) {
      return res.status(400).json({
        success: false,
        message: "user_id is required",
      });
    }

    const connection = await pool.getConnection();

    try {
      let query = "SELECT * FROM products WHERE user_id = ?";
      const params = [user_id];

      if (status) {
        query += " AND status = ?";
        params.push(status);
      }

      query += " ORDER BY updated_at DESC LIMIT ? OFFSET ?";
      params.push(parseInt(limit), parseInt(offset));

      const [rows] = await connection.execute(query, params);

      // Get total count
      let countQuery =
        "SELECT COUNT(*) as total FROM products WHERE user_id = ?";
      const countParams = [user_id];
      if (status) {
        countQuery += " AND status = ?";
        countParams.push(status);
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
 * POST /api/products/update
 * Update an existing product
 */
router.post("/update", async (req, res) => {
  try {
    const {
      user_id,
      product_id,
      name,
      category,
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
    } = req.body;

    if (!user_id || !product_id) {
      return res.status(400).json({
        success: false,
        message: "user_id and product_id are required",
      });
    }

    const connection = await pool.getConnection();

    try {
      // Get existing product to merge images
      const [existing] = await connection.execute(
        "SELECT images, variations FROM products WHERE id = ? AND user_id = ?",
        [product_id, user_id]
      );

      if (existing.length === 0) {
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
      if (variations !== undefined) {
        if (typeof processedVariations === "string") {
          try {
            processedVariations = JSON.parse(processedVariations);
          } catch (e) {
            processedVariations = [];
          }
        }

        // If stock_mode is color_size, ensure variations have stock data
        if (stock_mode === "color_size" && stock_by_color_size) {
          const stockData = typeof stock_by_color_size === "string" 
            ? JSON.parse(stock_by_color_size) 
            : stock_by_color_size;
          
          // Update variations with stock data
          processedVariations = processedVariations.map((variation) => {
            const colorName = variation.name || variation.color;
            if (stockData[colorName]) {
              variation.stock = stockData[colorName];
              // Calculate total stock for this color
              const totalStock = Object.values(stockData[colorName]).reduce(
                (sum, qty) => sum + (parseInt(qty) || 0),
                0
              );
              variation.totalStock = totalStock;
            }
            return variation;
          });
        }

        processedVariations = JSON.stringify(processedVariations);
      }

      // Prepare stock_by_color_size for database (JSON column)
      const stockByColorSizeJson = stock_mode === "color_size" && stock_by_color_size
        ? (typeof stock_by_color_size === "string" ? stock_by_color_size : JSON.stringify(stock_by_color_size))
        : null;

      const [result] = await connection.execute(
        `UPDATE products SET
          name = COALESCE(?, name),
          category = COALESCE(?, category),
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
          stock_by_color_size = COALESCE(?, stock_by_color_size),
          updated_at = NOW()
        WHERE id = ? AND user_id = ?`,
        [
          name,
          category,
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
          product_id,
          user_id,
        ]
      );

      if (result.affectedRows === 0) {
        return res.status(404).json({
          success: false,
          message: "Product not found or unauthorized",
        });
      }

      res.json({
        success: true,
        message: "Product updated successfully",
        data: { product_id: product_id },
      });
    } finally {
      connection.release();
    }
  } catch (error) {
    console.error("Error updating product:", error);
    res.status(500).json({
      success: false,
      message: "Error updating product",
      error: error.message,
    });
  }
});

/**
 * POST /api/products/delete
 * Delete a product
 */
router.post("/delete", async (req, res) => {
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
      // Get product images before deleting
      const [product] = await connection.execute(
        "SELECT images FROM products WHERE id = ? AND user_id = ?",
        [product_id, user_id]
      );

      if (product.length === 0) {
        return res.status(404).json({
          success: false,
          message: "Product not found or unauthorized",
        });
      }

      // Delete product
      const [result] = await connection.execute(
        "DELETE FROM products WHERE id = ? AND user_id = ?",
        [product_id, user_id]
      );

      if (result.affectedRows === 0) {
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

      res.json({
        success: true,
        message: "Product deleted successfully",
      });
    } finally {
      connection.release();
    }
  } catch (error) {
    console.error("Error deleting product:", error);
    res.status(500).json({
      success: false,
      message: "Error deleting product",
      error: error.message,
    });
  }
});

module.exports = router;
