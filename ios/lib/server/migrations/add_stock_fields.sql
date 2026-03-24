-- Migration: Add stock_mode and stock_by_color_size columns to products table
-- Run this SQL on your MySQL database

ALTER TABLE products 
ADD COLUMN stock_mode VARCHAR(20) DEFAULT 'simple' COMMENT 'Stock mode: simple or color_size',
ADD COLUMN stock_by_color_size JSON NULL COMMENT 'Stock data by color and size: {color: {size: qty}}';

-- Update existing products to have default stock_mode
UPDATE products SET stock_mode = 'simple' WHERE stock_mode IS NULL;


