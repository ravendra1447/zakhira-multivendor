-- Migration: Add available_quantity and stock_status fields to order_items table
-- Run this SQL on your MySQL database

ALTER TABLE order_items 
ADD COLUMN available_quantity INT DEFAULT 0 COMMENT 'Actual available quantity after stock check',
ADD COLUMN stock_status VARCHAR(20) DEFAULT 'full' COMMENT 'Stock status: full, partial, out_of_stock';

-- Update existing order_items to have default values
UPDATE order_items SET available_quantity = quantity WHERE available_quantity = 0;
UPDATE order_items SET stock_status = 'full' WHERE stock_status IS NULL;
