-- Migration: Add availability_status column to order_items table
-- Run this SQL on your MySQL database

ALTER TABLE order_items 
ADD COLUMN availability_status TINYINT(1) DEFAULT 0 COMMENT 'Availability status: 0=available, 1=unavailable';

-- Update existing order_items to have default availability status (available by default)
UPDATE order_items SET availability_status = 0 WHERE availability_status IS NULL;
