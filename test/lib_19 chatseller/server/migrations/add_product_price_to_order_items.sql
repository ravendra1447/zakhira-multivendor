-- Add product_price column to order_items table
ALTER TABLE order_items ADD COLUMN product_price DECIMAL(10,2) AFTER price;
