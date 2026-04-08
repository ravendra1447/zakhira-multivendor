-- WhatsApp Chat Database Schema for Order Management

-- Update orders table with new status structure
ALTER TABLE orders 
MODIFY COLUMN order_status ENUM(
    'Pending',
    'Waiting for Payment',
    'Ready for Shipment',
    'Shipped',
    'Delivered',
    'Cancelled'
) DEFAULT 'Pending';

-- Add payment_status column if not exists
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS payment_status ENUM(
    'Pending',
    'Paid',
    'Failed'
) DEFAULT 'Pending';

-- Add payment_confirmed_at column for tracking
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS payment_confirmed_at TIMESTAMP NULL DEFAULT NULL;

-- Add updated_at column for tracking changes
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP;

-- Create order status log table for tracking changes
CREATE TABLE IF NOT EXISTS order_status_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id INT NOT NULL,
    old_status VARCHAR(50) NOT NULL,
    new_status VARCHAR(50) NOT NULL,
    changed_by VARCHAR(50) DEFAULT 'system',
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(order_status);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);
CREATE INDEX IF NOT EXISTS idx_orders_payment_status ON orders(payment_status);

-- Create order_status_log index
CREATE INDEX IF NOT EXISTS idx_order_status_log_order_id ON order_status_log(order_id);

-- Insert sample data for testing (optional)
-- INSERT INTO orders (user_id, total_amount, order_status, payment_status, customer_name, customer_phone, shipping_street, shipping_city, shipping_state, shipping_pincode, delivery_fee, created_at) 
-- VALUES 
-- (1, 1500.00, 'Pending', 'Pending', 'John Doe', '9876543210', '123 Main St', 'Mumbai', 'Maharashtra', '400001', 250.00, NOW());

-- Sample order items insertion
-- INSERT INTO order_items (order_id, product_name, price, quantity, color, size) 
-- VALUES 
-- (1, 'T-Shirt', 500.00, 2, 'Blue', 'L'),
-- (1, 'Jeans', 500.00, 1, 'Black', '32');
