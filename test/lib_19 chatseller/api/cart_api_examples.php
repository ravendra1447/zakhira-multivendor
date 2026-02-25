<?php
/**
 * Cart API Examples
 * This file demonstrates how to use the cart API endpoints
 */

// Base URL for your server
$baseUrl = "http://localhost:3000/api/cart";

/**
 * Get user cart with all items
 * GET /api/cart/get-cart/{userId}
 */
function getUserCart($userId) {
    $url = "$baseUrl/get-cart/$userId";
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    $data = json_decode($response, true);
    
    if ($httpCode == 200 && $data['success']) {
        echo "Cart found with " . count($data['items']) . " items\n";
        return $data;
    } else {
        echo "Error getting cart: " . $data['error'] . "\n";
        return null;
    }
}

/**
 * Add item to cart
 * POST /api/cart/add-item
 */
function addItemToCart($userId, $productId, $quantity = 1, $price, $size = null, $color = null) {
    $url = "$baseUrl/add-item";
    
    $data = [
        'userId' => $userId,
        'productId' => $productId,
        'quantity' => $quantity,
        'price' => $price
    ];
    
    if ($size) $data['size'] = $size;
    if ($color) $data['color'] = $color;
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_POST, true);
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    $data = json_decode($response, true);
    
    if ($httpCode == 200 && $data['success']) {
        echo "Item added to cart successfully\n";
        return true;
    } else {
        echo "Error adding item: " . $data['error'] . "\n";
        return false;
    }
}

/**
 * Update cart item quantity
 * PUT /api/cart/update-item/{itemId}
 */
function updateCartItem($itemId, $quantity) {
    $url = "$baseUrl/update-item/$itemId";
    
    $data = ['quantity' => $quantity];
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'PUT');
    curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    $data = json_decode($response, true);
    
    if ($httpCode == 200 && $data['success']) {
        echo "Item updated successfully\n";
        return true;
    } else {
        echo "Error updating item: " . $data['error'] . "\n";
        return false;
    }
}

/**
 * Remove item from cart
 * DELETE /api/cart/remove-item/{itemId}
 */
function removeCartItem($itemId) {
    $url = "$baseUrl/remove-item/$itemId";
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'DELETE');
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    $data = json_decode($response, true);
    
    if ($httpCode == 200 && $data['success']) {
        echo "Item removed successfully\n";
        return true;
    } else {
        echo "Error removing item: " . $data['error'] . "\n";
        return false;
    }
}

/**
 * Clear entire cart
 * DELETE /api/cart/clear-cart/{userId}
 */
function clearCart($userId) {
    $url = "$baseUrl/clear-cart/$userId";
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_CUSTOMREQUEST, 'DELETE');
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    $data = json_decode($response, true);
    
    if ($httpCode == 200 && $data['success']) {
        echo "Cart cleared successfully\n";
        return true;
    } else {
        echo "Error clearing cart: " . $data['error'] . "\n";
        return false;
    }
}

/**
 * Get cart item count
 * GET /api/cart/cart-count/{userId}
 */
function getCartCount($userId) {
    $url = "$baseUrl/cart-count/$userId";
    
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
    
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    $data = json_decode($response, true);
    
    if ($httpCode == 200 && $data['success']) {
        echo "Cart has " . $data['count'] . " items\n";
        return $data['count'];
    } else {
        echo "Error getting cart count: " . $data['error'] . "\n";
        return 0;
    }
}

// Example usage:
/*
// Add item to cart
addItemToCart(1, 5, 2, 29.99, 'M', 'Blue');

// Get cart contents
$cart = getUserCart(1);

// Get cart count
$count = getCartCount(1);

// Update item quantity (assuming item ID is 1)
updateCartItem(1, 3);

// Remove item (assuming item ID is 1)
removeCartItem(1);

// Clear entire cart
clearCart(1);
*/

?>
