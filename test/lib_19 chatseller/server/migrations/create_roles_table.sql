CREATE TABLE roles (
    role_id BIGINT AUTO_INCREMENT PRIMARY KEY
        COMMENT 'Unique role record ID',

    user_id BIGINT NOT NULL
        COMMENT 'Assigned user ID',

    website_id BIGINT NOT NULL
        COMMENT 'Related website ID',

    role ENUM(
        'user',
        'admin',
        'supplier',
        'reseller',
        'delivery',
        'manager',
        'catalog_manager'
    )
        DEFAULT 'admin'
        COMMENT 'User role name',

    permissions JSON NULL
        COMMENT 'Role permissions in JSON',

    platform ENUM('WEB','APP','BOTH')
        DEFAULT 'BOTH'
        COMMENT 'Applicable platform',

    status ENUM('active','inactive','suspended')
        DEFAULT 'active'
        COMMENT 'Role status',

    assigned_by BIGINT NULL
        COMMENT 'Assigned by user ID',

    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        COMMENT 'Role assigned time',

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        COMMENT 'Record created time',

    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP
        COMMENT 'Last updated time',

    INDEX idx_user_id (user_id),
    INDEX idx_website_id (website_id),
    INDEX idx_role (role),
    INDEX idx_status (status)

) COMMENT='Master table for user roles and permissions (web and app)';
