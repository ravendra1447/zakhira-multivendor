-- Add vendor_id column to websites table
ALTER TABLE websites 
ADD COLUMN vendor_id VARCHAR(100) NULL AFTER domain,
ADD INDEX idx_vendor_id (vendor_id);
