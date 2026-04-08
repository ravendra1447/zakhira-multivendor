-- Fix existing order items to be available by default
-- Run this SQL on your MySQL database to fix the issue

-- Update all existing order items to be available (0 = available)
UPDATE order_items SET availability_status = 0 WHERE availability_status = 1;

-- Also update the default value for future orders
ALTER TABLE order_items ALTER COLUMN availability_status SET DEFAULT 0;
