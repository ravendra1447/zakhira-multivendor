-- Add status field to product_variants table
-- This will allow better control over variant visibility

ALTER TABLE product_variants 
ADD COLUMN status TINYINT(1) DEFAULT 1 COMMENT '1=active, 0=inactive';

-- Update existing records to set status based on stock and product stock mode
UPDATE product_variants pv
SET status = CASE 
    WHEN pv.stock > 0 THEN 1 
    WHEN pv.stock = 0 THEN 
        CASE 
            WHEN EXISTS (
                SELECT 1 FROM products p 
                WHERE p.id = pv.product_id 
                AND (p.stock_mode = 'always_available' OR p.stock_mode = 'Unlimited' OR p.stock_maintane_type = 'Unlimited')
            ) THEN 1
            ELSE 0 
        END
    ELSE 0 
END;

-- Add index for better performance
CREATE INDEX idx_product_variants_status ON product_variants(status);
CREATE INDEX idx_product_variants_product_status ON product_variants(product_id, status);
