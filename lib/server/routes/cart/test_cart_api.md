# Cart API Testing

## Quick Test

1. Start server: `node server.js`
2. Set user ID: `CartService.setUserId(1)`
3. Test add item:
```bash
curl -X POST http://localhost:3000/api/cart/add-item \
  -H "Content-Type: application/json" \
  -d '{"userId": 1, "productId": 5, "quantity": 2, "price": 29.99}'
```
4. Test get cart: `curl http://localhost:3000/api/cart/get-cart/1`

## Flutter Test
```dart
CartService.setUserId(1);
await CartService.loadCartFromServer();
```
