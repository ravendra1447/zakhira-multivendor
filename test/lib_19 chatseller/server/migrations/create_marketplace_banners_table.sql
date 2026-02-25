-- Create marketplace_banners table for dynamic banner management
CREATE TABLE IF NOT EXISTS marketplace_banners (
  id INT AUTO_INCREMENT PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  subtitle VARCHAR(255) NULL,
  description TEXT NULL,
  image_url VARCHAR(500) NOT NULL,
  background_color VARCHAR(20) DEFAULT '#FF6B35',
  text_color VARCHAR(20) DEFAULT '#FFFFFF',
  button_text VARCHAR(100) NULL,
  button_url VARCHAR(500) NULL,
  display_order INT DEFAULT 0,
  is_active BOOLEAN DEFAULT 1,
  start_date DATETIME NULL,
  end_date DATETIME NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_display_order (display_order),
  INDEX idx_is_active (is_active),
  INDEX idx_date_range (start_date, end_date)
);
