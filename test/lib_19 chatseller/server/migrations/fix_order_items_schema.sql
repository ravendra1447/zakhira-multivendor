-- Fix order_items table schema
-- Add missing columns if they don't exist

-- Add product_name column if it doesn't exist
ALTER TABLE order_items 
ADD COLUMN IF NOT EXISTS product_name VARCHAR(255) AFTER color;

-- Add product_price column if it doesn't exist  
ALTER TABLE order_items 
ADD COLUMN IF NOT EXISTS product_price DECIMAL(10,2) AFTER product_name;
