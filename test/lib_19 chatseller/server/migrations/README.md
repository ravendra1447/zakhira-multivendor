# Database Migration Guide

## Adding Marketplace Enabled Field

This migration adds `marketplace_enabled` column to the products table.

### MySQL Database (Server)

Run the following SQL on your MySQL database:

```sql
ALTER TABLE products 
ADD COLUMN marketplace_enabled TINYINT(1) DEFAULT 0 COMMENT 'Enable product in marketplace (0=disabled, 1=enabled)';

-- Update existing products to have default marketplace_enabled = 0
UPDATE products SET marketplace_enabled = 0 WHERE marketplace_enabled IS NULL;
```

Or use the migration file:
```bash
mysql -u chatuser -p chat_db < server/migrations/add_marketplace_enabled_field.sql
```

## Adding Stock Management Fields

This migration adds `stock_mode` and `stock_by_color_size` columns to the products table.

### MySQL Database (Server)

Run the following SQL on your MySQL database:

```sql
ALTER TABLE products 
ADD COLUMN stock_mode VARCHAR(20) DEFAULT 'simple' COMMENT 'Stock mode: simple or color_size',
ADD COLUMN stock_by_color_size JSON NULL COMMENT 'Stock data by color and size: {color: {size: qty}}';

-- Update existing products to have default stock_mode
UPDATE products SET stock_mode = 'simple' WHERE stock_mode IS NULL;
```

Or use the migration file:
```bash
mysql -u chatuser -p chat_db < server/migrations/add_stock_fields.sql
```

### SQLite Database (Local - Flutter App)

The local database migration is handled automatically by the app. The database version has been incremented to 3, and the migration will run automatically when the app starts.

### Database Schema

**Products Table Structure:**

```sql
CREATE TABLE products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  category TEXT,
  available_qty TEXT NOT NULL,
  description TEXT,
  status TEXT NOT NULL DEFAULT 'draft',
  price_slabs TEXT,
  attributes TEXT,
  selected_attribute_values TEXT,
  variations TEXT,
  sizes TEXT,
  images TEXT,
  marketplace_enabled INTEGER DEFAULT 0,
  stock_mode TEXT DEFAULT 'simple',              -- NEW FIELD
  stock_by_color_size TEXT,                     -- NEW FIELD (JSON)
  created_at TEXT,
  updated_at TEXT,
  server_id INTEGER,
  synced INTEGER DEFAULT 0
);
```

### Field Descriptions

- **stock_mode**: 
  - Type: `VARCHAR(20)` (MySQL) / `TEXT` (SQLite)
  - Default: `'simple'`
  - Values: `'simple'` or `'color_size'`
  - Description: Indicates whether the product uses simple stock or color & size based stock

- **stock_by_color_size**: 
  - Type: `JSON` (MySQL) / `TEXT` (SQLite - stores JSON string)
  - Default: `NULL`
  - Format: `{"color_name": {"size": quantity}}`
  - Example: `{"red": {"S": 10, "M": 20, "L": 15}, "blue": {"S": 5, "M": 10}}`
  - Description: Stores stock quantity for each color and size combination. Only used when `stock_mode = 'color_size'`

### Notes

- For **simple stock mode**: `stock_by_color_size` will be `NULL`, and `available_qty` contains the total quantity
- For **color_size stock mode**: `stock_by_color_size` contains the detailed breakdown, and `available_qty` is calculated as the sum of all quantities
- The `variations` field still contains stock data in each variation object for easy access, but the primary source of truth is the `stock_by_color_size` column


