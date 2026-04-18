-- Add missing product availability fields
-- Migration to add always_available, dispatch_time, and show_made_on_order_badge columns

ALTER TABLE products 
ADD COLUMN IF NOT EXISTS always_available TINYINT(1) DEFAULT 0 COMMENT '0=stock management, 1=always available',
ADD COLUMN IF NOT EXISTS dispatch_time VARCHAR(255) NULL COMMENT 'Dispatch time in days',
ADD COLUMN IF NOT EXISTS show_made_on_order_badge TINYINT(1) DEFAULT 0 COMMENT '0=hide badge, 1=show made on order badge';

-- Update existing products to have default values
UPDATE products 
SET always_available = 0, 
    show_made_on_order_badge = 0 
WHERE always_available IS NULL OR show_made_on_order_badge IS NULL;
