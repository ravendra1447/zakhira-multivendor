-- Create chat_rooms table for marketplace chat
CREATE TABLE IF NOT EXISTS chat_rooms (
    id INT AUTO_INCREMENT PRIMARY KEY,
    product_id INT NOT NULL,
    buyer_id BIGINT NOT NULL,
    seller_id BIGINT NOT NULL,
    status ENUM('active', 'closed', 'archived') DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_product_id (product_id),
    INDEX idx_buyer_id (buyer_id),
    INDEX idx_seller_id (seller_id),
    INDEX idx_status (status),
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    FOREIGN KEY (buyer_id) REFERENCES users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (seller_id) REFERENCES users(user_id) ON DELETE CASCADE,
    UNIQUE KEY unique_buyer_seller_product (buyer_id, seller_id, product_id)
);

-- Create chat_messages table for storing chat messages
CREATE TABLE IF NOT EXISTS chat_messages (
    id INT AUTO_INCREMENT PRIMARY KEY,
    chat_room_id INT NOT NULL,
    sender_id BIGINT NOT NULL,
    message_type ENUM('text', 'image', 'product_info') NOT NULL DEFAULT 'text',
    message_content TEXT NOT NULL,
    encrypted_content TEXT NOT NULL, 
    product_info JSON,
    is_read BOOLEAN DEFAULT FALSE,
    is_delivered BOOLEAN DEFAULT FALSE, 
    delivery_time TIMESTAMP NULL, 
    read_time TIMESTAMP NULL, 
    encryption_key VARCHAR(255) NOT NULL, 
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_chat_room_sender (chat_room_id, sender_id),
    INDEX idx_created_at (created_at),
    INDEX idx_read_status (is_read),
    INDEX idx_delivery_status (is_delivered),
    FOREIGN KEY (chat_room_id) REFERENCES chat_rooms(id) ON DELETE CASCADE,
    FOREIGN KEY (sender_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Create chat_participants table for tracking participant status
CREATE TABLE IF NOT EXISTS chat_participants (
    id INT AUTO_INCREMENT PRIMARY KEY,
    chat_room_id INT NOT NULL,
    user_id BIGINT NOT NULL,
    last_read_message_id INT NULL,
    is_online BOOLEAN DEFAULT FALSE,
    last_seen_at TIMESTAMP NULL,
    last_active_at TIMESTAMP NULL, 
    typing_status BOOLEAN DEFAULT FALSE, 
    typing_since TIMESTAMP NULL, 
    
    INDEX idx_chat_room_id (chat_room_id),
    INDEX idx_user_id (user_id),
    INDEX idx_is_online (is_online),
    INDEX idx_user_status (user_id, is_online),
    INDEX idx_last_active (last_active_at),
    FOREIGN KEY (chat_room_id) REFERENCES chat_rooms(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (last_read_message_id) REFERENCES chat_messages(id) ON DELETE SET NULL,
    UNIQUE KEY unique_chat_room_user (chat_room_id, user_id)
);

-- Create chat_message_attachments table for file attachments
CREATE TABLE IF NOT EXISTS chat_message_attachments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    message_id INT NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_size INT NOT NULL,
    file_type VARCHAR(50) NOT NULL,
    thumbnail_path VARCHAR(500) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_message_id (message_id),
    FOREIGN KEY (message_id) REFERENCES chat_messages(id) ON DELETE CASCADE
);

-- Note: Sample data commented out to avoid foreign key constraint errors
-- Insert sample data for testing (optional)
-- Make sure you have actual products with these IDs before uncommenting
/*
INSERT INTO chat_rooms (product_id, buyer_id, seller_id, status) VALUES 
(1, 2, 1, 'active'),
(2, 3, 1, 'active');

INSERT INTO chat_messages (chat_room_id, sender_id, message_type, message_content, product_info) VALUES 
(1, 2, 'text', 'Hello, I am interested in this product', NULL),
(1, 1, 'text', 'Hi! How can I help you?', NULL),
(1, 2, 'product_info', 'Can you tell me more about this product?', '{"product_id": 1, "product_name": "Sample Product", "price": 750.0, "image": "https://example.com/image.jpg"}');

INSERT INTO chat_participants (chat_room_id, user_id, is_online, last_seen_at) VALUES 
(1, 2, TRUE, NOW()),
(1, 1, FALSE, DATE_SUB(NOW(), INTERVAL 1 HOUR));
*/
