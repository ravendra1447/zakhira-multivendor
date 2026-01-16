-- Migration: Add marketplace_enabled column to products table
-- Run this SQL on your MySQL database

ALTER TABLE products 
ADD COLUMN marketplace_enabled TINYINT(1) DEFAULT 0 COMMENT 'Enable product in marketplace (0=disabled, 1=enabled)';

-- Update existing products to have default marketplace_enabled = 0
UPDATE products SET marketplace_enabled = 0 WHERE marketplace_enabled IS NULL;



