@echo off
echo Running migration to fix order_items schema...

REM Try to find node.js
where node >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Found Node.js, running migration...
    node run_migration.js
) else (
    echo Node.js not found in PATH
    echo Please run this migration manually in your MySQL client:
    echo.
    echo ALTER TABLE order_items ADD COLUMN product_name VARCHAR(255) AFTER color;
    echo ALTER TABLE order_items ADD COLUMN product_price DECIMAL(10,2) AFTER product_name;
    echo.
    pause
)
