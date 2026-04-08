-- Migration: Add manual_stock_quantity field to order_items table
-- Run this SQL on your MySQL database

ALTER TABLE order_items 
ADD COLUMN manual_stock_quantity INT DEFAULT NULL COMMENT 'Manually set available quantity by admin',
ADD COLUMN use_manual_stock BOOLEAN DEFAULT FALSE COMMENT 'Whether to use manual stock quantity or automatic stock';

-- Update existing items to not use manual stock by default
UPDATE order_items SET use_manual_stock = FALSE WHERE use_manual_stock IS NULL;
