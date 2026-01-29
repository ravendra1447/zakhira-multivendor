# Cart API Documentation

## Overview
This API provides complete cart functionality for your e-commerce application. It handles cart creation, item management, and user cart tracking.

## Database Tables
- `carts` - Stores user cart information
- `cart_items` - Stores individual cart items with product details

## API Endpoints

### 1. Get User Cart
**GET** `/api/cart/get-cart/:userId`

Retrieves the user's cart with all items and product details.

**Response:**
```json
{
  "success": true,
  "cart": {
    "id": 1,
    "user_id": 123,
    "updated_at": "2026-01-29T11:33:00.000Z"
  },
  "items": [
    {
      "id": 1,
      "cart_id": 1,
      "product_id": 5,
      "quantity": 2,
      "price": "29.99",
      "size": "M",
      "color": "Blue",
      "name": "Product Name",
      "description": "Product description",
      "image_url": "product.jpg"
    }
  ]
}
```

### 2. Add Item to Cart
**POST** `/api/cart/add-item`

Adds a new item to the user's cart or updates quantity if item already exists.

**Request Body:**
```json
{
  "userId": 123,
  "productId": 5,
  "quantity": 2,
  "price": 29.99,
  "size": "M",
  "color": "Blue"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Item added to cart"
}
```

### 3. Update Cart Item
**PUT** `/api/cart/update-item/:itemId`

Updates the quantity of a specific cart item.

**Request Body:**
```json
{
  "quantity": 3
}
```

**Response:**
```json
{
  "success": true,
  "message": "Item updated"
}
```

### 4. Remove Item from Cart
**DELETE** `/api/cart/remove-item/:itemId`

Removes a specific item from the cart.

**Response:**
```json
{
  "success": true,
  "message": "Item removed from cart"
}
```

### 5. Clear Cart
**DELETE** `/api/cart/clear-cart/:userId`

Removes all items from the user's cart.

**Response:**
```json
{
  "success": true,
  "message": "Cart cleared"
}
```

### 6. Get Cart Count
**GET** `/api/cart/cart-count/:userId`

Returns the total number of items in the user's cart.

**Response:**
```json
{
  "success": true,
  "count": 5
}
```

## Usage Examples

### JavaScript/Node.js
```javascript
// Add item to cart
fetch('/api/cart/add-item', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    userId: 1,
    productId: 5,
    quantity: 2,
    price: 29.99,
    size: 'M',
    color: 'Blue'
  })
});

// Get cart
fetch('/api/cart/get-cart/1')
  .then(res => res.json())
  .then(data => console.log(data));
```

### PHP
See `cart_api_examples.php` for complete PHP implementation examples.

## Features

- **Automatic Cart Creation**: Creates a new cart for users who don't have one
- **Item Consolidation**: Combines identical items (same product, size, color) by updating quantity
- **Product Details**: Joins with products table to get product information
- **Error Handling**: Comprehensive error handling with meaningful messages
- **Flexible Attributes**: Supports size and color options for products

## Integration Notes

The cart API is already integrated into the main server at `/api/cart/*`. Make sure your server is running to access these endpoints.

## Database Schema

### carts table
- `id` (INT, PRIMARY KEY, AUTO_INCREMENT)
- `user_id` (INT, UNIQUE)
- `updated_at` (TIMESTAMP)

### cart_items table
- `id` (INT, PRIMARY KEY, AUTO_INCREMENT)
- `cart_id` (INT, FOREIGN KEY)
- `product_id` (INT, FOREIGN KEY)
- `quantity` (INT, DEFAULT 1)
- `price` (DECIMAL(10,2))
- `size` (VARCHAR(50), NULLABLE)
- `color` (VARCHAR(50), NULLABLE)
