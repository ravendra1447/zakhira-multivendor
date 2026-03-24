-- Create shipping_rates table for managing delivery charges
CREATE TABLE IF NOT EXISTS shipping_rates (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL DEFAULT 'Standard Delivery',
  description TEXT,
  rate DECIMAL(10, 2) NOT NULL DEFAULT 250.00,
  is_active BOOLEAN DEFAULT TRUE,
  min_order_amount DECIMAL(10, 2) DEFAULT 0.00,
  max_order_amount DECIMAL(10, 2) DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_is_active (is_active),
  INDEX idx_rate_range (min_order_amount, max_order_amount)
);

-- Insert default shipping rate
INSERT INTO shipping_rates (name, description, rate, is_active) 
VALUES ('Standard Delivery', 'Standard delivery charge for all orders', 250.00, TRUE)
ON DUPLICATE KEY UPDATE rate = 250.00;
