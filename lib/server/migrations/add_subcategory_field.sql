-- Migration: Add subcategory column to products table
-- Run this SQL on your MySQL database

ALTER TABLE products 
ADD COLUMN subcategory VARCHAR(255) NULL COMMENT 'Product subcategory';

-- Update existing products to have NULL subcategory (optional)
-- UPDATE products SET subcategory = NULL WHERE subcategory IS NULL;





