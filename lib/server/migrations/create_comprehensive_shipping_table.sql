-- Create comprehensive shipping rates table linked with products and users
CREATE TABLE IF NOT EXISTS shipping_rates (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL DEFAULT 'Standard Delivery',
  description TEXT,
  
  -- Rate configuration
  rate DECIMAL(10, 2) NOT NULL DEFAULT 250.00,
  rate_type ENUM('fixed', 'percentage') DEFAULT 'fixed',
  
  -- Link with products (optional - if null, applies to all products)
  product_id INT NULL,
  category_id INT NULL,
  
  -- Link with users (optional - if null, applies to all users)
  user_id INT NULL,
  user_type ENUM('all', 'regular', 'premium', 'wholesale') DEFAULT 'all',
  
  -- Order amount conditions
  min_order_amount DECIMAL(10, 2) DEFAULT 0.00,
  max_order_amount DECIMAL(10, 2) DEFAULT NULL,
  
  -- Geographic conditions (optional)
  city VARCHAR(100) NULL,
  state VARCHAR(100) NULL,
  pincode VARCHAR(10) NULL,
  
  -- Status and timestamps
  is_active BOOLEAN DEFAULT TRUE,
  priority INT DEFAULT 0, -- Higher priority rates are applied first
  
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  
  -- Foreign key constraints
  FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  
  -- Indexes for better performance
  INDEX idx_product_id (product_id),
  INDEX idx_user_id (user_id),
  INDEX idx_is_active (is_active),
  INDEX idx_priority (priority),
  INDEX idx_rate_range (min_order_amount, max_order_amount),
  INDEX idx_geographic (city, state, pincode),
  INDEX idx_user_type (user_type)
);

-- Insert default shipping rates
-- 1. Default rate for all products and all users
INSERT INTO shipping_rates (name, description, rate, rate_type, is_active, priority) 
VALUES ('Standard Delivery', 'Standard delivery charge for all orders', 250.00, 'fixed', TRUE, 1)
ON DUPLICATE KEY UPDATE rate = 250.00;

-- 2. Free delivery for orders above ₹2000
INSERT INTO shipping_rates (name, description, rate, rate_type, min_order_amount, is_active, priority) 
VALUES ('Free Delivery', 'Free delivery for orders above ₹2000', 0.00, 'fixed', 2000.00, TRUE, 2)
ON DUPLICATE KEY UPDATE rate = 0.00;

-- 3. Example: Higher rate for specific product (you can modify product_id)
-- INSERT INTO shipping_rates (name, description, rate, product_id, is_active, priority) 
-- VALUES ('Special Product Delivery', 'Higher delivery for special products', 350.00, 1, TRUE, 3);

-- 4. Example: Wholesale user rates
-- INSERT INTO shipping_rates (name, description, rate, user_type, is_active, priority) 
-- VALUES ('Wholesale Delivery', 'Special rates for wholesale customers', 150.00, 'wholesale', TRUE, 4);
