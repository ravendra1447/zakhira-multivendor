-- Migration to ensure profile_settings table exists with proper structure
-- Run this migration if profile_settings table doesn't exist or needs updates

CREATE TABLE IF NOT EXISTS `profile_settings` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `legal_business_name` varchar(255) DEFAULT NULL,
  `business_type` varchar(100) DEFAULT NULL,
  `business_category` varchar(255) DEFAULT NULL,
  `gst_no` varchar(50) DEFAULT NULL,
  `phone_number` varchar(20) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `email` varchar(255) DEFAULT NULL,
  `website` varchar(255) DEFAULT NULL,
  `business_description` text DEFAULT NULL,
  `about` text DEFAULT NULL,
  `profile_image` varchar(500) DEFAULT NULL,
  `upi_qr_code` varchar(500) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Add index for better performance
CREATE INDEX IF NOT EXISTS `idx_profile_user_id` ON `profile_settings` (`user_id`);
