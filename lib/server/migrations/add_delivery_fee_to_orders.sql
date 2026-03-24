-- Add delivery_fee column to orders table
ALTER TABLE orders 
ADD COLUMN delivery_fee DECIMAL(10, 2) DEFAULT 250.00 AFTER total_amount,
ADD COLUMN updated_delivery_fee BOOLEAN DEFAULT FALSE AFTER delivery_fee;

-- Update existing orders with default delivery fee
UPDATE orders SET delivery_fee = 250.00 WHERE delivery_fee IS NULL;

-- Add index for better performance
CREATE INDEX idx_delivery_fee ON orders(delivery_fee);
CREATE INDEX idx_updated_delivery_fee ON orders(updated_delivery_fee);
