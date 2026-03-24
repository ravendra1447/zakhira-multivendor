-- Add FCM token columns to users table
ALTER TABLE users 
ADD COLUMN fcm_token TEXT NULL,
ADD COLUMN fcm_platform ENUM('android', 'ios') NULL,
ADD COLUMN fcm_enabled BOOLEAN DEFAULT TRUE,
ADD COLUMN fcm_updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP;

-- Create index for FCM token queries
CREATE INDEX idx_users_fcm_token ON users(fcm_token);
CREATE INDEX idx_users_fcm_enabled ON users(fcm_enabled);

-- Update existing users to have FCM enabled by default
UPDATE users SET fcm_enabled = TRUE WHERE fcm_enabled IS NULL;
