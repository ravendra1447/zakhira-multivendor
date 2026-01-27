-- Add website_id column to orders table
ALTER TABLE orders 
ADD COLUMN website_id INT NULL,
ADD INDEX idx_website_id (website_id);

-- Add foreign key constraint if websites table exists
-- ALTER TABLE orders 
-- ADD CONSTRAINT fk_orders_website 
-- FOREIGN KEY (website_id) REFERENCES websites(website_id) 
-- ON DELETE SET NULL;

-- Update existing orders to have a default website_id if needed
-- This is optional - you may want to set existing orders to a specific website or leave as NULL
-- UPDATE orders SET website_id = 1 WHERE website_id IS NULL;
