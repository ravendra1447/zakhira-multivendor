-- Create companies table
CREATE TABLE companies (
    company_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    company_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_company_name (company_name)
);

-- Create branches table
CREATE TABLE branches (
    branch_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    company_id BIGINT NOT NULL,
    branch_name VARCHAR(255) NOT NULL,
    city VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (company_id) REFERENCES companies(company_id) ON DELETE CASCADE,
    INDEX idx_company_branch (company_id),
    INDEX idx_branch_name (branch_name),
    INDEX idx_city (city)
);

-- Add company and branch columns to users table
ALTER TABLE users 
ADD COLUMN company_id BIGINT NULL,
ADD COLUMN branch_id BIGINT NULL,
ADD INDEX idx_user_company (company_id),
ADD INDEX idx_user_branch (branch_id),
ADD FOREIGN KEY (company_id) REFERENCES companies(company_id) ON DELETE SET NULL,
ADD FOREIGN KEY (branch_id) REFERENCES branches(branch_id) ON DELETE SET NULL;

-- Add company, branch and assigned admin columns to orders table
ALTER TABLE orders 
ADD COLUMN company_id BIGINT NULL,
ADD COLUMN branch_id BIGINT NULL,
ADD COLUMN assigned_admin_id BIGINT NULL,
ADD INDEX idx_order_company (company_id),
ADD INDEX idx_order_branch (branch_id),
ADD INDEX idx_order_assigned_admin (assigned_admin_id),
ADD FOREIGN KEY (company_id) REFERENCES companies(company_id) ON DELETE SET NULL,
ADD FOREIGN KEY (branch_id) REFERENCES branches(branch_id) ON DELETE SET NULL,
ADD FOREIGN KEY (assigned_admin_id) REFERENCES users(user_id) ON DELETE SET NULL;

-- Add company and branch columns to products table for branch-wise product management
ALTER TABLE products 
ADD COLUMN company_id BIGINT NULL,
ADD COLUMN branch_id BIGINT NULL,
ADD COLUMN published_by_admin_id BIGINT NULL,
ADD INDEX idx_product_company (company_id),
ADD INDEX idx_product_branch (branch_id),
ADD INDEX idx_product_published_by (published_by_admin_id),
ADD FOREIGN KEY (company_id) REFERENCES companies(company_id) ON DELETE SET NULL,
ADD FOREIGN KEY (branch_id) REFERENCES branches(branch_id) ON DELETE SET NULL,
ADD FOREIGN KEY (published_by_admin_id) REFERENCES users(user_id) ON DELETE SET NULL;

-- Insert sample data for testing
INSERT INTO companies (company_name) VALUES ('Test Company 1'), ('Test Company 2');

INSERT INTO branches (company_id, branch_name, city) VALUES 
(1, 'Main Branch', 'Delhi'),
(1, 'Secondary Branch', 'Mumbai'),
(2, 'Head Office', 'Bangalore');
